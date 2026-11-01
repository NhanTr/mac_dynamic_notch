# DynamicNotch

A Dynamic Island–style notch for macOS with live Now Playing wings, Volume/Brightness/Battery HUD, upcoming Calendar events, and a drag-and-drop File Shelf with AirDrop.

## Requirements
- macOS 15+
- Xcode 16+ / Swift 6

## Quick Install (from GitHub)
Clone the repository and run the one-step installer (no Apple Developer certificate required):

```bash
git clone https://github.com/NhanTr/mac_dynamic_notch.git DynamicNotch
cd DynamicNotch
./scripts/install.sh
```

This builds `DynamicNotch.app` natively on your Mac, installs it into `/Applications`, and launches it immediately without Gatekeeper quarantine warnings.

## Development Build & Package DMG
```bash
./scripts/bundle.sh debug        # or: ./scripts/bundle.sh release
open build/DynamicNotch.app

./scripts/package_dmg.sh         # creates build/DynamicNotch-1.0.0.dmg
```

Run tests:
```bash
swift test
```

You can also open `Package.swift` in Xcode and run the `DynamicNotch` scheme.

## Features
- **4 Morphing States**: `.closed` (flush with hardware notch), `.compact` (artwork + animated equalizer wings), `.peek` (transient HUD below notch), and `.open` (interactive dashboard & shelf).
- **Now Playing**: Real-time Apple Music & Spotify updates via `DistributedNotificationCenter`, bidirectional 1-second position synchronization, locale-safe AppleScript seek & transport, `MediaRemote` command dispatch, and a built-in Demo Track mode.
- **Volume, Brightness & Battery HUD**: Event-driven `CoreAudio` volume/mute monitoring, `DisplayServices` brightness control, `IOKit.ps` battery/charging notifications, and optional native macOS `OSDUIHelper` suppression via `CGEventTap` (Accessibility).
- **Calendar & Launch at Login**: `EventKit` integration showing your next upcoming event in the notch header, and `SMAppService.mainApp` Launch at Login in Settings.
- **File Shelf + AirDrop**: Drag files near the notch to auto-open the Shelf tab, stash files temporarily, drag them back out, or share via AirDrop with one click.

## Layout
```text
Sources/
├── NotchCore/          # Pure logic: geometry, layout, coordinator, models, parsers (unit-tested)
└── DynamicNotch/
    ├── App/            # @main, AppDelegate, settings model
    ├── Core/           # NotchPanel, NotchWindowManager, NotchViewModel, NotchShape
    ├── Services/       # NowPlaying, SystemHUD, Battery, Shelf, Calendar, LaunchAtLogin
    ├── Views/          # NotchRootView, NotchCompactView, NotchPeekHUDView, NotchExpandedView
    └── Settings/       # Settings window
Support/Info.plist      # Bundle metadata (LSUIElement agent app + permissions)
scripts/bundle.sh       # Builds and wraps the binary into a .app
scripts/package_dmg.sh  # Packages a release .dmg installer
```

## Roadmap
- [x] P0 – Project setup
- [x] P1 – Core notch (geometry, panel, morphing shape, hover, click-through, multi-display)
- [x] P2 – Now Playing (compact wings, animated equalizer, expanded player, seek & transport)
- [x] P3 – Volume & Brightness HUD (CoreAudio + DisplayServices + `.peek` state + quick sliders)
- [x] P4 – Live activities (`ActivityCoordinator` priority engine + IOKit battery/charging monitor)
- [x] P5 – File shelf & widgets (drag-near-notch auto-open, file tray, drag-out, AirDrop)
- [x] P6 – Polish & release (Launch at Login, Calendar EventKit widget, native HUD suppression, DMG script)
