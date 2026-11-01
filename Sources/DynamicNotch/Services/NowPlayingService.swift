import AppKit
import Darwin
import Foundation
import NotchCore
import Observation

/// Observes system-wide "Now Playing" state and dispatches playback commands.
///
/// Combines:
/// 1. Zero-latency `DistributedNotificationCenter` events from Apple Music and Spotify.
/// 2. Live 1-second position synchronization via AppleScript so scrubbing in Apple Music
///    or Spotify is reflected on the notch immediately.
/// 3. Locale-safe AppleScript + `MediaRemote.framework` command and seek dispatch.
@MainActor
@Observable
final class NowPlayingService {
    private(set) var currentItem: NowPlayingItem?
    private(set) var isDemoMode: Bool = false

    @ObservationIgnored private var distributedObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var positionSyncTask: Task<Void, Never>?
    @ObservationIgnored private var immediateSyncTask: Task<Void, Never>?
    @ObservationIgnored private var lastArtworkTrackKey: String?
    @ObservationIgnored private var lastLocalSeekDate: Date = .distantPast
    @ObservationIgnored private let mediaRemote = MediaRemoteBridge()

    func start() {
        let center = DistributedNotificationCenter.default()

        let names = [
            NowPlayingNotificationParser.appleMusicNotification,
            NowPlayingNotificationParser.spotifyNotification,
        ]
        for name in names {
            let token = center.addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let info = notification.userInfo ?? [:]
                let parsed = NowPlayingNotificationParser.parseDetailed(
                    notificationName: name,
                    userInfo: info
                )
                MainActor.assumeIsolated {
                    self?.handleNotificationUpdate(parsed)
                }
            }
            distributedObservers.append(token)
        }

