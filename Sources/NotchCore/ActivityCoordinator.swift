import Foundation

/// Pure priority & state resolver for the notch.
///
/// Priority order (highest to lowest):
/// 1. User interaction (`isHovering`, `isDraggingOverNotch`, or `isPinnedOpen`) -> `.open`
/// 2. Transient HUD alert (`activeHUD != nil`) -> `.peek`
/// 3. Ongoing live activity (`nowPlaying != nil` when compact live activities are enabled) -> `.compact`
/// 4. Idle -> `.closed`
public struct ActivityCoordinator: Sendable, Equatable {
    public var isHovering: Bool = false
    public var isDraggingOverNotch: Bool = false
    public var isPinnedOpen: Bool = false
    public var enableCompactNowPlaying: Bool = true
    public var activeHUD: HUDEvent?
    public var nowPlaying: NowPlayingItem?
    public var battery: BatteryStatus?
    public var selectedTab: NotchTab = .dashboard

    public init(
        isHovering: Bool = false,
        isDraggingOverNotch: Bool = false,
        isPinnedOpen: Bool = false,
        enableCompactNowPlaying: Bool = true,
        activeHUD: HUDEvent? = nil,
        nowPlaying: NowPlayingItem? = nil,
        battery: BatteryStatus? = nil,
        selectedTab: NotchTab = .dashboard
    ) {
        self.isHovering = isHovering
        self.isDraggingOverNotch = isDraggingOverNotch
        self.isPinnedOpen = isPinnedOpen
        self.enableCompactNowPlaying = enableCompactNowPlaying
        self.activeHUD = activeHUD
        self.nowPlaying = nowPlaying
        self.battery = battery
        self.selectedTab = selectedTab
    }

    /// Resolves the target visual state of the notch from all active inputs.
    public var resolvedState: NotchState {
        if isHovering || isDraggingOverNotch || isPinnedOpen {
            return .open
        }
        if activeHUD != nil {
            return .peek
        }
        if enableCompactNowPlaying, let nowPlaying, !nowPlaying.title.isEmpty {
            return .compact
        }
        return .closed
    }

    /// Resolves which tab should be displayed when the notch is open.
    public var effectiveTab: NotchTab {
        if isDraggingOverNotch {
            return .shelf
        }
        return selectedTab
    }
}
