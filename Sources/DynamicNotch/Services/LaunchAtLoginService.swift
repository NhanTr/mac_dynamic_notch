import Foundation
import Observation
import ServiceManagement

/// Manages "Launch at Login" registration via `SMAppService.mainApp`.
@MainActor
@Observable
final class LaunchAtLoginService {
    private(set) var isEnabled: Bool = false
    private(set) var lastErrorMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func setEnabled(_ enabled: Bool) {
        lastErrorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            lastErrorMessage = error.localizedDescription
            refresh()
        }
    }
}
