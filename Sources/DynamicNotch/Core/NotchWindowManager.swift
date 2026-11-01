import AppKit
import NotchCore
import SwiftUI

/// Owns one `NotchPanel` per display and keeps them in sync with screen changes,
/// pointer movement, and system services.
@MainActor
final class NotchWindowManager {
    private struct Entry {
        let panel: NotchPanel
        let viewModel: NotchViewModel
    }

    private var entries: [CGDirectDisplayID: Entry] = [:]
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    let settings: AppSettings
    let nowPlayingService = NowPlayingService()
    let hudService = SystemHUDService()
    let batteryService = BatteryService()
    let shelfService = ShelfService()
    let calendarService = CalendarService()
    let launchAtLoginService = LaunchAtLoginService()

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        nowPlayingService.start()
        hudService.suppressNativeHUD = settings.suppressNativeHUD
        hudService.start()
        batteryService.start()
        calendarService.start()

        hudService.onHUDEvent = { [weak self] event in
            guard let self, self.settings.enableHUDReplacement else { return }
            self.broadcastHUD(event)
        }
        batteryService.onBatteryEvent = { [weak self] event in
            guard let self, self.settings.enableHUDReplacement else { return }
            self.broadcastHUD(event)
        }

        rebuildPanels()
        installPointerMonitors()

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildPanels() }
        })
        observers.append(center.addObserver(
            forName: AppSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildPanels() }
        })
    }

    func stop() {
        nowPlayingService.stop()
        hudService.stop()
        batteryService.stop()
        calendarService.stop()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        entries.values.forEach { $0.panel.close() }
        entries.removeAll()
    }

    func broadcastHUD(_ event: HUDEvent) {
        for entry in entries.values {
            entry.viewModel.presentHUD(event)
        }
    }

    // MARK: - Panels

    private func targetScreens() -> [NSScreen] {
        if settings.showOnAllDisplays { return NSScreen.screens }
        if let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return [notched]
        }
        return NSScreen.screens.first.map { [$0] } ?? []
    }

    private func rebuildPanels() {
        hudService.suppressNativeHUD = settings.suppressNativeHUD
        let screens = targetScreens()
        let wanted = Set(screens.compactMap(\.displayID))

        for (id, entry) in entries where !wanted.contains(id) {
            entry.panel.close()
            entries[id] = nil
        }

        for screen in screens {
            guard let id = screen.displayID else { continue }
            let layout = NotchLayout(metrics: ScreenMetrics(screen: screen))

            if let entry = entries[id] {
                entry.viewModel.update(layout: layout)
                apply(settings: settings, to: entry.viewModel)
                entry.panel.setFrame(layout.panelFrame, display: true)
            } else {
                let viewModel = NotchViewModel(
                    layout: layout,
                    nowPlayingService: nowPlayingService,
                    hudService: hudService,
                    batteryService: batteryService,
                    shelfService: shelfService,
                    calendarService: calendarService
                )
                apply(settings: settings, to: viewModel)
                let panel = NotchPanel(frame: layout.panelFrame)
                let hosting = NSHostingView(rootView: NotchRootView(viewModel: viewModel))
                hosting.sizingOptions = []
                panel.contentView = hosting
                panel.setFrame(layout.panelFrame, display: true)
                panel.orderFrontRegardless()
                entries[id] = Entry(panel: panel, viewModel: viewModel)
            }
        }
    }

    private func apply(settings: AppSettings, to viewModel: NotchViewModel) {
        viewModel.hoverOpenDelay = .milliseconds(settings.hoverOpenDelayMs)
        viewModel.enableCompactNowPlaying = settings.enableCompactNowPlaying
        viewModel.autoOpenShelfOnFileDrag = settings.autoOpenShelfOnFileDrag
        viewModel.enableCalendarWidget = settings.enableCalendarWidget
    }

    // MARK: - Pointer & Drag Tracking

    private func installPointerMonitors() {
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .leftMouseUp,
        ]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let isDrag = event.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.handlePointer(isMouseDragged: isDrag) }
        }) {
            monitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let isDrag = event.type == .leftMouseDragged
            MainActor.assumeIsolated { self?.handlePointer(isMouseDragged: isDrag) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handlePointer(isMouseDragged: Bool) {
        let location = NSEvent.mouseLocation
        let isDraggingFiles: Bool
        if isMouseDragged {
            let dragBoard = NSPasteboard(name: .drag)
            isDraggingFiles = dragBoard.types?.contains(.fileURL) ?? false
        } else {
            isDraggingFiles = false
        }

        for entry in entries.values {
            entry.viewModel.pointerMoved(to: location, isDraggingFiles: isDraggingFiles)
            let activeZone = isDraggingFiles
                ? entry.viewModel.fileDragActivationRect
                : entry.viewModel.interactiveRect
            let shouldIgnore = !activeZone.contains(location)
            if entry.panel.ignoresMouseEvents != shouldIgnore {
                entry.panel.ignoresMouseEvents = shouldIgnore
            }
        }
    }
}

// MARK: - NSScreen helpers

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

extension ScreenMetrics {
    @MainActor
    init(screen: NSScreen) {
        self.init(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryTopRightWidth: screen.auxiliaryTopRightArea?.width
        )
    }
}
