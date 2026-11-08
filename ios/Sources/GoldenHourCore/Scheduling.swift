import Foundation

public struct SchedulingConfig: Codable, Sendable {
    public var durationMinutes = 30
    public var horizonHours = 72
    public var leadMinutes = 30
    public var overallWeight = 0.5
    public var leastConvenientWeight = 0.5
    public var fairnessWeight = 0.3
    /// How much a start/end outside the comfortable hours reduces a person's fit.
    public var comfortPenalty = 0.35
    public var comfortStartHour = 9
    public var comfortEndHour = 21
    public var topCount = 3
    public var minSeparationMinutes = 120
    /// Bounded, explainable fairness memory.
    public var burdenHistoryLimit = 10
    public var burdenHalfLifeDays = 14.0
    public init() {}
}

/// A record that a confirmed call was inconvenient for someone (0…1).
public struct Burden: Codable, Hashable, Sendable {
    public var personID: String
    public var at: Date
    public var amount: Double
    public var proposalID: String
    public init(personID: String, at: Date, amount: Double, proposalID: String) {
        self.personID = personID; self.at = at; self.amount = amount; self.proposalID = proposalID
    }
}

public struct BookedInterval: Codable, Hashable, Sendable {
    public var personIDs: [String]
    public var interval: Interval
    public init(personIDs: [String], interval: Interval) { self.personIDs = personIDs; self.interval = interval }
}

public struct PersonFit: Codable, Hashable, Sendable {
    public var personID: String
    public var name: String
    public var level: AvailabilityLevel
    public var fit: Double
    public var confidence: Double
    public var inconvenience: Double
}

public struct RankedWindow: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var start: Date
    public var end: Date
    public var participants: [String]
    public var fits: [PersonFit]
    public var overall: Double
    public var leastConvenient: Double
    public var fairnessPenalty: Double
    public var total: Double
    public var explanation: String
}

/// Deterministic scheduler. The LLM never touches this logic.
///
///   fit(p)   = meanScore(p, window) × (1 − comfortPenalty × inconvenience(p, window))
///   total    = wOverall·mean(fit) + wLeast·min(fit) − wFair·fairnessPenalty
///   fairnessPenalty = mean over p of burdenLoad(p) × inconvenience(p, window)
///
/// Hard constraints (quiet hours, Busy overrides, busy windows, existing bookings) are
/// filtered out before scoring and can never be outweighed by the score.
public struct SchedulingEngine: Sendable {
    public var config: SchedulingConfig
    public var scorer: AvailabilityScorer
    public init(config: SchedulingConfig = .init(), scorer: AvailabilityScorer = .init()) {
        self.config = config; self.scorer = scorer
    }

