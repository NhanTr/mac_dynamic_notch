import CoreGraphics

/// Visual state of the notch.
public enum NotchState: Sendable, Equatable {
    /// Matches the physical notch (or the virtual pill).
    case closed
    /// Widened horizontal wings alongside the notch for live activities (e.g. Now Playing).
    case compact
    /// Temporary heads-up display (volume, brightness, power state changes).
    case peek
    /// Fully expanded interactive panel.
    case open
}

/// Tunable visual constants for the notch.
public struct NotchStyle: Sendable, Equatable {
    public var closedTopRadius: CGFloat
    public var closedBottomRadius: CGFloat
    public var peekTopRadius: CGFloat
    public var peekBottomRadius: CGFloat
    public var openTopRadius: CGFloat
    public var openBottomRadius: CGFloat
    /// Width of each horizontal wing added on the left and right in `.compact` mode.
    public var compactWingWidth: CGFloat
    /// Extra height below the physical notch in `.peek` mode so HUD content is never obscured.
    public var peekDropHeight: CGFloat
    /// Minimum total width of the `.peek` HUD pill.
    public var peekMinWidth: CGFloat
    /// Size of the expanded shape, including the top "ears".
    public var openSize: CGSize
    /// Transparent room around the open shape so its shadow is not clipped.
    public var shadowPadding: CGFloat
    /// Extra hover tolerance around the visible shape.
    public var hoverTolerance: CGFloat

    public init(
        closedTopRadius: CGFloat = 6,
        closedBottomRadius: CGFloat = 12,
        peekTopRadius: CGFloat = 12,
        peekBottomRadius: CGFloat = 20,
        openTopRadius: CGFloat = 18,
        openBottomRadius: CGFloat = 28,
        compactWingWidth: CGFloat = 54,
        peekDropHeight: CGFloat = 40,
        peekMinWidth: CGFloat = 330,
        openSize: CGSize = CGSize(width: 580, height: 204),
        shadowPadding: CGFloat = 24,
        hoverTolerance: CGFloat = 10
    ) {
        self.closedTopRadius = closedTopRadius
        self.closedBottomRadius = closedBottomRadius
        self.peekTopRadius = peekTopRadius
        self.peekBottomRadius = peekBottomRadius
        self.openTopRadius = openTopRadius
        self.openBottomRadius = openBottomRadius
        self.compactWingWidth = compactWingWidth
        self.peekDropHeight = peekDropHeight
        self.peekMinWidth = peekMinWidth
        self.openSize = openSize
        self.shadowPadding = shadowPadding
        self.hoverTolerance = hoverTolerance
    }

    public static let `default` = NotchStyle()
}

/// Computes every rect the app needs for one display, in global screen coordinates.
///
/// The panel has a fixed size (big enough for the open state); all morphing happens
/// inside SwiftUI so the window never resizes during animations.
public struct NotchLayout: Sendable, Equatable {
    public let screenFrame: CGRect
    public let geometry: NotchGeometry
    public let style: NotchStyle

    public init(metrics: ScreenMetrics, style: NotchStyle = .default) {
        self.screenFrame = metrics.frame
        self.geometry = NotchGeometry(metrics: metrics)
        self.style = style
    }

    // MARK: Shape sizes (local)

    public var closedShapeSize: CGSize {
        CGSize(
            width: geometry.size.width + style.closedTopRadius * 2,
            height: geometry.size.height
        )
    }

    public var compactShapeSize: CGSize {
        CGSize(
            width: geometry.size.width + (style.compactWingWidth + style.closedTopRadius) * 2,
            height: geometry.size.height
        )
    }

    public var peekShapeSize: CGSize {
        CGSize(
            width: max(style.peekMinWidth, compactShapeSize.width),
            height: geometry.size.height + style.peekDropHeight
        )
    }

    public var openShapeSize: CGSize {
        CGSize(
            width: max(style.openSize.width, compactShapeSize.width),
            height: max(style.openSize.height, peekShapeSize.height)
        )
    }

    public func shapeSize(for state: NotchState) -> CGSize {
        switch state {
        case .closed: return closedShapeSize
        case .compact: return compactShapeSize
        case .peek: return peekShapeSize
        case .open: return openShapeSize
        }
    }

    public func topRadius(for state: NotchState) -> CGFloat {
        switch state {
        case .closed, .compact: return style.closedTopRadius
        case .peek: return style.peekTopRadius
        case .open: return style.openTopRadius
        }
    }

    public func bottomRadius(for state: NotchState) -> CGFloat {
        switch state {
        case .closed, .compact: return style.closedBottomRadius
        case .peek: return style.peekBottomRadius
        case .open: return style.openBottomRadius
        }
    }

    // MARK: Global rects

    public var panelSize: CGSize {
        CGSize(
            width: openShapeSize.width + style.shadowPadding * 2,
            height: openShapeSize.height + style.shadowPadding
        )
    }

    public var panelFrame: CGRect {
        topCenteredRect(size: panelSize)
    }

    public var closedRect: CGRect {
        topCenteredRect(size: closedShapeSize)
    }

    public var compactRect: CGRect {
        topCenteredRect(size: compactShapeSize)
    }

    public var peekRect: CGRect {
        topCenteredRect(size: peekShapeSize)
    }

    public var openRect: CGRect {
        topCenteredRect(size: openShapeSize)
    }

    public func rect(for state: NotchState) -> CGRect {
        switch state {
        case .closed: return closedRect
        case .compact: return compactRect
        case .peek: return peekRect
        case .open: return openRect
        }
    }

    /// The area in which the pointer counts as "over the notch" for a given state.
    /// Extends above the top edge so a pointer pinned to the screen edge still hits.
    public func hoverRect(for state: NotchState) -> CGRect {
        let base = rect(for: state)
        let tolerance = style.hoverTolerance
        return CGRect(
            x: base.minX - tolerance,
            y: base.minY - tolerance,
            width: base.width + tolerance * 2,
            height: base.height + tolerance * 2
        )
    }

    private func topCenteredRect(size: CGSize) -> CGRect {
        CGRect(
            x: (screenFrame.midX - size.width / 2).rounded(),
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
