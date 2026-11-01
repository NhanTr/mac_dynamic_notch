import Foundation

/// Metadata and playback state for the currently playing (or paused) media item.
public struct NowPlayingItem: Sendable, Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var elapsedTime: TimeInterval
    public var isPlaying: Bool
    public var playbackRate: Double
    public var appBundleIdentifier: String?
    public var appName: String?
    public var artworkData: Data?
    public var timestamp: Date

    public init(
        title: String,
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        elapsedTime: TimeInterval = 0,
        isPlaying: Bool = false,
        playbackRate: Double = 1.0,
        appBundleIdentifier: String? = nil,
        appName: String? = nil,
        artworkData: Data? = nil,
        timestamp: Date = .now
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = max(0, duration)
        self.elapsedTime = max(0, elapsedTime)
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.artworkData = artworkData
        self.timestamp = timestamp
    }

    /// Extrapolated playback position at a given point in time.
    public func currentElapsedTime(at date: Date) -> TimeInterval {
        guard isPlaying else {
            return duration > 0 ? min(elapsedTime, duration) : elapsedTime
        }
        let delta = max(0, date.timeIntervalSince(timestamp)) * playbackRate
        let current = elapsedTime + delta
        return duration > 0 ? min(current, duration) : current
    }

    /// Normalized progress in `0...1` at a given point in time.
    public func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, currentElapsedTime(at: date) / duration))
    }
}

/// Power and battery snapshot from IOKit.
public struct BatteryStatus: Sendable, Equatable {
    public var percentage: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var timeRemainingMinutes: Int?

    public init(
        percentage: Int,
        isCharging: Bool,
        isPluggedIn: Bool,
        timeRemainingMinutes: Int? = nil
    ) {
        self.percentage = min(100, max(0, percentage))
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.timeRemainingMinutes = timeRemainingMinutes
    }

    public var isLowBattery: Bool {
        !isPluggedIn && percentage <= 20
    }

    public var symbolName: String {
        if isCharging { return "battery.100percent.bolt" }
        switch percentage {
        case 88...100: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

/// Kind of temporary HUD notification displayed in `.peek` state.
public enum HUDKind: Sendable, Equatable {
    case volume(Float, isMuted: Bool)
    case brightness(Float)
    case battery(BatteryStatus)
}

/// A transient heads-up display event shown in the notch `.peek` state.
public struct HUDEvent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let kind: HUDKind
    public let timestamp: Date

    public init(id: UUID = UUID(), kind: HUDKind, timestamp: Date = .now) {
        self.id = id
        self.kind = kind
        self.timestamp = timestamp
    }

    public var title: String {
        switch kind {
        case .volume(_, let isMuted):
            return isMuted ? "Muted" : "Volume"
        case .brightness:
            return "Brightness"
        case .battery(let status):
            if status.isCharging { return "Charging" }
            if status.isPluggedIn { return "Power Connected" }
            return status.isLowBattery ? "Low Battery" : "On Battery"
        }
    }

    /// Normalized `0...1` value for progress bar rendering.
    public var normalizedValue: Float {
        switch kind {
        case .volume(let value, let isMuted):
            return isMuted ? 0 : min(1, max(0, value))
        case .brightness(let value):
            return min(1, max(0, value))
        case .battery(let status):
            return Float(status.percentage) / 100.0
        }
    }

    public var valueText: String {
        switch kind {
        case .volume(let value, let isMuted):
            return isMuted ? "Off" : "\(Int((min(1, max(0, value)) * 100).rounded()))%"
        case .brightness(let value):
            return "\(Int((min(1, max(0, value)) * 100).rounded()))%"
        case .battery(let status):
            return "\(status.percentage)%"
        }
    }

    public var symbolName: String {
        switch kind {
        case .volume(let value, let isMuted):
            if isMuted || value <= 0.001 { return "speaker.slash.fill" }
            if value < 0.33 { return "speaker.wave.1.fill" }
            if value < 0.66 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness(let value):
            return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .battery(let status):
            return status.symbolName
        }
    }
}

/// A file stashed temporarily in the notch File Shelf.
public struct ShelfItem: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let url: URL
    public let displayName: String
    public let addedAt: Date

    public init(id: UUID = UUID(), url: URL, displayName: String? = nil, addedAt: Date = .now) {
        self.id = id
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
        self.addedAt = addedAt
    }
}

/// Active tab inside the expanded `.open` notch view.
public enum NotchTab: String, Sendable, Equatable, CaseIterable {
    case dashboard
    case shelf
}

/// Summary of an upcoming calendar event from `EventKit`.
public struct CalendarEventItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
    }

    /// Concise relative label (e.g. `"All day"`, `"Now"`, `"In 12m"`, `"In 2h"`).
    public func relativeBadge(at now: Date = .now) -> String {
        if isAllDay { return "All day" }
        if now >= startDate && now <= endDate { return "Now" }
        let minutes = Int((startDate.timeIntervalSince(now) / 60.0).rounded())
        if minutes <= 0 { return "Now" }
        if minutes < 60 { return "in \(minutes)m" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem > 0 ? "in \(hours)h \(rem)m" : "in \(hours)h"
    }
}
