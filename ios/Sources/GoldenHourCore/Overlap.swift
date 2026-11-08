import Foundation

/// The large widget's 24-hour ring: for each half hour of the viewer's day, how many
/// family members (viewer included) are likely free. Pure, so it is unit-tested.
public struct OverlapDial: Sendable, Equatable {
    public static let cellsPerDay = 48
    public static let cellSeconds: TimeInterval = 1800

    /// Index = viewer-local half hour (0 = 00:00–00:30, 47 = 23:30–24:00). Value = people free.
    public let counts: [Int]
    /// Everyone in the ring, viewer included when the snapshot has their forecast.
    public let total: Int
    /// The next stretch (within the forecast) when everyone is free.
    public let allFree: DateInterval?

    /// "Free" means `.likelyFree`. Maybe-free does not count, so a glowing slot is a safe bet.
    public static func isFree(_ level: AvailabilityLevel) -> Bool { level == .likelyFree }

    public init(snapshot s: WidgetSnapshot, now: Date) {
        let forecasts = s.people.map(\.forecast) + (s.viewerForecast.map { [$0] } ?? [])
        total = forecasts.count

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = s.viewerTimeZone

        var dial = Array(repeating: 0, count: Self.cellsPerDay)
        var byStep: [Int] = []
        for step in 0..<Self.cellsPerDay {
            let start = s.forecastStart.addingTimeInterval(Double(step) * Self.cellSeconds)
            let free = forecasts.filter { step < $0.count && Self.isFree($0[step]) }.count
            byStep.append(free)
            dial[Self.localCell(start, cal)] = free
        }
        counts = dial
        allFree = Self.firstAllFree(byStep, total: total, from: s.forecastStart, now: now)
    }

    /// Viewer-local half-hour index for `date`.
    public static func localCell(_ date: Date, _ cal: Calendar) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 2 + ((c.minute ?? 0) >= 30 ? 1 : 0)
    }

    /// First run of steps where all `total` people are free that has not already ended.
    static func firstAllFree(_ byStep: [Int], total: Int, from start: Date, now: Date) -> DateInterval? {
        guard total > 0 else { return nil }
        var runStart: Int?
        for step in 0...byStep.count {
            let full = step < byStep.count && byStep[step] == total
            if full, runStart == nil { runStart = step }
            guard !full, let first = runStart else { continue }
            let interval = DateInterval(start: start.addingTimeInterval(Double(first) * cellSeconds),
                                        end: start.addingTimeInterval(Double(step) * cellSeconds))
            if interval.end > now { return interval }
            runStart = nil
        }
        return nil
    }
}