        startPositionSyncLoop()
    }

    func stop() {
        let center = DistributedNotificationCenter.default()
        distributedObservers.forEach { center.removeObserver($0) }
        distributedObservers.removeAll()
        artworkTask?.cancel()
        positionSyncTask?.cancel()
        immediateSyncTask?.cancel()
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        if isDemoMode, var item = currentItem {
            item.elapsedTime = item.currentElapsedTime(at: .now)
            item.isPlaying.toggle()
            item.playbackRate = item.isPlaying ? 1.0 : 0.0
            item.timestamp = .now
            currentItem = item
            return
        }

        if let bundleID = currentItem?.appBundleIdentifier {
            Task.detached {
                await AppleScriptPlayerBridge.sendCommand("playpause", to: bundleID)
            }
        } else {
            _ = mediaRemote.sendCommand(.togglePlayPause)
        }

        if var item = currentItem {
            item.elapsedTime = item.currentElapsedTime(at: .now)
            item.isPlaying.toggle()
            item.playbackRate = item.isPlaying ? 1.0 : 0.0
            item.timestamp = .now
            currentItem = item
        }
    }

    func nextTrack() {
        if isDemoMode {
            cycleDemoTrack(forward: true)
            return
        }
        if let bundleID = currentItem?.appBundleIdentifier {
            Task.detached {
                await AppleScriptPlayerBridge.sendCommand("next track", to: bundleID)
            }
        } else {
            _ = mediaRemote.sendCommand(.nextTrack)
        }
    }

    func previousTrack() {
        if isDemoMode {
            cycleDemoTrack(forward: false)
            return
        }
        if let bundleID = currentItem?.appBundleIdentifier {
            Task.detached {
                await AppleScriptPlayerBridge.sendCommand("previous track", to: bundleID)
            }
        } else {
            _ = mediaRemote.sendCommand(.previousTrack)
        }
    }

    func seek(to seconds: TimeInterval) {
        guard var item = currentItem else { return }
        let clamped = max(0, item.duration > 0 ? min(seconds, item.duration) : seconds)
        item.elapsedTime = clamped
        item.timestamp = .now
        currentItem = item
        lastLocalSeekDate = .now

        guard !isDemoMode else { return }
        if let bundleID = item.appBundleIdentifier {
            immediateSyncTask?.cancel()
            immediateSyncTask = Task { [weak self] in
                await AppleScriptPlayerBridge.setPosition(clamped, in: bundleID)
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await self?.refreshFromRunningPlayers(ignoreLocalSeekGuard: true)
            }
        } else {
            mediaRemote.setElapsedTime(clamped)
        }
    }

    func activateSourceApp() {
        guard let bundleID = currentItem?.appBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Demo Mode

    func toggleDemoMode() {
        if isDemoMode {
            isDemoMode = false
            currentItem = nil
            Task { [weak self] in
                await self?.refreshFromRunningPlayers(ignoreLocalSeekGuard: true)
            }
        } else {
            isDemoMode = true
            demoIndex = 0
            currentItem = Self.demoTracks[0]
        }
    }

    @ObservationIgnored private var demoIndex: Int = 0

    private func cycleDemoTrack(forward: Bool) {
        let count = Self.demoTracks.count
        demoIndex = (demoIndex + (forward ? 1 : count - 1)) % count
        var next = Self.demoTracks[demoIndex]
        next.timestamp = .now
        currentItem = next
    }

    private static let demoTracks: [NowPlayingItem] = [
        NowPlayingItem(
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            duration: 243,
            elapsedTime: 48,
            isPlaying: true,
            appBundleIdentifier: "com.apple.Music",
            appName: "Music"
        ),
        NowPlayingItem(
            title: "Veridis Quo",
            artist: "Daft Punk",
            album: "Discovery",
            duration: 345,
            elapsedTime: 112,
            isPlaying: true,
            appBundleIdentifier: "com.spotify.client",
            appName: "Spotify"
        ),
        NowPlayingItem(
            title: "Starboy",
            artist: "The Weeknd",
            album: "Starboy",
            duration: 230,
            elapsedTime: 19,
            isPlaying: true,
            appBundleIdentifier: "com.apple.Music",
            appName: "Music"
        ),
    ]

    // MARK: - Internal Updates & Live Position Sync

    private func startPositionSyncLoop() {
        positionSyncTask?.cancel()
        positionSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshFromRunningPlayers(ignoreLocalSeekGuard: false)
                let isActivelyPlaying = self?.currentItem?.isPlaying == true && self?.isDemoMode == false
                try? await Task.sleep(for: isActivelyPlaying ? .seconds(1) : .seconds(3))
            }
        }
    }

    private func handleNotificationUpdate(
        _ parsedResult: (item: NowPlayingItem, hasExplicitElapsedTime: Bool)?
    ) {
        isDemoMode = false
        guard let parsedResult else {
            currentItem = nil
            lastArtworkTrackKey = nil
            return
        }

        var newItem = parsedResult.item
        let newKey = Self.trackKey(for: newItem)

        if let existing = currentItem, Self.trackKey(for: existing) == newKey {
            if let existingArtwork = existing.artworkData {
                newItem.artworkData = existingArtwork
            }
            if newItem.duration <= 0 && existing.duration > 0 {
                newItem.duration = existing.duration
            }
            // Apple Music's notification omits elapsed time. Preserve the current
            // extrapolated position until the immediate AppleScript sync completes.
            if !parsedResult.hasExplicitElapsedTime {
                newItem.elapsedTime = existing.currentElapsedTime(at: .now)
                newItem.timestamp = .now
            }
        }

        currentItem = newItem

        // Immediately query the player for the exact `player position` (e.g. after a seek in Apple Music).
        if !parsedResult.hasExplicitElapsedTime, let bundleID = newItem.appBundleIdentifier {
            immediateSyncTask?.cancel()
            immediateSyncTask = Task { [weak self] in
                guard let self else { return }
                if Date.now.timeIntervalSince(self.lastLocalSeekDate) < 0.6 { return }
                await self.refreshFromRunningPlayers(
                    preferredBundleID: bundleID,
                    ignoreLocalSeekGuard: false
                )
            }
        }

        if newItem.artworkData == nil, let bundleID = newItem.appBundleIdentifier {
            lastArtworkTrackKey = newKey
            artworkTask?.cancel()
            artworkTask = Task { [weak self] in
                if let data = await AppleScriptPlayerBridge.fetchArtwork(from: bundleID),
                   !Task.isCancelled {
                    self?.applyArtwork(data, forKey: newKey)
                }
            }
        }
    }

    private func applyArtwork(_ data: Data, forKey key: String) {
        guard var item = currentItem, Self.trackKey(for: item) == key else { return }
        item.artworkData = data
        currentItem = item
    }

    func refreshFromRunningPlayers(
        preferredBundleID: String? = nil,
        ignoreLocalSeekGuard: Bool
    ) async {
        guard !isDemoMode else { return }
        if !ignoreLocalSeekGuard, Date.now.timeIntervalSince(lastLocalSeekDate) < 0.8 {
            return
        }

        let running = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        var candidates = ["com.apple.Music", "com.spotify.client"]
        if let preferredBundleID, let idx = candidates.firstIndex(of: preferredBundleID) {
            candidates.remove(at: idx)
            candidates.insert(preferredBundleID, at: 0)
        }

        for bundleID in candidates where running.contains(bundleID) {
            guard let snapshot = await AppleScriptPlayerBridge.fetchSnapshot(from: bundleID) else {
                continue
            }
            if !ignoreLocalSeekGuard, Date.now.timeIntervalSince(lastLocalSeekDate) < 0.8 {
                return
            }

            var merged = snapshot
            let key = Self.trackKey(for: snapshot)
            if let existing = currentItem, Self.trackKey(for: existing) == key {
                merged.artworkData = existing.artworkData
            }
            currentItem = merged

            if merged.artworkData == nil, lastArtworkTrackKey != key {
                lastArtworkTrackKey = key
                if let art = await AppleScriptPlayerBridge.fetchArtwork(from: bundleID) {
                    applyArtwork(art, forKey: key)
                }
            }
            return
        }
    }

    private static func trackKey(for item: NowPlayingItem) -> String {
        "\(item.appBundleIdentifier ?? "")|\(item.title)|\(item.artist)"
    }
}