    public static func proposalID(start: Date, participants: [String]) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmm'Z'"
        return "p-\(f.string(from: start))-\(participants.sorted().joined(separator: "+"))"
    }

    public func inconvenience(_ p: Person, at d: Date) -> Double {
        let m = TimeKit.local(d, p.timeZone).minuteOfDay
        return (m >= config.comfortStartHour * 60 && m < config.comfortEndHour * 60) ? 0 : 0.5
    }

    public func burdenLoad(_ personID: String, burdens: [Burden], now: Date) -> Double {
        let recent = burdens.filter { $0.personID == personID }.sorted { $0.at > $1.at }
            .prefix(config.burdenHistoryLimit)
        let sum = recent.reduce(0.0) { acc, b in
            acc + b.amount * pow(0.5, max(0, now.timeIntervalSince(b.at)) / 86_400 / config.burdenHalfLifeDays)
        }
        return min(1, sum / 2)
    }

    public func rank(participants: [Person], models: [String: SlotModel], overrides: [BusyOverride],
                     bookings: [BookedInterval], burdens: [Burden], now: Date,
                     durationMinutes: Int? = nil) -> [RankedWindow] {
        guard participants.count >= 2 else { return [] }
        let dur = TimeInterval((durationMinutes ?? config.durationMinutes) * 60)
        let step: TimeInterval = 30 * 60
        let first = ((now.timeIntervalSince1970 + Double(config.leadMinutes) * 60) / step).rounded(.up) * step
        let horizonEnd = now.addingTimeInterval(Double(config.horizonHours) * 3600)
        let ids = participants.map(\.id)
        let loads = Dictionary(uniqueKeysWithValues: participants.map {
            ($0.id, burdenLoad($0.id, burdens: burdens, now: now)) })
        var ranked: [RankedWindow] = []

        var t = first
        while Date(timeIntervalSince1970: t) < horizonEnd {
            let start = Date(timeIntervalSince1970: t), end = start.addingTimeInterval(dur)
            t += step
            var fits: [PersonFit] = []
            var blocked = false
            for p in participants {
                let mine = bookings.filter { $0.personIDs.contains(p.id) }.map(\.interval)
                if Constraints.blockReason(person: p, overrides: overrides, bookings: mine,
                                           start: start, end: end) != nil { blocked = true; break }
                var scores: [Double] = [], conf: [Double] = []
                var s = start
                while s < end {
                    let e = scorer.estimate(person: p, at: s, model: models[p.id], overrides: overrides)
                    scores.append(e.score); conf.append(e.confidence)
                    s = s.addingTimeInterval(15 * 60)
                }
                let inc = max(inconvenience(p, at: start), inconvenience(p, at: end.addingTimeInterval(-1)))
                let mean = scores.reduce(0, +) / Double(scores.count)
                let startEst = scorer.estimate(person: p, at: start, model: models[p.id], overrides: overrides)
                fits.append(.init(personID: p.id, name: p.name, level: startEst.level,
                                  fit: mean * (1 - config.comfortPenalty * inc),
                                  confidence: conf.min() ?? 0, inconvenience: inc))
            }
            if blocked { continue }
            let overall = fits.map(\.fit).reduce(0, +) / Double(fits.count)
            let least = fits.map(\.fit).min() ?? 0
            let penalty = fits.map { (loads[$0.personID] ?? 0) * $0.inconvenience }.reduce(0, +) / Double(fits.count)
            let total = config.overallWeight * overall + config.leastConvenientWeight * least
                - config.fairnessWeight * penalty
            ranked.append(.init(id: Self.proposalID(start: start, participants: ids), start: start, end: end,
                                participants: ids, fits: fits, overall: overall, leastConvenient: least,
                                fairnessPenalty: penalty, total: total,
                                explanation: explain(fits, loads: loads)))
        }
        ranked.sort { $0.total != $1.total ? $0.total > $1.total : $0.start < $1.start }

        var picked: [RankedWindow] = []
        for c in ranked {
            let sep = TimeInterval(config.minSeparationMinutes * 60)
            if picked.allSatisfy({ abs($0.start.timeIntervalSince(c.start)) >= sep }) { picked.append(c) }
            if picked.count == config.topCount { break }
        }
        return picked.sorted { $0.start < $1.start }   // present by absolute instant
    }

    /// Deterministic fallback explanation. Built only from computed facts.
    func explain(_ fits: [PersonFit], loads: [String: Double]) -> String {
        var parts = [fits.count == 2 ? "Both people are outside quiet hours and busy times." :
                        "Everyone is outside quiet hours and busy times."]
        if let low = fits.min(by: { $0.fit < $1.fit }) {
            parts.append("Least convenient for \(low.name): \(low.level.label.lowercased()).")
        }
        if let favored = fits.first(where: { (loads[$0.personID] ?? 0) >= 0.3 && $0.inconvenience == 0 }) {
            parts.append("\(favored.name) had a less convenient call recently, so this window favors them.")
        }
        if let learning = fits.first(where: { $0.confidence < scorer.config.minConfidence }) {
            parts.append("\(learning.name)'s pattern is still being learned, so treat this as an estimate.")
        }
        return parts.joined(separator: " ")
    }
}
