import NotchCore
import SwiftUI

/// Transient heads-up display rendered below the physical notch in `.peek` state.
struct NotchPeekHUDView: View {
    let event: HUDEvent

    private var accentColor: Color {
        switch event.kind {
        case .volume(_, let isMuted):
            return isMuted ? .red : .white
        case .brightness:
            return .yellow
        case .battery(let status):
            if status.isCharging { return .green }
            if status.isLowBattery { return .orange }
            return .white
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 20, alignment: .center)
                .contentTransition(.symbolEffect(.replace))

            Text(event.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.16))
                    Capsule(style: .continuous)
                        .fill(accentColor)
                        .frame(width: max(0, proxy.size.width * CGFloat(event.normalizedValue)))
                        .animation(.spring(response: 0.22, dampingFraction: 0.85), value: event.normalizedValue)
                }
            }
            .frame(height: 6)

            Text(event.valueText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
