import AppKit
import NotchCore
import Observation

/// Per-display state and coordinator of the notch.
@MainActor
@Observable
final class NotchViewModel {
    private(set) var layout: NotchLayout
    private(set) var isHovering = false
    private(set) var isDebouncedHoverOpen = false
    private(set) var isDraggingOverNotch = false
    var isPinnedOpen = false
    var enableCompactNowPlaying = true
    var autoOpenShelfOnFileDrag = true
    var enableCalendarWidget = true
    var selectedTab: NotchTab = .dashboard
    private(set) var activeHUD: HUDEvent?

    let nowPlayingService: NowPlayingService
    let hudService: SystemHUDService
    let batteryService: BatteryService
    let shelfService: ShelfService
    let calendarService: CalendarService

    /// Delay before a hover opens the notch, to avoid opening on accidental fly-overs.
    var hoverOpenDelay: Duration = .milliseconds(120)
    /// Delay before the notch closes after the pointer leaves.
    var hoverCloseDelay: Duration = .milliseconds(250)
    /// Duration a `.peek` HUD stays visible before auto-dismissing.
    var hudDisplayDuration: Duration = .milliseconds(1600)

    @ObservationIgnored private var pendingHoverTask: Task<Void, Never>?
    @ObservationIgnored private var hudDismissTask: Task<Void, Never>?

    init(
        layout: NotchLayout,
        nowPlayingService: NowPlayingService,
        hudService: SystemHUDService,
        batteryService: BatteryService,
        shelfService: ShelfService,
        calendarService: CalendarService
    ) {
        self.layout = layout
        self.nowPlayingService = nowPlayingService
        self.hudService = hudService
        self.batteryService = batteryService
        self.shelfService = shelfService
        self.calendarService = calendarService
    }

    var coordinator: ActivityCoordinator {
        ActivityCoordinator(
            isHovering: isDebouncedHoverOpen,
            isDraggingOverNotch: isDraggingOverNotch,
            isPinnedOpen: isPinnedOpen,
            enableCompactNowPlaying: enableCompactNowPlaying,
            activeHUD: activeHUD,
            nowPlaying: nowPlayingService.currentItem,
            battery: batteryService.status,
            selectedTab: selectedTab
        )
    }

    /// Current resolved visual state (`.closed`, `.compact`, `.peek`, `.open`).
    var state: NotchState {
        coordinator.resolvedState
    }

    /// Active tab when expanded.
    var effectiveTab: NotchTab {
        coordinator.effectiveTab
    }

    func update(layout: NotchLayout) {
        self.layout = layout
    }

    /// Area (global screen coordinates) where the panel should accept mouse events.
    var interactiveRect: CGRect {
        layout.hoverRect(for: state)
    }

    /// Generous region near the top center of the display that triggers the shelf when dragging files.
    var fileDragActivationRect: CGRect {
        let open = layout.openRect
        return open.insetBy(dx: -40, dy: -24)
    }

    /// Feed the latest pointer location (global screen coordinates) and file-drag state.
    func pointerMoved(to point: CGPoint, isDraggingFiles: Bool = false) {
        if autoOpenShelfOnFileDrag && isDraggingFiles {
            let insideDragZone = fileDragActivationRect.contains(point)
            if insideDragZone != isDraggingOverNotch {
                isDraggingOverNotch = insideDragZone
                if insideDragZone {
                    selectedTab = .shelf
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
        } else if isDraggingOverNotch {
            isDraggingOverNotch = false
        }

        let inside = interactiveRect.contains(point)
        guard inside != isHovering else { return }
        isHovering = inside
        scheduleHover(open: inside, after: inside ? hoverOpenDelay : hoverCloseDelay)
    }

    /// Presents a transient HUD alert in `.peek` mode and auto-dismisses it after `hudDisplayDuration`.
    func presentHUD(_ event: HUDEvent) {
        hudDismissTask?.cancel()
        activeHUD = event
        hudDismissTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.hudDisplayDuration)
            guard !Task.isCancelled else { return }
            self.activeHUD = nil
        }
    }

    func dismissHUD() {
        hudDismissTask?.cancel()
        hudDismissTask = nil
        activeHUD = nil
    }

    func open() {
        applyHoverOpen(true)
    }

    func close() {
        isPinnedOpen = false
        isDraggingOverNotch = false
        applyHoverOpen(false)
    }

    func toggle() {
        state == .open ? close() : open()
    }

    private func scheduleHover(open: Bool, after delay: Duration) {
        pendingHoverTask?.cancel()
        guard open != isDebouncedHoverOpen else { return }
        pendingHoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.applyHoverOpen(open)
        }
    }

    private func applyHoverOpen(_ open: Bool) {
        pendingHoverTask?.cancel()
        pendingHoverTask = nil
        guard open != isDebouncedHoverOpen else { return }
        if open {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        isDebouncedHoverOpen = open
    }
}