// MARK: - Dynamic MediaRemote Bridge

private final class MediaRemoteBridge: Sendable {
    enum Command: UInt32 {
        case play = 0
        case pause = 1
        case togglePlayPause = 2
        case stop = 3
        case nextTrack = 4
        case previousTrack = 5
    }

    private typealias SendCommandFn = @convention(c) (UInt32, AnyObject?) -> Bool
    private typealias SetElapsedTimeFn = @convention(c) (Double) -> Void

    private nonisolated(unsafe) let sendCommandPtr: SendCommandFn?
    private nonisolated(unsafe) let setElapsedTimePtr: SetElapsedTimeFn?

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        if let handle = dlopen(path, RTLD_LAZY) {
            if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
                sendCommandPtr = unsafeBitCast(sym, to: SendCommandFn.self)
            } else {
                sendCommandPtr = nil
            }
            if let sym = dlsym(handle, "MRMediaRemoteSetElapsedTime") {
                setElapsedTimePtr = unsafeBitCast(sym, to: SetElapsedTimeFn.self)
            } else {
                setElapsedTimePtr = nil
            }
        } else {
            sendCommandPtr = nil
            setElapsedTimePtr = nil
        }
    }

    func sendCommand(_ command: Command) -> Bool {
        sendCommandPtr?(command.rawValue, nil) ?? false
    }

    func setElapsedTime(_ elapsed: TimeInterval) {
        setElapsedTimePtr?(elapsed)
    }
}

// MARK: - Locale-Safe AppleScript Player Bridge

private enum AppleScriptPlayerBridge {
    static func sendCommand(_ command: String, to bundleID: String) async {
        let appName = bundleID == "com.spotify.client" ? "Spotify" : "Music"
        let source = "tell application \"\(appName)\" to \(command)"
        _ = await runOsascript(source)
    }

    static func setPosition(_ seconds: TimeInterval, in bundleID: String) async {
        let appName = bundleID == "com.spotify.client" ? "Spotify" : "Music"
        // Use integer tenths of a second (`(tenths / 10)`) to avoid any locale decimal separator issues.
        let tenths = max(0, Int((seconds * 10.0).rounded()))
        let source = "tell application \"\(appName)\" to set player position to (\(tenths) / 10)"
        _ = await runOsascript(source)
    }

    static func fetchSnapshot(from bundleID: String) async -> NowPlayingItem? {
        let isSpotify = bundleID == "com.spotify.client"
        let appName = isSpotify ? "Spotify" : "Music"
        // Multiply by 1000 and round to integer inside AppleScript so the output
        // is plain integer milliseconds regardless of system decimal separator (`.` vs `,`).
        let script = """
        tell application "\(appName)"
            if it is running then
                set pState to player state as string
                if pState is "playing" or pState is "paused" then
                    set tName to name of current track
                    set tArtist to artist of current track
                    set tAlbum to album of current track
                    set rawDur to duration of current track
                    set rawPos to player position
                    set durMs to (round (rawDur * 1000)) as integer
                    set posMs to (round (rawPos * 1000)) as integer
                    return pState & "|||" & tName & "|||" & tArtist & "|||" & tAlbum & "|||" & (durMs as string) & "|||" & (posMs as string)
                end if
            end if
        end tell
        return ""
        """
        guard let output = await runOsascript(script), !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }
        let isPlaying = parts[0].lowercased().contains("playing")
        let title = parts[1]
        guard !title.isEmpty else { return nil }
        let artist = parts[2]
        let album = parts[3]

        let rawDurMs = Double(parts[4].filter { $0.isNumber || $0 == "-" }) ?? 0
        // Spotify's `duration of current track` is already in ms (so `* 1000` makes it > 1_000_000).
        // Apple Music's `duration of current track` is in seconds (so `* 1000` is milliseconds).
        let duration: TimeInterval
        if isSpotify && rawDurMs > 10_000_000 {
            duration = rawDurMs / 1_000_000.0
        } else {
            duration = rawDurMs / 1000.0
        }

        let posMs = Double(parts[5].filter { $0.isNumber || $0 == "-" }) ?? 0
        let elapsed = max(0, posMs / 1000.0)

        return NowPlayingItem(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsedTime: elapsed,
            isPlaying: isPlaying,
            playbackRate: isPlaying ? 1.0 : 0.0,
            appBundleIdentifier: bundleID,
            appName: appName,
            timestamp: .now
        )
    }

    static func fetchArtwork(from bundleID: String) async -> Data? {
        if bundleID == "com.spotify.client" {
            let script = """
            tell application "Spotify"
                if it is running and (player state is playing or player state is paused) then
                    return artwork url of current track
                end if
            end tell
            return ""
            """
            guard let urlString = await runOsascript(script),
                  let url = URL(string: urlString),
                  let (data, _) = try? await URLSession.shared.data(from: url) else {
                return nil
            }
            return data
        }
        return nil
    }

    private static func runOsascript(_ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
