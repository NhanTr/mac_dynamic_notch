import AppKit
import NotchCore
import SwiftUI

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("DynamicNotch", systemImage: "macbook") {
            MenuBarContent(appDelegate: appDelegate)
        }

        Settings {
            SettingsView(
                settings: appDelegate.settings,
                launchAtLoginService: appDelegate.windowManager?.launchAtLoginService,
                hudService: appDelegate.windowManager?.hudService,
                calendarService: appDelegate.windowManager?.calendarService,
                onToggleDemoTrack: { appDelegate.windowManager?.nowPlayingService.toggleDemoMode() },
                onTestHUD: {
                    let volume = appDelegate.windowManager?.hudService.volume ?? 0.65
                    let muted = appDelegate.windowManager?.hudService.isMuted ?? false
                    appDelegate.windowManager?.broadcastHUD(
                        HUDEvent(kind: .volume(volume, isMuted: muted))
                    )
                }
            )
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    private(set) var windowManager: NotchWindowManager?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon, no main menu. (Also set via LSUIElement in the bundle.)
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let manager = NotchWindowManager(settings: settings)
        manager.start()
        windowManager = manager
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowManager?.stop()
    }
}

private struct MenuBarContent: View {
    let appDelegate: AppDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Toggle Demo Music Track") {
            appDelegate.windowManager?.nowPlayingService.toggleDemoMode()
        }

        Button("Preview Volume HUD Peek") {
            let volume = appDelegate.windowManager?.hudService.volume ?? 0.65
            let muted = appDelegate.windowManager?.hudService.isMuted ?? false
            appDelegate.windowManager?.broadcastHUD(
                HUDEvent(kind: .volume(volume, isMuted: muted))
            )
        }

        Divider()

        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit DynamicNotch") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
