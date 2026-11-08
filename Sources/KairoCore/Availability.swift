import Foundation

public enum AvailabilityLevel: String, Codable, Sendable, CaseIterable {
    case likelyFree, maybeFree, unlikely, busy, quietHours, learning

    public var label: String {
        switch self {
        case .likelyFree: return "Likely free"
        case .maybeFree: return "Maybe free"
        case .unlikely: return "Less likely free"
        case .busy: return "Busy"
        case .quietHours: return "Quiet hours"
        case .learning: return "Learning"
        }
    }
    /// Hard blocks are never scheduled over.
    public var isHardBlock: Bool { self == .busy || self == .quietHours }
}

public enum AvailabilitySource: String, Codable, Sendable { case explicitOverride, quietHours, preference, learned, insufficientEvidence }

public struct AvailabilityEstimate: Codable, Hashable, Sendable {
    public var level: AvailabilityLevel
    /// Heuristic 0…1 ranking score. NOT a calibrated probability.
    public var score: Double
    /// 0…1 evidence-quantity measure. NOT a statistical confidence interval.
    public var confidence: Double
    public var source: AvailabilitySource
    public var until: Date?
}

public struct ScorerConfig: Codable, Sendable {
    /// Weight of the onboarding prior, in "observation equivalents".
    public var priorStrength = 2.0
    public var halfLifeDays = 10.0
    /// Fraction of an observation's weight shared with adjacent 30-minute slots.
    public var neighborWeight = 0.5
    /// Fraction shared with the same slot on other days of the same type (weekday/weekend).
    public var dayTypeWeight = 0.35
    public var fullConfidenceEvidence = 4.0
    public var minConfidence = 0.25
    public var likelyThreshold = 0.62
    public var maybeThreshold = 0.38
    public init() {}
}

public struct SlotCell: Codable, Hashable, Sendable {
    public var prior: Double
    public var score: Double
    public var confidence: Double
    public var evidence: Double
}

public struct SlotModel: Codable, Sendable {
    public var personID: String
    public var cells: [SlotCell]   // 336 local-week slots
    public var builtAt: Date
}

/// On-device availability model.
///
///   score(slot) = (k·prior + E⁺) / (k + E⁺ + E⁻)
///
/// where E⁺/E⁻ are recency-weighted sums of positive/negative evidence (half-life
/// `halfLifeDays`), spread to neighboring slots and to the same slot on other days of the
/// same type. `confidence = min(1, (E⁺+E⁻)/fullConfidenceEvidence)`.
/// Limitations: weights are hand-set heuristics, silence is ambiguous, and scores are
/// rankings, not probabilities. Below `minConfidence` the result is "Learning".
public struct AvailabilityScorer: Sendable {
    public var config: ScorerConfig
    public init(config: ScorerConfig = .init()) { self.config = config }

    /// Signed evidence weight for one event. Missed calls are deliberately weak.
    public func signal(_ e: ActivityEvent) -> Double {
        let m = e.magnitude ?? 0
        switch e.kind {
        case .callAnswered: return m >= 300 ? 1.2 : 1.0
        case .callback: return m <= 1800 ? 0.8 : 0.4
        case .messageReply: return m < 600 ? 0.7 : (m < 3600 ? 0.4 : 0.15)
        case .firstActivity, .lastActivity: return 0.2
        case .callMissed: return -0.25
        case .callDeclined: return -0.5
        case .selfReportedConnected: return 0.6
        case .selfReportedNotConnected: return -0.15
        }
    }

    func prior(_ p: Person, weekday: Int, slot: Int) -> Double {
        let mid = slot * TimeKit.slotMinutes + TimeKit.slotMinutes / 2
        if p.prefs.isQuiet(minuteOfDay: mid) { return 0 }
        if p.prefs.busyWindow(weekday: weekday, minuteOfDay: mid) != nil { return 0.15 }
        return 0.5
    }

