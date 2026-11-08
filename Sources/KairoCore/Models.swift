import Foundation

// MARK: - People & preferences

/// A recurring weekly window stored in the *person's own* local time.
public struct WeeklyWindow: Codable, Hashable, Sendable {
    /// Calendar weekday numbers: 1 = Sunday … 7 = Saturday.
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int
    public var label: String

    public init(weekdays: Set<Int>, startMinute: Int, endMinute: Int, label: String) {
        self.weekdays = weekdays; self.startMinute = startMinute
        self.endMinute = endMinute; self.label = label
    }

    public func contains(weekday: Int, minuteOfDay: Int) -> Bool {
        weekdays.contains(weekday) && minuteOfDay >= startMinute && minuteOfDay < endMinute
    }
}

public struct LocalPreferences: Codable, Hashable, Sendable {
    public var wakeMinute: Int
    public var bedMinute: Int
    public var busyWindows: [WeeklyWindow]
    public var preferredCallMinutes: Int

    public init(wakeMinute: Int = 7 * 60, bedMinute: Int = 22 * 60 + 30,
                busyWindows: [WeeklyWindow] = [], preferredCallMinutes: Int = 30) {
        self.wakeMinute = wakeMinute; self.bedMinute = bedMinute
        self.busyWindows = busyWindows; self.preferredCallMinutes = preferredCallMinutes
    }

    /// Quiet hours run from bedtime to wake time and may cross midnight.
    public func isQuiet(minuteOfDay m: Int) -> Bool {
        if bedMinute == wakeMinute { return false }
        if bedMinute < wakeMinute { return m >= bedMinute && m < wakeMinute }
        return m >= bedMinute || m < wakeMinute
    }

    public func busyWindow(weekday: Int, minuteOfDay: Int) -> WeeklyWindow? {
        busyWindows.first { $0.contains(weekday: weekday, minuteOfDay: minuteOfDay) }
    }
}

public struct Person: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Short label used in widgets, e.g. "Mom".
    public var relationship: String
    public var city: String
    /// IANA identifier. Flags are decorative and never used to derive this.
    public var timeZoneID: String
    public var flag: String?
    public var prefs: LocalPreferences

    public init(id: String, name: String, relationship: String, city: String,
                timeZoneID: String, flag: String? = nil, prefs: LocalPreferences = .init()) {
        self.id = id; self.name = name; self.relationship = relationship; self.city = city
        self.timeZoneID = timeZoneID; self.flag = flag; self.prefs = prefs
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)! }
    public var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(parts).uppercased()
    }
}

// MARK: - Activity metadata (never message content)

public enum ActivityKind: String, Codable, Sendable {
    case callAnswered, callMissed, callDeclined, callback, messageReply
    case firstActivity, lastActivity
    case selfReportedConnected, selfReportedNotConnected
}

/// Communication *metadata* only. `magnitude` is seconds (call duration,
/// callback delay or reply delay depending on `kind`). No bodies, no audio.
public struct ActivityEvent: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var personID: String
    public var at: Date
    public var kind: ActivityKind
    public var magnitude: Double?
    public var synthetic: Bool

    public init(id: String = UUID().uuidString, personID: String, at: Date, kind: ActivityKind,
                magnitude: Double? = nil, synthetic: Bool = false) {
        self.id = id; self.personID = personID; self.at = at; self.kind = kind
        self.magnitude = magnitude; self.synthetic = synthetic
    }
}

public struct BusyOverride: Codable, Hashable, Sendable {
    public var personID: String
    public var start: Date
    public var end: Date
    public var setAt: Date
    public init(personID: String, start: Date, end: Date, setAt: Date) {
        self.personID = personID; self.start = start; self.end = end; self.setAt = setAt
    }
    public func isActive(at d: Date) -> Bool { d >= start && d < end }
    public func overlaps(_ i: Interval) -> Bool { start < i.end && end > i.start }
}

public struct Interval: Codable, Hashable, Sendable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
    public func overlaps(_ o: Interval) -> Bool { start < o.end && end > o.start }
}

// MARK: - Decision log (tool actions and short outcomes only; no reasoning traces)

public struct LogEntry: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case tool, constraint, outcome, user, system }
    public var id: String
    public var at: Date
    public var kind: Kind
    public var text: String
    public init(id: String = UUID().uuidString, at: Date, kind: Kind, text: String) {
        self.id = id; self.at = at; self.kind = kind; self.text = text
    }
}

public enum FeedbackChoice: String, Codable, Sendable { case yes, no, skip }

public enum SyncStatus: Codable, Hashable, Sendable {
    /// Demo mode: state exists only on this device. Nothing is synchronized.
    case localOnly
    /// Changes saved locally but not yet synchronized (offline).
    case offlinePending(Int)
    /// Confirmed synchronized with a backend (production adapter only).
    case synced(Date)
}
