import EventKit
import Foundation
import GoldenHourCore

/// Reads the phone's calendars (iOS 17 full access) and turns them into busy blocks for the
/// family server. Only start, end and an opaque id leave the phone: never titles, places or people.
@MainActor @Observable
final class CalendarSync {
    enum Access: Equatable { case notAsked, granted, denied, restricted }

    enum MoveError: LocalizedError {
        case notFound, notEditable
        var errorDescription: String? {
            switch self {
            case .notFound: "That event is no longer in your calendar."
            case .notEditable: "That calendar can't be edited from Kairos."
            }
        }
    }

    private let store = EKEventStore()
    private(set) var access: Access = CalendarSync.currentAccess()
    private(set) var lastSynced: Date?
    private(set) var eventCount = 0

    /// Calendar accounts on this iPhone (iCloud, Google, Outlook…), by name. Only the account names, never events.
    var accountNames: [String] {
        guard access == .granted else { return [] }
        let names = store.calendars(for: .event).compactMap { $0.source?.title }
        return Array(Set(names)).sorted()
    }

    /// A Google account shows up as a CalDAV source on gmail.com / googlemail.com, or titled "Google".
    var hasGoogle: Bool {
        guard access == .granted else { return false }
        return store.calendars(for: .event).contains { c in
            guard let src = c.source else { return false }
            let t = src.title.lowercased()
            return t.contains("gmail") || t.contains("google") || t.contains("googlemail")
        }
    }
    /// Opaque block id → event, so a server "move" suggestion can find the real event again.
    private var eventsByBlockID: [String: EKEvent] = [:]
    private var observer: NSObjectProtocol?

    static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        case .restricted: .restricted
        default: .denied   // .denied and .writeOnly (we need to read)
        }
    }

    /// Shows the system prompt the first time. Returns whether we can read events.
    func requestAccess() async -> Bool {
        do { _ = try await store.requestFullAccessToEvents() } catch { /* status below tells the truth */ }
        access = Self.currentAccess()
        return access == .granted
    }

    /// Calls `onChange` whenever any calendar on the phone changes (edits, new invites, iCloud sync).
    func observeChanges(_ onChange: @escaping @MainActor () -> Void) {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { onChange() }
        }
    }

    /// Busy blocks for the next 48 hours. Empty when access isn't granted.
    func currentBlocks(now: Date = Date()) -> [BusyBlockPayload] {
        access = Self.currentAccess()
        guard access == .granted else { eventsByBlockID = [:]; eventCount = 0; return [] }
        let window = CalendarBusy.window(now: now)
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: nil)
        let events = store.events(matching: predicate)
        var byID: [String: EKEvent] = [:]
        let infos = events.map { e -> CalendarEventInfo in
            let info = Self.info(e)
            byID[CalendarBusy.blockID(identifier: info.identifier, start: info.start)] = e
            return info
        }
        let blocks = CalendarBusy.blocks(from: infos, in: window)
        eventsByBlockID = byID
        eventCount = blocks.count
        return blocks
    }

    /// Uploads the current blocks. Throws so the caller can show the error.
    func push(with client: BackendClient, now: Date = Date()) async throws -> ServerResult? {
        guard Self.currentAccess() == .granted else { return nil }
        let result = try await client.pushBusy(currentBlocks(now: now))
        lastSynced = Date()
        return result
    }

    /// Moves one of the user's own events to the suggested start, keeping its length.
    /// Only ever called after the user taps "Move it": Kairos never rearranges on its own.
    func move(blockID: String, to newStart: Date) throws {
        if eventsByBlockID[blockID] == nil { _ = currentBlocks() }
        guard let event = eventsByBlockID[blockID] else { throw MoveError.notFound }
        guard event.calendar?.allowsContentModifications == true else { throw MoveError.notEditable }
        let length = event.endDate.timeIntervalSince(event.startDate)
        event.startDate = newStart
        event.endDate = newStart.addingTimeInterval(length)
        try store.save(event, span: .thisEvent, commit: true)
    }

    private static func info(_ e: EKEvent) -> CalendarEventInfo {
        let attendees = e.attendees ?? []
        let me = attendees.first(where: \.isCurrentUser)
        let others = attendees.contains { !$0.isCurrentUser }
        let editable = e.calendar?.allowsContentModifications ?? false
        return CalendarEventInfo(
            identifier: e.calendarItemIdentifier,
            start: e.startDate, end: e.endDate,
            isAllDay: e.isAllDay,
            showsAsFree: e.availability == .free,
            declined: me?.participantStatus == .declined,
            // Not ours to move: meetings with other people, or calendars we can't write to.
            hasOtherAttendees: others || !editable)
    }
}
