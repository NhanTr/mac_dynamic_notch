import AppKit
import NotchCore
import SwiftUI
import UniformTypeIdentifiers

/// Interactive dashboard and file shelf inside the `.open` notch state.
struct NotchExpandedView: View {
    @Bindable var viewModel: NotchViewModel

    var body: some View {
        VStack(spacing: 10) {
            HeaderBar(viewModel: viewModel)

            Group {
                switch viewModel.effectiveTab {
                case .dashboard:
                    DashboardTabView(
                        nowPlayingService: viewModel.nowPlayingService,
                        hudService: viewModel.hudService
                    )
                case .shelf:
                    FileShelfTabView(shelfService: viewModel.shelfService)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 8)
        .foregroundStyle(.white)
    }
}

// MARK: - Top Header Bar

private struct HeaderBar: View {
    @Bindable var viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.everyMinute) { context in
                HStack(spacing: 6) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            if let battery = viewModel.batteryService.status {
                BatteryBadge(status: battery)
            }

            if viewModel.enableCalendarWidget {
                CalendarBadge(service: viewModel.calendarService)
            }

            Spacer(minLength: 8)

            // Tab Switcher
            HStack(spacing: 4) {
                TabPillButton(
                    title: "Media",
                    symbol: "play.circle.fill",
                    isSelected: viewModel.effectiveTab == .dashboard
                ) {
                    viewModel.selectedTab = .dashboard
                }

                TabPillButton(
                    title: "Shelf",
                    symbol: "tray.and.arrow.down.fill",
                    badgeCount: viewModel.shelfService.items.count,
                    isSelected: viewModel.effectiveTab == .shelf
                ) {
                    viewModel.selectedTab = .shelf
                }
            }
            .padding(2)
            .background(.white.opacity(0.08), in: Capsule(style: .continuous))

            Button {
                viewModel.isPinnedOpen.toggle()
            } label: {
                Image(systemName: viewModel.isPinnedOpen ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(viewModel.isPinnedOpen ? .yellow : .white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help(viewModel.isPinnedOpen ? "Unpin notch" : "Pin notch open")
        }
    }
}

private struct BatteryBadge: View {
    let status: BatteryStatus

    private var color: Color {
        if status.isCharging { return .green }
        if status.isLowBattery { return .orange }
        return .white.opacity(0.75)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text("\(status.percentage)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.white.opacity(0.08), in: Capsule(style: .continuous))
    }
}

private struct CalendarBadge: View {
    let service: CalendarService

    var body: some View {
        if let event = service.nextEvent {
            TimelineView(.everyMinute) { context in
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.cyan)
                    Text(event.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 110, alignment: .leading)
                    Text(event.relativeBadge(at: context.date))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                .onTapGesture {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }
        } else if !service.isAuthorized {
            Button {
                service.requestAccess()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.cyan)
                    Text("Calendar")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.white.opacity(0.08), in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Connect Apple Calendar to show upcoming events")
        }
    }
}

private struct TabPillButton: View {
    let title: String
    let symbol: String
    var badgeCount: Int = 0
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.22), in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? .black : .white.opacity(0.8))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.clear),
                in: Capsule(style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dashboard Tab (Now Playing + Quick Sliders)

private struct DashboardTabView: View {
    let nowPlayingService: NowPlayingService
    let hudService: SystemHUDService

    var body: some View {
        HStack(spacing: 12) {
            NowPlayingCardView(service: nowPlayingService)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            QuickSlidersColumn(hudService: hudService)
                .frame(width: 158)
        }
    }
}

private struct NowPlayingCardView: View {
    let service: NowPlayingService
    @State private var isScrubbing = false
    @State private var scrubRatio: Double = 0

    var body: some View {
        if let item = service.currentItem {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ArtworkThumbnail(data: item.artworkData, size: 52, cornerRadius: 10)
                        .onTapGesture {
                            service.activateSourceApp()
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            AudioEqualizerView(isPlaying: item.isPlaying)
                                .frame(width: 18, height: 12)
                        }

                        Text(item.artist.isEmpty ? "Unknown Artist" : item.artist)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            if let appName = item.appName {
                                Text(appName)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1.5)
                                    .background(.white.opacity(0.12), in: Capsule())
                            }
                            if service.isDemoMode {
                                Button("Exit Demo") {
                                    service.toggleDemoMode()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.cyan)
                            }
                        }
                    }
                }

                // Scrubber + Transport Row
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    let liveProgress = item.progress(at: context.date)
                    let displayProgress = isScrubbing ? scrubRatio : liveProgress
                    let displayElapsed = isScrubbing
                        ? (item.duration * scrubRatio)
                        : item.currentElapsedTime(at: context.date)

                    HStack(spacing: 10) {
                        Text(Self.formatTime(displayElapsed))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isScrubbing ? .white : .white.opacity(0.55))
                            .frame(width: 30, alignment: .leading)

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .fill(.white.opacity(0.15))
                                    .frame(height: isScrubbing ? 7 : 5)
                                Capsule(style: .continuous)
                                    .fill(.white)
                                    .frame(
                                        width: max(0, proxy.size.width * displayProgress),
                                        height: isScrubbing ? 7 : 5
                                    )
                            }
                            .frame(maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        guard item.duration > 0, proxy.size.width > 0 else { return }
                                        isScrubbing = true
                                        scrubRatio = max(0, min(1, value.location.x / proxy.size.width))
                                    }
                                    .onEnded { value in
                                        guard item.duration > 0, proxy.size.width > 0 else {
                                            isScrubbing = false
                                            return
                                        }
                                        let ratio = max(0, min(1, value.location.x / proxy.size.width))
                                        isScrubbing = false
                                        service.seek(to: item.duration * ratio)
                                    }
                            )
                        }
                        .frame(height: 14)

                        Text(Self.formatTime(item.duration))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 30, alignment: .trailing)

                        HStack(spacing: 8) {
                            TransportButton(symbol: "backward.fill", size: 11) {
                                service.previousTrack()
                            }
                            TransportButton(
                                symbol: item.isPlaying ? "pause.fill" : "play.fill",
                                size: 13
                            ) {
                                service.togglePlayPause()
                            }
                            TransportButton(symbol: "forward.fill", size: 11) {
                                service.nextTrack()
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing Playing")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Play music in Apple Music or Spotify")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                    Button {
                        service.toggleDemoMode()
                    } label: {
                        Label("Preview Demo Track", systemImage: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private static func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct QuickSlidersColumn: View {
    let hudService: SystemHUDService

    var body: some View {
        VStack(spacing: 8) {
            MiniSliderRow(
                symbol: hudService.isMuted || hudService.volume <= 0.001
                    ? "speaker.slash.fill"
                    : "speaker.wave.2.fill",
                tint: hudService.isMuted ? .red : .white,
                value: hudService.isMuted ? 0 : hudService.volume,
                onIconTap: { hudService.toggleMute(emitHUD: false) },
                onChange: { hudService.setVolume($0, emitHUD: false) }
            )

            MiniSliderRow(
                symbol: "sun.max.fill",
                tint: .yellow,
                value: hudService.brightness,
                onIconTap: nil,
                onChange: { hudService.setBrightness($0, emitHUD: false) }
            )
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct MiniSliderRow: View {
    let symbol: String
    let tint: Color
    let value: Float
    let onIconTap: (() -> Void)?
    let onChange: (Float) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                onIconTap?()
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.14))
                    Capsule(style: .continuous)
                        .fill(tint)
                        .frame(width: max(0, proxy.size.width * CGFloat(min(1, max(0, value)))))
                }
                .frame(height: 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            guard proxy.size.width > 0 else { return }
                            let ratio = Float(max(0, min(1, drag.location.x / proxy.size.width)))
                            onChange(ratio)
                        }
                )
            }

            Text("\(Int((min(1, max(0, value)) * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 30, alignment: .trailing)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - File Shelf Tab

private struct FileShelfTabView: View {
    let shelfService: ShelfService
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            if shelfService.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isDropTargeted ? .cyan : .white.opacity(0.55))
                    Text("Drop files here to stash temporarily")
                        .font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 8) {
                        Text("Drag files near the notch to open automatically")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                        Button("Add Files…") {
                            pickFiles()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.14), in: Capsule())
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isDropTargeted ? Color.cyan : Color.white.opacity(0.18),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isDropTargeted ? Color.cyan.opacity(0.12) : Color.white.opacity(0.04))
                        )
                )
            } else {
                HStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(shelfService.items) { item in
                                ShelfItemCard(
                                    item: item,
                                    onReveal: { shelfService.revealInFinder(item) },
                                    onRemove: { shelfService.remove(item) }
                                )
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(spacing: 6) {
                        Button {
                            shelfService.shareViaAirDrop()
                        } label: {
                            Label("AirDrop", systemImage: "paperplane.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            pickFiles()
                        } label: {
                            Label("Add", systemImage: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            shelfService.clearAll()
                        } label: {
                            Text("Clear")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 82)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            shelfService.handleDrop(providers: providers)
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            shelfService.addFiles(panel.urls)
        }
    }
}

private struct ShelfItemCard: View {
    let item: ShelfItem
    let onReveal: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .onTapGesture(perform: onReveal)

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -4)
            }

            Text(item.displayName)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 68)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
    }
}
