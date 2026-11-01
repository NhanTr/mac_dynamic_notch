#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

/// Renders the DynamicNotch macOS app icon at a given pixel dimension.
func renderIcon(size: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let nsContext = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = nsContext
    let ctx = nsContext.cgContext

    let s = CGFloat(size)
    let scale = s / 1024.0
    ctx.scaleBy(x: scale, y: scale)

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // 1. Outer macOS Squircle Geometry (824x824 centered in 1024x1024)
    let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircleRadius: CGFloat = 186
    let squirclePath = NSBezierPath(
        roundedRect: squircleRect,
        xRadius: squircleRadius,
        yRadius: squircleRadius
    )

    // Subtle outer drop shadow for macOS icon depth
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -18),
        blur: 36,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42)
    )
    NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.14, alpha: 1.0).setFill()
    squirclePath.fill()
    ctx.restoreGState()

    // Clip to squircle
    ctx.saveGState()
    squirclePath.addClip()

    // 2. Rich MacBook Wallpaper Background Gradient (Deep Indigo -> Violet -> Cyan/Magenta glow)
    if let bgGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.05, green: 0.06, blue: 0.14, alpha: 1.0),
            CGColor(red: 0.12, green: 0.10, blue: 0.28, alpha: 1.0),
            CGColor(red: 0.28, green: 0.15, blue: 0.48, alpha: 1.0),
            CGColor(red: 0.16, green: 0.42, blue: 0.72, alpha: 1.0),
        ] as CFArray,
        locations: [0.0, 0.38, 0.75, 1.0]
    ) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: 512, y: 100),
            end: CGPoint(x: 512, y: 924),
            options: []
        )
    }

    // Vibrant radial aurora glow behind the notch
    if let aurora = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.96, green: 0.28, blue: 0.56, alpha: 0.58),
            CGColor(red: 0.38, green: 0.52, blue: 0.98, alpha: 0.25),
            CGColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
        ] as CFArray,
        locations: [0.0, 0.55, 1.0]
    ) {
        ctx.drawRadialGradient(
            aurora,
            startCenter: CGPoint(x: 512, y: 660),
            startRadius: 10,
            endCenter: CGPoint(x: 512, y: 620),
            endRadius: 430,
            options: []
        )
    }

    // 3. Inner Display Screen Bezel & Frosted Menu Bar Strip
    let screenInset: CGFloat = 148
    let screenRect = CGRect(
        x: screenInset,
        y: screenInset,
        width: 1024 - screenInset * 2,
        height: 1024 - screenInset * 2
    )
    let screenRadius: CGFloat = 138
    let screenPath = NSBezierPath(
        roundedRect: screenRect,
        xRadius: screenRadius,
        yRadius: screenRadius
    )

    ctx.saveGState()
    screenPath.addClip()

    // Translucent top menu bar strip
    let menuBarHeight: CGFloat = 96
    let menuBarRect = CGRect(
        x: screenRect.minX,
        y: screenRect.maxY - menuBarHeight,
        width: screenRect.width,
        height: menuBarHeight
    )
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12))
    ctx.fill(menuBarRect)

    // Subtle bottom hairline on menu bar
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    ctx.fill(CGRect(x: screenRect.minX, y: menuBarRect.minY, width: screenRect.width, height: 2))

    // 4. The Signature Dynamic Notch Silhouette (with concave top ears & convex bottom corners)
    let notchTopY = screenRect.maxY
    let notchWidth: CGFloat = 520
    let notchHeight: CGFloat = 250
    let notchBottomY = notchTopY - notchHeight
    let earRadius: CGFloat = 38
    let bottomRadius: CGFloat = 68
    let leftX: CGFloat = 512 - notchWidth / 2
    let rightX: CGFloat = 512 + notchWidth / 2

    let notchPath = CGMutablePath()
    // Start at top-left outer ear
    notchPath.move(to: CGPoint(x: leftX - earRadius, y: notchTopY))
    // Concave top-left ear
    notchPath.addQuadCurve(
        to: CGPoint(x: leftX, y: notchTopY - earRadius),
        control: CGPoint(x: leftX, y: notchTopY)
    )
    // Left vertical edge down to bottom-left corner
    notchPath.addLine(to: CGPoint(x: leftX, y: notchBottomY + bottomRadius))
    // Convex bottom-left corner
    notchPath.addQuadCurve(
        to: CGPoint(x: leftX + bottomRadius, y: notchBottomY),
        control: CGPoint(x: leftX, y: notchBottomY)
    )
    // Bottom horizontal edge
    notchPath.addLine(to: CGPoint(x: rightX - bottomRadius, y: notchBottomY))
    // Convex bottom-right corner
    notchPath.addQuadCurve(
        to: CGPoint(x: rightX, y: notchBottomY + bottomRadius),
        control: CGPoint(x: rightX, y: notchBottomY)
    )
    // Right vertical edge up to top-right ear
    notchPath.addLine(to: CGPoint(x: rightX, y: notchTopY - earRadius))
    // Concave top-right ear
    notchPath.addQuadCurve(
        to: CGPoint(x: rightX + earRadius, y: notchTopY),
        control: CGPoint(x: rightX, y: notchTopY)
    )
    notchPath.closeSubpath()

    // Drop shadow under the Dynamic Notch
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -20),
        blur: 42,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.72)
    )
    ctx.addPath(notchPath)
    ctx.setFillColor(CGColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Subtle glossy rim stroke on the Dynamic Notch
    ctx.saveGState()
    ctx.addPath(notchPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.setLineWidth(3.5)
    ctx.strokePath()
    ctx.restoreGState()

    // 5. Inside the Dynamic Notch:
    // 5a. Subtle FaceTime Camera Lens at the top center
    let lensCenter = CGPoint(x: 512, y: notchTopY - 40)
    let lensRect = CGRect(x: lensCenter.x - 14, y: lensCenter.y - 14, width: 28, height: 28)
    ctx.setFillColor(CGColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1.0))
    ctx.fillEllipse(in: lensRect)
    ctx.setFillColor(CGColor(red: 0.20, green: 0.85, blue: 0.45, alpha: 0.95))
    // Green camera/live indicator dot to the right of lens
    ctx.fillEllipse(in: CGRect(x: lensCenter.x + 28, y: lensCenter.y - 5, width: 10, height: 10))

    // 5b. Left Side: Glowing Album / Play Disc
    let discSize: CGFloat = 116
    let discRect = CGRect(
        x: leftX + 46,
        y: notchBottomY + 48,
        width: discSize,
        height: discSize
    )
    let discPath = NSBezierPath(roundedRect: discRect, xRadius: 30, yRadius: 30)
    ctx.saveGState()
    discPath.addClip()
    if let discGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.98, green: 0.32, blue: 0.52, alpha: 1.0),
            CGColor(red: 0.52, green: 0.24, blue: 0.96, alpha: 1.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawLinearGradient(
            discGrad,
            start: CGPoint(x: discRect.minX, y: discRect.maxY),
            end: CGPoint(x: discRect.maxX, y: discRect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // White play symbol inside the disc
    let playPath = CGMutablePath()
    let cx = discRect.midX + 4
    let cy = discRect.midY
    playPath.move(to: CGPoint(x: cx - 18, y: cy + 24))
    playPath.addLine(to: CGPoint(x: cx - 18, y: cy - 24))
    playPath.addLine(to: CGPoint(x: cx + 22, y: cy))
    playPath.closeSubpath()
    ctx.saveGState()
    ctx.addPath(playPath)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    ctx.fillPath()
    ctx.restoreGState()

    // 5c. Right Side: 5 Vibrant Equalizer Waveform Bars
    let barHeights: [CGFloat] = [54, 96, 122, 78, 46]
    let barWidth: CGFloat = 20
    let barSpacing: CGFloat = 14
    let totalBarsWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * barSpacing
    let barsStartX = rightX - 48 - totalBarsWidth
    let barsCenterY = discRect.midY

    for (idx, h) in barHeights.enumerated() {
        let bx = barsStartX + CGFloat(idx) * (barWidth + barSpacing)
        let barRect = CGRect(x: bx, y: barsCenterY - h / 2, width: barWidth, height: h)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
        ctx.saveGState()
        barPath.addClip()
        if let barGrad = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.24, green: 0.86, blue: 0.98, alpha: 1.0),
                CGColor(red: 0.62, green: 0.38, blue: 0.98, alpha: 1.0),
                CGColor(red: 0.98, green: 0.34, blue: 0.58, alpha: 1.0),
            ] as CFArray,
            locations: [0.0, 0.5, 1.0]
        ) {
            ctx.drawLinearGradient(
                barGrad,
                start: CGPoint(x: bx, y: barRect.maxY),
                end: CGPoint(x: bx, y: barRect.minY),
                options: []
            )
        }
        ctx.restoreGState()
    }

    // 6. Floating HUD Pill Card Below the Notch (symbolizing Volume/Shelf/Live Activity)
    let hudWidth: CGFloat = 420
    let hudHeight: CGFloat = 68
    let hudRect = CGRect(
        x: 512 - hudWidth / 2,
        y: notchBottomY - 126,
        width: hudWidth,
        height: hudHeight
    )
    let hudPath = NSBezierPath(roundedRect: hudRect, xRadius: hudHeight / 2, yRadius: hudHeight / 2)
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -10),
        blur: 24,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.38)
    )
    NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.16, alpha: 0.82).setFill()
    hudPath.fill()
    ctx.restoreGState()

    // HUD border + glowing progress bar inside
    ctx.saveGState()
    NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
    hudPath.lineWidth = 2.5
    hudPath.stroke()

    let trackRect = CGRect(x: hudRect.minX + 32, y: hudRect.midY - 8, width: hudRect.width - 64, height: 16)
    let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: 8, yRadius: 8)
    NSColor(calibratedWhite: 1.0, alpha: 0.16).setFill()
    trackPath.fill()

    let fillRect = CGRect(x: trackRect.minX, y: trackRect.minY, width: trackRect.width * 0.72, height: trackRect.height)
    let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 8, yRadius: 8)
    fillPath.addClip()
    if let fillGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.24, green: 0.86, blue: 0.98, alpha: 1.0),
            CGColor(red: 0.98, green: 0.36, blue: 0.58, alpha: 1.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawLinearGradient(
            fillGrad,
            start: CGPoint(x: fillRect.minX, y: fillRect.midY),
            end: CGPoint(x: fillRect.maxX, y: fillRect.midY),
            options: []
        )
    }
    ctx.restoreGState()

    ctx.restoreGState() // end screenRect clip

    // Dark bezel frame around inner screen
    ctx.saveGState()
    NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.10, alpha: 1.0).setStroke()
    screenPath.lineWidth = 36
    screenPath.stroke()
    ctx.restoreGState()

    // Outer squircle metallic rim highlight
    NSColor(calibratedWhite: 1.0, alpha: 0.22).setStroke()
    squirclePath.lineWidth = 4
    squirclePath.stroke()

    ctx.restoreGState() // end squircle clip
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 1)
    }
    try data.write(to: url)
}

let args = CommandLine.arguments
let outputDir = args.count > 1 ? args[1] : "build/AppIcon.iconset"
let previewPath = args.count > 2 ? args[2] : "build/AppIcon-1024.png"

let fm = FileManager.default
try? fm.removeItem(atPath: outputDir)
try fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let specs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for spec in specs {
    if let rep = renderIcon(size: spec.pixels) {
        let url = URL(fileURLWithPath: outputDir).appendingPathComponent(spec.name)
        try writePNG(rep, to: url)
    }
}

if let previewRep = renderIcon(size: 1024) {
    try writePNG(previewRep, to: URL(fileURLWithPath: previewPath))
}
print("Generated iconset at \(outputDir) and preview at \(previewPath)")
