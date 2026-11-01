import NotchCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var launchAtLoginService: LaunchAtLoginService?
    var hudService: SystemHUDService?
    var calendarService: CalendarService?
    var onToggleDemoTrack: (() -> Void)?
    var onTestHUD: (() -> Void)?

    var body: some View {
        Form {
            if let launchAtLoginService {
                Section("General") {
                    Toggle(
                        "Launch DynamicNotch at login",
                        isOn: Binding(
                            get: { launchAtLoginService.isEnabled },
                            set: { launchAtLoginService.setEnabled($0) }
                        )
                    )
                    if let error = launchAtLoginService.lastErrorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Display") {
                Toggle("Show on all displays", isOn: $settings.showOnAllDisplays)
                Text("When off, the notch only appears on the built-in display (or the primary display).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Live Activities & HUD") {
                Toggle("Show Now Playing wings when closed", isOn: $settings.enableCompactNowPlaying)
                Toggle("Show Volume, Brightness & Battery HUD in notch", isOn: $settings.enableHUDReplacement)
                Toggle("Suppress native macOS HUD overlay (Accessibility)", isOn: $settings.suppressNativeHUD)
                    .disabled(!settings.enableHUDReplacement)

                if let hudService {
                    HStack {
                        Image(
                            systemName: hudService.isAccessibilityTrusted
                                ? "checkmark.shield.fill"
                                : "exclamationmark.shield.fill"
                        )
                        .foregroundStyle(hudService.isAccessibilityTrusted ? .green : .orange)
                        Text(
                            hudService.isAccessibilityTrusted
                                ? "Accessibility permission granted"
                                : "Accessibility permission needed to hide native macOS HUD"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                        if !hudService.isAccessibilityTrusted {
                            Button("Grant Access…") {
                                hudService.requestAccessibilityPermission()
                            }
                            .controlSize(.small)
                        } else {
                            Button("Refresh") {
                                hudService.refreshAccessibilityTrust()
                            }
                            .controlSize(.small)
                        }
                    }
                }

                Toggle("Show upcoming Calendar event in notch", isOn: $settings.enableCalendarWidget)
                if let calendarService, settings.enableCalendarWidget, !calendarService.isAuthorized {
                    HStack {
                        Text("Calendar permission not yet granted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Connect Calendar…") {
                            calendarService.requestAccess()
                        }
                        .controlSize(.small)
                    }
                }

                Toggle("Auto-open File Shelf when dragging files near notch", isOn: $settings.autoOpenShelfOnFileDrag)
            }

            Section("Behavior") {
                LabeledContent("Hover open delay") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(settings.hoverOpenDelayMs) },
                                set: { settings.hoverOpenDelayMs = Int($0) }
                            ),
                            in: 0...600,
                            step: 20
                        )
                        Text("\(settings.hoverOpenDelayMs) ms")
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }

            if onToggleDemoTrack != nil || onTestHUD != nil {
                Section("Preview") {
                    HStack(spacing: 12) {
                        if let onToggleDemoTrack {
                            Button("Toggle Demo Track", action: onToggleDemoTrack)
                        }
                        if let onTestHUD {
                            Button("Test HUD Peek", action: onTestHUD)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}
