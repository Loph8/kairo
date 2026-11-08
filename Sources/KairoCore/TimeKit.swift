import Foundation

/// All time zone math lives here. Instants are `Date` (UTC); local views are derived
/// from IANA identifiers via Foundation, so DST is handled by the OS tz database.
public enum TimeKit {
    public static let slotMinutes = 30
    public static let slotsPerDay = 48
    public static let slotsPerWeek = 336

    public static func calendar(_ tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    public struct LocalTime: Hashable, Sendable {
        public let weekday: Int      // 1 = Sunday
        public let minuteOfDay: Int
    }

    public static func local(_ d: Date, _ tz: TimeZone) -> LocalTime {
        let c = calendar(tz).dateComponents([.weekday, .hour, .minute], from: d)
        return LocalTime(weekday: c.weekday ?? 1, minuteOfDay: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// Index 0..<336 into a local week of 30-minute slots (Sunday 00:00 = 0).
    public static func slotIndex(_ d: Date, _ tz: TimeZone) -> Int {
        let l = local(d, tz)
        return (l.weekday - 1) * slotsPerDay + l.minuteOfDay / slotMinutes
    }

    public static func isWeekend(_ weekday: Int) -> Bool { weekday == 1 || weekday == 7 }

    public static func formatTime(_ d: Date, _ tz: TimeZone, use24Hour: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return f.string(from: d)
    }

    /// Whole local-calendar-day difference between `instant` and `reference` in `tz`.
    public static func dayOffset(of instant: Date, from reference: Date, in tz: TimeZone) -> Int {
        let cal = calendar(tz)
        return cal.dateComponents([.day], from: cal.startOfDay(for: reference),
                                  to: cal.startOfDay(for: instant)).day ?? 0
    }

    /// "Today", "Tomorrow", "Yesterday" or a weekday, judged in `tz` against `reference`.
    public static func dayLabel(_ instant: Date, reference: Date, in tz: TimeZone) -> String {
        switch dayOffset(of: instant, from: reference, in: tz) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = tz; f.dateFormat = "EEE"
            return f.string(from: instant)
        }
    }

    /// "Today, 8:00 PM" — day judged against `reference` in the *viewing* zone.
    public static func describe(_ instant: Date, in tz: TimeZone, reference: Date, use24Hour: Bool) -> String {
        "\(dayLabel(instant, reference: reference, in: tz)), \(formatTime(instant, tz, use24Hour: use24Hour))"
    }

    /// Resolves a local wall-clock time to an instant, DST-safely.
    /// Nonexistent times (spring forward) move to the next valid time; repeated times
    /// (fall back) resolve to the first occurrence.
    public static func resolve(year: Int, month: Int, day: Int, minuteOfDay: Int, in tz: TimeZone) -> Date? {
        let cal = calendar(tz)
        guard let dayStart = cal.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let match = DateComponents(hour: minuteOfDay / 60, minute: minuteOfDay % 60)
        return cal.nextDate(after: dayStart.addingTimeInterval(-1), matching: match,
                            matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }

    public static func ymd(_ d: Date, _ tz: TimeZone) -> (Int, Int, Int) {
        let c = calendar(tz).dateComponents([.year, .month, .day], from: d)
        return (c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
}
