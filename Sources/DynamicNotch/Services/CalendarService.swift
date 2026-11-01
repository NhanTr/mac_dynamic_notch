import EventKit
import Foundation
import NotchCore
import Observation

/// Observes `EventKit` for the next upcoming calendar event within 24 hours.
@MainActor
@Observable
final class CalendarService {
    private(set) var nextEvent: CalendarEventItem?
    private(set) var isAuthorized: Bool = false

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var storeObserver: NSObjectProtocol?

    func start() {
        updateAuthorizationStatus()
        if isAuthorized {
            refreshUpcomingEvent()
        }
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshUpcomingEvent()
            }
        }
    }

    func stop() {
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
            self.storeObserver = nil
        }
    }

    func requestAccess() {
        Task { [weak self] in
            guard let self else { return }
            let granted = (try? await self.store.requestFullAccessToEvents()) ?? false
            self.isAuthorized = granted
            if granted {
                self.refreshUpcomingEvent()
            }
        }
    }

    func refreshUpcomingEvent() {
        updateAuthorizationStatus()
        guard isAuthorized else {
            nextEvent = nil
            return
        }

        let now = Date.now
        let horizon = now.addingTimeInterval(24 * 3600)
        let predicate = store.predicateForEvents(withStart: now, end: horizon, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }

        if let first = events.first {
            nextEvent = CalendarEventItem(
                id: first.eventIdentifier ?? UUID().uuidString,
                title: first.title ?? "Untitled Event",
                startDate: first.startDate,
                endDate: first.endDate,
                isAllDay: first.isAllDay
            )
        } else {
            nextEvent = nil
        }
    }

    private func updateAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = (status == .fullAccess || status == .authorized)
    }
}
