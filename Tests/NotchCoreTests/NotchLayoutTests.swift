import CoreGraphics
import Foundation
import Testing
@testable import NotchCore

/// MacBook Pro 14" at the default "looks like 1512 x 982" scaling.
private let mbp14 = ScreenMetrics(
    frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
    visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
    safeAreaTop: 32,
    auxiliaryTopLeftWidth: 656,
    auxiliaryTopRightWidth: 656
)

/// External 1080p display placed to the right of the built-in one.
private let external1080p = ScreenMetrics(
    frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
    visibleFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1055)
)

@Suite("NotchGeometry")
struct NotchGeometryTests {
    @Test func detectsPhysicalNotch() {
        let geometry = NotchGeometry(metrics: mbp14)
        #expect(geometry.hasPhysicalNotch)
        #expect(geometry.size == CGSize(width: 200, height: 32))
    }

    @Test func fallsBackToVirtualNotchUsingMenuBarHeight() {
        let geometry = NotchGeometry(metrics: external1080p)
        #expect(!geometry.hasPhysicalNotch)
        #expect(geometry.size == CGSize(width: NotchGeometry.virtualNotchWidth, height: 25))
    }

    @Test func usesFallbackHeightWhenMenuBarIsHidden() {
        var metrics = external1080p
        metrics.visibleFrame = metrics.frame
        let geometry = NotchGeometry(metrics: metrics)
        #expect(geometry.size.height == NotchGeometry.fallbackHeight)
    }

    @Test func ignoresSafeAreaWithoutAuxiliaryAreas() {
        var metrics = mbp14
        metrics.auxiliaryTopLeftWidth = nil
        #expect(!NotchGeometry(metrics: metrics).hasPhysicalNotch)
    }
}

@Suite("NotchLayout")
struct NotchLayoutTests {
    let layout = NotchLayout(metrics: mbp14)

    @Test func closedShapeCoversNotchPlusEars() {
        let style = NotchStyle.default
        #expect(layout.closedShapeSize.width == 200 + style.closedTopRadius * 2)
        #expect(layout.closedShapeSize.height == 32)
    }

    @Test func compactAndPeekShapesGrowMonotonically() {
        #expect(layout.compactShapeSize.width > layout.closedShapeSize.width)
        #expect(layout.compactShapeSize.height == layout.closedShapeSize.height)
        #expect(layout.peekShapeSize.height > layout.compactShapeSize.height)
        #expect(layout.openShapeSize.width >= layout.peekShapeSize.width)
        #expect(layout.openShapeSize.height > layout.peekShapeSize.height)
    }

    @Test func panelIsTopAlignedAndCentered() {
        let panel = layout.panelFrame
        #expect(panel.maxY == mbp14.frame.maxY)
        #expect(abs(panel.midX - mbp14.frame.midX) <= 0.5)
        #expect(panel.contains(layout.openRect))
    }

    @Test func closedRectSitsInsideOpenRect() {
        #expect(layout.openRect.contains(layout.closedRect))
        #expect(layout.openRect.contains(layout.compactRect))
        #expect(layout.openRect.contains(layout.peekRect))
        #expect(layout.closedRect.maxY == mbp14.frame.maxY)
    }

    @Test func hoverRectAcceptsPointerPinnedToTopEdge() {
        let topEdge = CGPoint(x: mbp14.frame.midX, y: mbp14.frame.maxY)
        #expect(layout.hoverRect(for: .closed).contains(topEdge))
        #expect(layout.hoverRect(for: .compact).contains(topEdge))
    }

    @Test func hoverRectRejectsFarAwayPoints() {
        let below = CGPoint(x: mbp14.frame.midX, y: mbp14.frame.maxY - 80)
        let aside = CGPoint(x: 100, y: mbp14.frame.maxY - 5)
        #expect(!layout.hoverRect(for: .closed).contains(below))
        #expect(!layout.hoverRect(for: .closed).contains(aside))
        #expect(layout.hoverRect(for: .open).contains(below))
    }

    @Test func layoutFollowsSecondaryDisplayOrigin() {
        let layout = NotchLayout(metrics: external1080p)
        #expect(abs(layout.panelFrame.midX - external1080p.frame.midX) <= 0.5)
        #expect(layout.panelFrame.maxY == external1080p.frame.maxY)
    }
}

