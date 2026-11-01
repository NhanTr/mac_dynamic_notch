import Foundation
import Observation

/// User preferences backed by `UserDefaults`.
@MainActor
@Observable
final class AppSettings {
    static let didChangeNotification = Notification.Name("AppSettingsDidChange")

    private enum Key {
        static let showOnAllDisplays = "showOnAllDisplays"
        static let hoverOpenDelayMs = "hoverOpenDelayMs"
        static let enableCompactNowPlaying = "enableCompactNowPlaying"
        static let enableHUDReplacement = "enableHUDReplacement"
        static let suppressNativeHUD = "suppressNativeHUD"
        static let autoOpenShelfOnFileDrag = "autoOpenShelfOnFileDrag"
        static let enableCalendarWidget = "enableCalendarWidget"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var showOnAllDisplays: Bool {
        didSet { persist(showOnAllDisplays, Key.showOnAllDisplays) }
    }

    var hoverOpenDelayMs: Int {
        didSet { persist(hoverOpenDelayMs, Key.hoverOpenDelayMs) }
    }

    var enableCompactNowPlaying: Bool {
        didSet { persist(enableCompactNowPlaying, Key.enableCompactNowPlaying) }
    }

    var enableHUDReplacement: Bool {
        didSet { persist(enableHUDReplacement, Key.enableHUDReplacement) }
    }

    var suppressNativeHUD: Bool {
        didSet { persist(suppressNativeHUD, Key.suppressNativeHUD) }
    }

    var autoOpenShelfOnFileDrag: Bool {
        didSet { persist(autoOpenShelfOnFileDrag, Key.autoOpenShelfOnFileDrag) }
    }

    var enableCalendarWidget: Bool {
        didSet { persist(enableCalendarWidget, Key.enableCalendarWidget) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.showOnAllDisplays: true,
            Key.hoverOpenDelayMs: 120,
            Key.enableCompactNowPlaying: true,
            Key.enableHUDReplacement: true,
            Key.suppressNativeHUD: true,
            Key.autoOpenShelfOnFileDrag: true,
            Key.enableCalendarWidget: true,
        ])
        showOnAllDisplays = defaults.bool(forKey: Key.showOnAllDisplays)
        hoverOpenDelayMs = defaults.integer(forKey: Key.hoverOpenDelayMs)
        enableCompactNowPlaying = defaults.bool(forKey: Key.enableCompactNowPlaying)
        enableHUDReplacement = defaults.bool(forKey: Key.enableHUDReplacement)
        suppressNativeHUD = defaults.bool(forKey: Key.suppressNativeHUD)
        autoOpenShelfOnFileDrag = defaults.bool(forKey: Key.autoOpenShelfOnFileDrag)
        enableCalendarWidget = defaults.bool(forKey: Key.enableCalendarWidget)
    }

    private func persist(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