    public func buildModel(person p: Person, events: [ActivityEvent], now: Date) -> SlotModel {
        var pos = [Double](repeating: 0, count: TimeKit.slotsPerWeek)
        var neg = pos
        let tz = p.timeZone
        for e in events where e.personID == p.id && e.at <= now {
            let w = signal(e)
            if w == 0 { continue }
            let ageDays = now.timeIntervalSince(e.at) / 86_400
            let weight = abs(w) * pow(0.5, ageDays / config.halfLifeDays)
            let l = TimeKit.local(e.at, tz)
            let slot = l.minuteOfDay / TimeKit.slotMinutes
            for wd in 1...7 {
                let dayFactor = wd == l.weekday ? 1.0
                    : (TimeKit.isWeekend(wd) == TimeKit.isWeekend(l.weekday) ? config.dayTypeWeight : 0)
                if dayFactor == 0 { continue }
                for ds in -1...1 {
                    let s = slot + ds
                    guard s >= 0, s < TimeKit.slotsPerDay else { continue }
                    let f = dayFactor * (ds == 0 ? 1.0 : config.neighborWeight)
                    let idx = (wd - 1) * TimeKit.slotsPerDay + s
                    if w > 0 { pos[idx] += weight * f } else { neg[idx] += weight * f }
                }
            }
        }
        var cells: [SlotCell] = []
        cells.reserveCapacity(TimeKit.slotsPerWeek)
        for idx in 0..<TimeKit.slotsPerWeek {
            let wd = idx / TimeKit.slotsPerDay + 1, s = idx % TimeKit.slotsPerDay
            let pr = prior(p, weekday: wd, slot: s)
            let n = pos[idx] + neg[idx]
            let score = (config.priorStrength * pr + pos[idx]) / (config.priorStrength + n)
            cells.append(SlotCell(prior: pr, score: score,
                                  confidence: min(1, n / config.fullConfidenceEvidence), evidence: n))
        }
        return SlotModel(personID: p.id, cells: cells, builtAt: now)
    }

    /// Precedence: explicit override > quiet hours > stated busy window > learned > unknown.
    public func estimate(person p: Person, at instant: Date, model: SlotModel?,
                         overrides: [BusyOverride]) -> AvailabilityEstimate {
        if let o = overrides.first(where: { $0.personID == p.id && $0.isActive(at: instant) }) {
            return .init(level: .busy, score: 0, confidence: 1, source: .explicitOverride, until: o.end)
        }
        let l = TimeKit.local(instant, p.timeZone)
        if p.prefs.isQuiet(minuteOfDay: l.minuteOfDay) {
            return .init(level: .quietHours, score: 0, confidence: 1, source: .quietHours, until: nil)
        }
        if p.prefs.busyWindow(weekday: l.weekday, minuteOfDay: l.minuteOfDay) != nil {
            return .init(level: .busy, score: 0.1, confidence: 1, source: .preference, until: nil)
        }
        guard let model, model.cells.count == TimeKit.slotsPerWeek else {
            return .init(level: .learning, score: 0.5, confidence: 0, source: .insufficientEvidence, until: nil)
        }
        let cell = model.cells[TimeKit.slotIndex(instant, p.timeZone)]
        if cell.confidence < config.minConfidence {
            return .init(level: .learning, score: cell.score, confidence: cell.confidence,
                         source: .insufficientEvidence, until: nil)
        }
        let level: AvailabilityLevel = cell.score >= config.likelyThreshold ? .likelyFree
            : (cell.score >= config.maybeThreshold ? .maybeFree : .unlikely)
        return .init(level: level, score: cell.score, confidence: cell.confidence, source: .learned, until: nil)
    }

    /// Short, honest explanation. Always labels learned output as an estimate.
    public func explanation(for e: AvailabilityEstimate, name: String) -> String {
        switch e.source {
        case .explicitOverride: return "\(name) set Busy. That overrides any estimate."
        case .quietHours: return "Inside \(name)'s quiet hours (from their preferences)."
        case .preference: return "\(name) marked this time as usually busy."
        case .insufficientEvidence: return "Still learning \(name)'s pattern. Not enough activity yet to estimate."
        case .learned:
            switch e.level {
            case .likelyFree: return "\(name) often connects around this time. This is an estimate."
            case .maybeFree: return "Mixed signals around this time for \(name). This is an estimate."
            default: return "\(name) has connected less often around this time. Silence can mean many things. This is an estimate."
            }
        }
    }
}

// MARK: - Hard constraints for scheduling

public enum BlockReason: String, Codable, Sendable { case quietHours, busyOverride, busyWindow, existingBooking }

public enum Constraints {
    /// Returns why `person` cannot take a call over [start, end), or nil. Samples every
    /// 15 minutes plus the last instant so boundary crossings are caught.
    public static func blockReason(person p: Person, overrides: [BusyOverride], bookings: [Interval],
                                   start: Date, end: Date) -> BlockReason? {
        let span = Interval(start: start, end: end)
        if overrides.contains(where: { $0.personID == p.id && $0.overlaps(span) }) { return .busyOverride }
        if bookings.contains(where: { $0.overlaps(span) }) { return .existingBooking }
        var t = start
        var samples: [Date] = []
        while t < end { samples.append(t); t = t.addingTimeInterval(15 * 60) }
        samples.append(end.addingTimeInterval(-1))
        for s in samples {
            let l = TimeKit.local(s, p.timeZone)
            if p.prefs.isQuiet(minuteOfDay: l.minuteOfDay) { return .quietHours }
            if p.prefs.busyWindow(weekday: l.weekday, minuteOfDay: l.minuteOfDay) != nil { return .busyWindow }
        }
        return nil
    }
}
