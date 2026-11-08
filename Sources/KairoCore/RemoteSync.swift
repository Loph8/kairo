import Foundation

/// The ONLY availability data that may leave the device: coarse level + coarse evidence bucket per
/// 30-minute slot, with an expiry. No raw events, no numeric scores.
/// Tradeoff: even coarse levels reveal a person's rhythm to family members. That is the minimum the
/// scheduler needs. If a server-side optimizer ever needed numeric scores, that would be a larger
/// disclosure and must be an explicit, opt-in setting.
public struct SharedAvailabilitySummary: Codable, Hashable, Sendable {
    public enum Confidence: String, Codable, Sendable { case low, medium, high }
    public var personID: String
    public var slotStart: Date
    public var level: AvailabilityLevel
    public var confidence: Confidence
    public var validUntil: Date
}

public enum SummaryBuilder {
    public static func make(person: Person, model: SlotModel?, overrides: [BusyOverride], now: Date,
                            scorer: AvailabilityScorer = .init(), hours: Int = 48, validFor: TimeInterval = 24 * 3600) -> [SharedAvailabilitySummary] {
        let start = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 1800) * 1800)
        return (0..<(hours * 2)).map { i in
            let t = start.addingTimeInterval(Double(i) * 1800)
            let e = scorer.estimate(person: person, at: t.addingTimeInterval(60), model: model, overrides: overrides)
            let c: SharedAvailabilitySummary.Confidence = e.confidence >= 0.66 ? .high : (e.confidence >= 0.25 ? .medium : .low)
            return .init(personID: person.id, slotStart: t, level: e.level, confidence: c, validUntil: now.addingTimeInterval(validFor))
        }
    }
}

/// Production sync boundary. Demo mode uses no remote at all (state is device-local and says so).
/// A Supabase adapter implements this against supabase/migrations (RPCs enforce authorization).
public protocol RemoteSyncing: Sendable {
    func pushAvailability(_ summaries: [SharedAvailabilitySummary]) async throws
    func confirm(proposalID: String) async throws        // server derives the participant from the JWT
    func decline(proposalID: String) async throws
    func setBusy(until: Date) async throws
}

public struct UnconfiguredRemoteSync: RemoteSyncing {
    public init() {}
    public func pushAvailability(_ s: [SharedAvailabilitySummary]) async throws { throw RepositoryError.notConfigured }
    public func confirm(proposalID: String) async throws { throw RepositoryError.notConfigured }
    public func decline(proposalID: String) async throws { throw RepositoryError.notConfigured }
    public func setBusy(until: Date) async throws { throw RepositoryError.notConfigured }
}
