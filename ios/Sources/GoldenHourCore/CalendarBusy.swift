import Foundation
import CryptoKit

/// One calendar event as the app reads it from EventKit. Titles, notes, locations and attendee
/// names are never copied here, so they can never reach the server.
public struct CalendarEventInfo: Sendable, Equatable {
    public var identifier: String        // EKEvent.calendarItemIdentifier (stays on the phone)
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var showsAsFree: Bool         // EKEvent.availability == .free
    public var declined: Bool            // the user declined the invitation
    public var hasOtherAttendees: Bool   // a meeting with other people can't be moved by us

    public init(identifier: String, start: Date, end: Date, isAllDay: Bool = false,
                showsAsFree: Bool = false, declined: Bool = false, hasOtherAttendees: Bool = false) {
        self.identifier = identifier; self.start = start; self.end = end; self.isAllDay = isAllDay
        self.showsAsFree = showsAsFree; self.declined = declined; self.hasOtherAttendees = hasOtherAttendees
    }
}

/// What the server gets: an opaque id plus the busy interval. Nothing else.
public struct BusyBlockPayload: Sendable, Equatable {
    public var id: String
    public var start: Date
    public var end: Date
    public var movable: Bool
}

public enum CalendarBusy {
    public static let maxBlocks = 600            // server limit (api.ts MAX_BLOCKS)
    public static let maxDuration: TimeInterval = 24 * 3600   // server limit (MAX_BLOCK_HOURS)
    public static let lookahead: TimeInterval = 4 * 24 * 3600  // forecast + the AI's 72 h search
    /// Past weeks the AI learns from: a weekly class becomes "usually busy Tuesdays at 2".
    public static let lookback: TimeInterval = 28 * 24 * 3600

    /// Opaque, stable id for one occurrence. The server can't turn it back into the event.
    public static func blockID(identifier: String, start: Date) -> String {
        let key = "\(identifier)|\(Int(start.timeIntervalSince1970))"
        let hex = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return "cal-" + hex.prefix(24)
    }

    /// The window the app reads and uploads: the last 4 weeks (to learn from) through the next 4 days (to avoid).
    public static func window(now: Date) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-lookback), end: now.addingTimeInterval(lookahead))
    }

    /// Turns events into upload-ready busy blocks: drops all-day, "free" and declined events,
    /// clips to the window, caps each at 24 h, removes duplicates and keeps the latest 600.
    public static func blocks(from events: [CalendarEventInfo], in window: DateInterval) -> [BusyBlockPayload] {
        var seen = Set<String>()
        let blocks = events.compactMap { e -> BusyBlockPayload? in
            guard !e.isAllDay, !e.showsAsFree, !e.declined else { return nil }
            let start = max(e.start, window.start)
            let end = min(e.end, window.end, start.addingTimeInterval(maxDuration))
            guard end > start else { return nil }
            let id = blockID(identifier: e.identifier, start: e.start)
            guard seen.insert(id).inserted else { return nil }
            return BusyBlockPayload(id: id, start: start, end: end, movable: !e.hasOtherAttendees)
        }
        return Array(blocks.sorted { ($0.start, $0.id) < ($1.start, $1.id) }.suffix(maxBlocks))
    }
}
