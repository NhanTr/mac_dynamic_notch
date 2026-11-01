import Foundation

/// Parses distributed notification payloads emitted by Apple Music and Spotify.
public enum NowPlayingNotificationParser {
    public static let appleMusicNotification = "com.apple.Music.playerInfo"
    public static let spotifyNotification = "com.spotify.client.PlaybackStateChanged"

    /// Parses a `userInfo` dictionary from `com.apple.Music.playerInfo` or
    /// `com.spotify.client.PlaybackStateChanged`.
    ///
    /// Returns `nil` when the player reports `"Stopped"` or when no track title is present.
    public static func parse(
        notificationName: String,
        userInfo: [AnyHashable: Any],
        timestamp: Date = .now
    ) -> NowPlayingItem? {
        parseDetailed(
            notificationName: notificationName,
            userInfo: userInfo,
            timestamp: timestamp
        )?.item
    }

    /// Parses a notification payload and also reports whether the payload explicitly
    /// included an elapsed playback position (`com.apple.Music.playerInfo` omits it).
    public static func parseDetailed(
        notificationName: String,
        userInfo: [AnyHashable: Any],
        timestamp: Date = .now
    ) -> (item: NowPlayingItem, hasExplicitElapsedTime: Bool)? {
        let stateString = (userInfo["Player State"] as? String) ?? ""
        if stateString.caseInsensitiveCompare("Stopped") == .orderedSame {
            return nil
        }

        guard let title = (userInfo["Name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }

        let artist = (userInfo["Artist"] as? String) ?? ""
        let album = (userInfo["Album"] as? String) ?? ""
        let isPlaying = stateString.caseInsensitiveCompare("Playing") == .orderedSame

        let isSpotify = notificationName == spotifyNotification
        let duration: TimeInterval
        if isSpotify {
            // Spotify reports "Duration" in milliseconds (or seconds in some versions; > 1000 means ms).
            if let raw = numberValue(userInfo["Duration"]) {
                duration = raw > 1000 ? raw / 1000.0 : raw
            } else {
                duration = 0
            }
        } else {
            // Apple Music reports "Total Time" in milliseconds.
            if let raw = numberValue(userInfo["Total Time"]) {
                duration = raw / 1000.0
            } else {
                duration = 0
            }
        }

        let explicitElapsed: TimeInterval?
        if let pos = numberValue(userInfo["Playback Position"]) {
            explicitElapsed = pos
        } else if let pos = numberValue(userInfo["Elapsed Time"]) {
            explicitElapsed = pos
        } else {
            explicitElapsed = nil
        }

        let item = NowPlayingItem(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsedTime: explicitElapsed ?? 0,
            isPlaying: isPlaying,
            playbackRate: isPlaying ? 1.0 : 0.0,
            appBundleIdentifier: isSpotify ? "com.spotify.client" : "com.apple.Music",
            appName: isSpotify ? "Spotify" : "Music",
            timestamp: timestamp
        )
        return (item, explicitElapsed != nil)
    }

    private static func numberValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String, let d = Double(s.replacingOccurrences(of: ",", with: ".")) {
            return d
        }
        return nil
    }
}