@Suite("ActivityCoordinator & Models")
struct ActivityCoordinatorTests {
    @Test func priorityResolvesOpenOverPeekAndCompact() {
        let track = NowPlayingItem(title: "Track", artist: "Artist", duration: 180, isPlaying: true)
        let hud = HUDEvent(kind: .volume(0.5, isMuted: false))

        var coordinator = ActivityCoordinator()
        #expect(coordinator.resolvedState == .closed)

        coordinator.nowPlaying = track
        #expect(coordinator.resolvedState == .compact)

        coordinator.activeHUD = hud
        #expect(coordinator.resolvedState == .peek)

        coordinator.isHovering = true
        #expect(coordinator.resolvedState == .open)
    }

    @Test func fileDragOpensShelfAutomatically() {
        var coordinator = ActivityCoordinator(selectedTab: .dashboard)
        #expect(coordinator.effectiveTab == .dashboard)

        coordinator.isDraggingOverNotch = true
        #expect(coordinator.resolvedState == .open)
        #expect(coordinator.effectiveTab == .shelf)
    }

    @Test func nowPlayingExtrapolatesElapsedTimeWhenPlaying() {
        let start = Date(timeIntervalSince1970: 1000)
        let item = NowPlayingItem(
            title: "Song",
            duration: 200,
            elapsedTime: 50,
            isPlaying: true,
            timestamp: start
        )
        let tenSecondsLater = start.addingTimeInterval(10)
        #expect(item.currentElapsedTime(at: tenSecondsLater) == 60)
        #expect(abs(item.progress(at: tenSecondsLater) - 0.30) < 0.0001)
    }

    @Test func notificationParserHandlesSpotifyAndAppleMusic() {
        let spotifyPayload: [AnyHashable: Any] = [
            "Player State": "Playing",
            "Name": "One More Time",
            "Artist": "Daft Punk",
            "Album": "Discovery",
            "Duration": 320_000,
            "Playback Position": 45.0,
        ]
        let parsed = NowPlayingNotificationParser.parseDetailed(
            notificationName: NowPlayingNotificationParser.spotifyNotification,
            userInfo: spotifyPayload
        )
        #expect(parsed?.item.title == "One More Time")
        #expect(parsed?.item.artist == "Daft Punk")
        #expect(parsed?.item.duration == 320.0)
        #expect(parsed?.item.elapsedTime == 45.0)
        #expect(parsed?.hasExplicitElapsedTime == true)
        #expect(parsed?.item.isPlaying == true)
        #expect(parsed?.item.appBundleIdentifier == "com.spotify.client")

        // Apple Music notifications omit elapsed time; parser flags `hasExplicitElapsedTime == false`.
        let appleMusicPayload: [AnyHashable: Any] = [
            "Player State": "Playing",
            "Name": "Track A",
            "Artist": "Artist A",
            "Total Time": 210_000,
        ]
        let parsedMusic = NowPlayingNotificationParser.parseDetailed(
            notificationName: NowPlayingNotificationParser.appleMusicNotification,
            userInfo: appleMusicPayload
        )
        #expect(parsedMusic?.item.duration == 210.0)
        #expect(parsedMusic?.hasExplicitElapsedTime == false)

        let stoppedPayload: [AnyHashable: Any] = ["Player State": "Stopped", "Name": "Song"]
        #expect(
            NowPlayingNotificationParser.parse(
                notificationName: NowPlayingNotificationParser.appleMusicNotification,
                userInfo: stoppedPayload
            ) == nil
        )
    }

    @Test func hudEventAndBatteryFormatting() {
        let muted = HUDEvent(kind: .volume(0.8, isMuted: true))
        #expect(muted.normalizedValue == 0)
        #expect(muted.valueText == "Off")
        #expect(muted.symbolName == "speaker.slash.fill")

        let battery = BatteryStatus(percentage: 15, isCharging: false, isPluggedIn: false)
        #expect(battery.isLowBattery)
        let batteryHUD = HUDEvent(kind: .battery(battery))
        #expect(batteryHUD.title == "Low Battery")
        #expect(batteryHUD.valueText == "15%")
    }

    @Test func calendarEventRelativeBadgeFormatsCorrectly() {
        let base = Date(timeIntervalSince1970: 10_000)
        let upcoming25m = CalendarEventItem(
            title: "Design Sync",
            startDate: base.addingTimeInterval(25 * 60),
            endDate: base.addingTimeInterval(55 * 60)
        )
        #expect(upcoming25m.relativeBadge(at: base) == "in 25m")

        let ongoing = CalendarEventItem(
            title: "Standup",
            startDate: base.addingTimeInterval(-300),
            endDate: base.addingTimeInterval(600)
        )
        #expect(ongoing.relativeBadge(at: base) == "Now")

        let allDay = CalendarEventItem(
            title: "Holiday",
            startDate: base,
            endDate: base.addingTimeInterval(86_400),
            isAllDay: true
        )
        #expect(allDay.relativeBadge(at: base) == "All day")
    }
}
