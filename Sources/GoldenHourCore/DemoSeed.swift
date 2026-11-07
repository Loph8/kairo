import Foundation

/// Deterministic generator so demos and tests are repeatable.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992.0 }
    mutating func range(_ lo: Int, _ hi: Int) -> Int { lo + Int(unit() * Double(hi - lo + 1)) }
}

/// Everything here is SYNTHETIC and labeled so. It is never real imported history.
public enum DemoSeed {
    /// Sun 8 Nov 2026 7:12 PM in Durham = Mon 9:12 AM in Seoul = Mon 3:12 AM in Addis Ababa.
    public static let anchor: Date = ISO8601DateFormatter().date(from: "2026-11-09T00:12:00Z")!

    public static func people(you override: Person? = nil) -> [Person] {
        let workDays: Set<Int> = [2, 3, 4, 5, 6]
        let you = override ?? Person(id: "you", name: "You", relationship: "You", city: "Durham", timeZoneID: "America/New_York", flag: "🇺🇸",
            prefs: .init(wakeMinute: 7 * 60, bedMinute: 23 * 60,
                         busyWindows: [WeeklyWindow(weekdays: workDays, startMinute: 9 * 60, endMinute: 17 * 60, label: "Work")]))
        return [
            you,
            Person(id: "mom", name: "Mom", relationship: "Mom", city: "Seoul", timeZoneID: "Asia/Seoul", flag: "🇰🇷",
                   prefs: .init(wakeMinute: 6 * 60 + 30, bedMinute: 22 * 60)),
            Person(id: "dad", name: "Dad", relationship: "Dad", city: "Seoul", timeZoneID: "Asia/Seoul", flag: "🇰🇷",
                   prefs: .init(wakeMinute: 6 * 60, bedMinute: 21 * 60 + 30,
                                busyWindows: [WeeklyWindow(weekdays: workDays, startMinute: 13 * 60, endMinute: 15 * 60, label: "Afternoon")])),
            Person(id: "sis", name: "Sis", relationship: "Sis", city: "Addis Ababa", timeZoneID: "Africa/Addis_Ababa", flag: "🇪🇹",
                   prefs: .init(wakeMinute: 7 * 60, bedMinute: 22 * 60 + 30,
                                busyWindows: [WeeklyWindow(weekdays: workDays, startMinute: 8 * 60, endMinute: 16 * 60, label: "School")])),
        ]
    }

    struct Pattern {
        var weekend: Bool?       // nil = any day
        var kind: ActivityKind
        var from: Int, to: Int   // local minutes
        var p: Double
        var mag: ClosedRange<Int>?
    }

    static func patterns(for id: String) -> [Pattern] {
        switch id {
        case "mom": return [
            .init(weekend: false, kind: .callAnswered, from: 540, to: 645, p: 0.75, mag: 240...900),
            .init(weekend: true, kind: .callAnswered, from: 600, to: 690, p: 0.6, mag: 240...900),
            .init(weekend: false, kind: .messageReply, from: 1200, to: 1260, p: 0.45, mag: 120...900),
            .init(weekend: false, kind: .callMissed, from: 840, to: 930, p: 0.35, mag: nil),
            .init(weekend: nil, kind: .firstActivity, from: 400, to: 450, p: 0.6, mag: nil),
            .init(weekend: nil, kind: .lastActivity, from: 1260, to: 1300, p: 0.6, mag: nil)]
        case "dad": return [
            .init(weekend: false, kind: .callAnswered, from: 540, to: 600, p: 0.35, mag: 60...300),
            .init(weekend: false, kind: .callDeclined, from: 540, to: 600, p: 0.7, mag: nil),
            .init(weekend: true, kind: .callAnswered, from: 600, to: 720, p: 0.4, mag: 120...600),
            .init(weekend: false, kind: .messageReply, from: 1170, to: 1260, p: 0.4, mag: 1800...7200)]
        case "sis": return [
            .init(weekend: false, kind: .callAnswered, from: 1110, to: 1230, p: 0.55, mag: 300...1500),
            .init(weekend: true, kind: .callAnswered, from: 900, to: 1200, p: 0.6, mag: 300...1500),
            .init(weekend: false, kind: .callMissed, from: 600, to: 900, p: 0.3, mag: nil),
            .init(weekend: nil, kind: .messageReply, from: 1140, to: 1290, p: 0.5, mag: 60...1200)]
        default: return [
            .init(weekend: nil, kind: .callAnswered, from: 1140, to: 1260, p: 0.7, mag: 300...1200),
            .init(weekend: false, kind: .messageReply, from: 450, to: 510, p: 0.5, mag: 60...600),
            .init(weekend: nil, kind: .callback, from: 1170, to: 1290, p: 0.3, mag: 300...1500)]
        }
    }

    static func stableSeed(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h
    }

    /// ~Two weeks of synthetic metadata ending at `anchor`.
    public static func syntheticEvents(for people: [Person], until end: Date = anchor, days: Int = 14) -> [ActivityEvent] {
        var out: [ActivityEvent] = []
        for p in people {
            var rng = SplitMix64(seed: stableSeed(p.id))
            let tz = p.timeZone, cal = TimeKit.calendar(tz)
            for back in 0...days {
                guard let day = cal.date(byAdding: .day, value: -back, to: end) else { continue }
                let (y, m, d) = TimeKit.ymd(day, tz)
                let weekend = TimeKit.isWeekend(cal.component(.weekday, from: day))
                for (i, pat) in patterns(for: p.id).enumerated() {
                    guard rng.unit() < pat.p else { continue }
                    let minute = rng.range(pat.from, pat.to)
                    let mag = pat.mag.map { Double(rng.range($0.lowerBound, $0.upperBound)) }
                    if let w = pat.weekend, w != weekend { continue }
                    guard let at = TimeKit.resolve(year: y, month: m, day: d, minuteOfDay: minute, in: tz), at < end else { continue }
                    out.append(ActivityEvent(id: "syn-\(p.id)-\(back)-\(i)", personID: p.id, at: at,
                                             kind: pat.kind, magnitude: mag, synthetic: true))
                }
            }
        }
        return out
    }

    public static func makeState(realNow: Date, you override: Person? = nil) -> AppState {
        var s = AppState()
        s.people = people(you: override)
        s.viewerID = s.people[0].id
        s.focusPersonID = "mom"
        s.events = syntheticEvents(for: s.people)
        s.isDemo = true
        s.clockOffset = anchor.timeIntervalSince(realNow)
        s.settings.onboardingComplete = true
        s.log = [LogEntry(at: anchor, kind: .system,
                          text: "Loaded \(s.events.count) SYNTHETIC metadata events (14 days). Demo data, not imported history.")]
        return s
    }
}
