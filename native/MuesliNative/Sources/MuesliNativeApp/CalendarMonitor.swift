import AppKit
import EventKit
import Foundation
import MuesliCore

struct UpcomingMeetingEvent {
    let id: String
    let title: String
    let startDate: Date
    var meetingURL: URL? = nil
}

final class CalendarMonitor {
    private let store = EKEventStore()
    private var changeObserver: NSObjectProtocol?

    /// Called when EventKit detects a calendar change (event added, moved, deleted).
    /// Delivered via NotificationCenter — immune to App Nap timer suspension.
    var onCalendarChanged: (() -> Void)?

    func start() {
        store.requestFullAccessToEvents { [weak self] granted, error in
            if !granted {
                fputs("[calendar] calendar access denied: \(error?.localizedDescription ?? "none")\n", stderr)
                return
            }
            DispatchQueue.main.async {
                self?.registerForChanges()
                self?.onCalendarChanged?()
            }
        }
    }

    func stop() {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
            self.changeObserver = nil
        }
    }

    private func registerForChanges() {
        // EKEventStoreChangedNotification fires whenever any calendar event
        // is added, modified, or deleted — including synced changes from
        // Google Calendar, iCloud, Exchange, etc. This is push-based and
        // works regardless of App Nap or LSUIElement status.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.onCalendarChanged?()
        }
    }

    func localCalendars() -> [LocalCalendarInfo] {
        store.calendars(for: .event)
            .map {
                LocalCalendarInfo(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    sourceTitle: $0.source.title,
                    colorHex: Self.hexString(from: $0.cgColor)
                )
            }
            .sorted { lhs, rhs in
                let lhsSource = lhs.sourceTitle ?? ""
                let rhsSource = rhs.sourceTitle ?? ""
                if lhsSource != rhsSource {
                    return lhsSource.localizedCaseInsensitiveCompare(rhsSource) == .orderedAscending
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    /// Returns the current calendar event if one is happening right now.
    func currentEvent(excluding hiddenCalendarIDs: Set<String> = []) -> UpcomingMeetingEvent? {
        let calendars = visibleCalendars(excluding: hiddenCalendarIDs, using: store)
        guard !calendars.isEmpty else { return nil }
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(60),
            calendars: calendars
        )
        let events = store.events(matching: predicate)
        for event in events {
            guard !event.isAllDay else { continue }
            guard let startDate = event.startDate, let endDate = event.endDate else { continue }
            if startDate <= now && endDate > now {
                return UpcomingMeetingEvent(
                    id: event.eventIdentifier ?? "",
                    title: event.title ?? "Meeting",
                    startDate: startDate,
                    meetingURL: Self.extractMeetingURL(from: event)
                )
            }
        }
        return nil
    }

    /// Returns the current or recently started event (within 15 minutes)
    /// for meeting detection. Prefers currently active events over nearby ones.
    func currentOrNearbyEvent(excluding hiddenCalendarIDs: Set<String> = []) -> CalendarEventContext? {
        let calendars = visibleCalendars(excluding: hiddenCalendarIDs, using: store)
        guard !calendars.isEmpty else { return nil }
        let now = Date()
        let searchStart = now.addingTimeInterval(-15 * 60)
        let searchEnd = now.addingTimeInterval(5 * 60)
        let predicate = store.predicateForEvents(withStart: searchStart, end: searchEnd, calendars: calendars)
        let events = store.events(matching: predicate)

        var nearby: CalendarEventContext?
        for event in events {
            guard !event.isAllDay else { continue }
            guard let startDate = event.startDate, let endDate = event.endDate else { continue }
            let ctx = CalendarEventContext(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Meeting"
            )
            // Currently active — return immediately
            if startDate <= now && endDate > now {
                return ctx
            }
            // Recently started (within 15 min) or about to start (within 5 min)
            if nearby == nil {
                nearby = ctx
            }
        }
        return nearby
    }

    /// Returns upcoming timed events from the local macOS calendar (EventKit) for the next N days.
    /// All-day events are excluded — they're not useful for meeting recording.
    func upcomingEvents(daysAhead: Int = 7, excluding hiddenCalendarIDs: Set<String> = []) -> [UnifiedCalendarEvent] {
        // Create a fresh EKEventStore each time to avoid stale cache.
        // EKEventStore instances cache calendar data and don't automatically
        // reflect external changes (e.g., events moved in Google Calendar).
        // Uses a local instance to avoid racing with currentEvent()/currentOrNearbyEvent().
        let freshStore = EKEventStore()
        let now = Date()
        guard let future = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) else { return [] }
        let calendars = visibleCalendars(excluding: hiddenCalendarIDs, using: freshStore)
        guard !calendars.isEmpty else { return [] }
        let predicate = freshStore.predicateForEvents(withStart: now, end: future, calendars: calendars)
        let events = freshStore.events(matching: predicate)
        return events.compactMap { event in
            guard let startDate = event.startDate, let endDate = event.endDate else { return nil }
            guard !event.isAllDay else { return nil }
            return UnifiedCalendarEvent(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Meeting",
                startDate: startDate,
                endDate: endDate,
                isAllDay: false,
                source: .eventKit,
                meetingURL: Self.extractMeetingURL(from: event),
                calendarID: event.calendar.calendarIdentifier,
                calendarName: event.calendar.title,
                calendarSourceTitle: event.calendar.source.title,
                calendarColorHex: Self.hexString(from: event.calendar.cgColor)
            )
        }.sorted { $0.startDate < $1.startDate }
    }

    func events(
        from startDate: Date,
        to endDate: Date,
        excluding hiddenCalendarIDs: Set<String> = []
    ) -> [UnifiedCalendarEvent] {
        let freshStore = EKEventStore()
        let calendars = visibleCalendars(excluding: hiddenCalendarIDs, using: freshStore)
        guard !calendars.isEmpty else { return [] }
        let predicate = freshStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = freshStore.events(matching: predicate)
        return events.compactMap { event in
            guard let eventStartDate = event.startDate, let eventEndDate = event.endDate else { return nil }
            guard !event.isAllDay else { return nil }
            return UnifiedCalendarEvent(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Meeting",
                startDate: eventStartDate,
                endDate: eventEndDate,
                isAllDay: false,
                source: .eventKit,
                meetingURL: Self.extractMeetingURL(from: event),
                calendarID: event.calendar.calendarIdentifier,
                calendarName: event.calendar.title,
                calendarSourceTitle: event.calendar.source.title,
                calendarColorHex: Self.hexString(from: event.calendar.cgColor)
            )
        }.sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Meeting URL Extraction

    /// Extract a meeting join URL from an EventKit event.
    /// Checks the event URL, location, and notes for known meeting link patterns.
    private static let meetingURLPattern: NSRegularExpression? = {
        let patterns = [
            "https://[a-z0-9.-]*zoom\\.us/j/[^\\s\"<>]+",
            "https://meet\\.google\\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}[^\\s\"<>]*",
            "https://teams\\.microsoft\\.com/l/meetup-join/[^\\s\"<>]+",
            "https://[a-z0-9.-]*webex\\.com/[^\\s\"<>]+/j\\.php[^\\s\"<>]*",
            "https://[a-z0-9.-]*chime\\.aws/[^\\s\"<>]+",
            "https://facetime\\.apple\\.com/join[^\\s\"<>]*",
        ]
        return try? NSRegularExpression(pattern: "(\(patterns.joined(separator: "|")))", options: .caseInsensitive)
    }()

    static func extractMeetingURL(from event: EKEvent) -> URL? {
        // 1. Explicit event URL (set by calendar provider)
        if let url = event.url, isMeetingURL(url) {
            return url
        }

        // 2. Search location field
        if let location = event.location, let url = findMeetingURL(in: location) {
            return url
        }

        // 3. Search notes/description
        if let notes = event.notes, let url = findMeetingURL(in: notes) {
            return url
        }

        return nil
    }

    private static func isMeetingURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com", "chime.aws", "facetime.apple.com"]
        return meetingHosts.contains(where: { host.hasSuffix($0) })
    }

    static func findMeetingURL(in text: String) -> URL? {
        guard let regex = meetingURLPattern else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        guard let matchRange = Range(match.range, in: text) else { return nil }
        return URL(string: String(text[matchRange]))
    }

    private func visibleCalendars(excluding hiddenCalendarIDs: Set<String>, using store: EKEventStore) -> [EKCalendar] {
        store.calendars(for: .event).filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
    }

    private static func hexString(from cgColor: CGColor?) -> String? {
        guard let cgColor,
              let color = NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB) else {
            return nil
        }
        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return String(format: "%02X%02X%02X", red, green, blue)
    }

}
