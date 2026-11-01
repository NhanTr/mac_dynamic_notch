import AppKit
import NotchCore
import SwiftUI

/// Compact live-activity wings rendered on the left and right of the physical notch.
struct NotchCompactView: View {
    let item: NowPlayingItem
    let notchWidth: CGFloat
    let wingWidth: CGFloat
    let topRadius: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            // Left wing: mini album artwork
            HStack {
                Spacer(minLength: 0)
                ArtworkThumbnail(data: item.artworkData, size: 20, cornerRadius: 5)
                Spacer(minLength: 0)
            }
            .frame(width: wingWidth)

            // Physical camera housing gap
            Spacer()
                .frame(width: notchWidth)

            // Right wing: animated equalizer bars
            HStack {
                Spacer(minLength: 0)
                AudioEqualizerView(isPlaying: item.isPlaying)
                    .frame(width: 20, height: 14)
                Spacer(minLength: 0)
            }
            .frame(width: wingWidth)
        }
        .padding(.horizontal, topRadius)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

/// Reusable album artwork view with a fallback gradient emblem.
struct ArtworkThumbnail: View {
    let data: Data?
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.28, blue: 0.48),
                        Color(red: 0.42, green: 0.25, blue: 0.92),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.44, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Animated 4-bar equalizer waveform.
struct AudioEqualizerView: View {
    let isPlaying: Bool

    private static let phases: [Double] = [0.0, 1.3, 2.5, 0.8]
    private static let speeds: [Double] = [4.2, 5.4, 3.7, 4.9]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isPlaying)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2.5) {
                ForEach(0..<4, id: \.self) { index in
                    let fraction = barHeightFraction(index: index, time: t)
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.36, blue: 0.56),
                                    Color(red: 0.58, green: 0.38, blue: 0.98),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3, height: max(3, 14 * fraction))
                }
            }
        }
    }

    private func barHeightFraction(index: Int, time: TimeInterval) -> CGFloat {
        guard isPlaying else { return 0.22 }
        let wave = sin(time * Self.speeds[index] + Self.phases[index])
        return CGFloat(0.32 + 0.68 * ((wave + 1.0) / 2.0))
    }
}
