import Foundation

// MARK: - Minimal JSON value for tool arguments/results

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var number: Double? { if case .number(let n) = self { return n }; return nil }
    var strings: [String]? {
        guard case .array(let a) = self else { return nil }
        let s = a.compactMap(\.string); return s.count == a.count ? s : nil
    }
}

public enum ToolCaller: Equatable, Sendable {
    /// The Claude-driven agent. May read, rank and create proposals. Never consents.
    case agent
    /// A person acting through the UI.
    case user(String)
}

public struct ToolError: Error, Equatable, Sendable { public let message: String }

/// Local mirror of the server-side tool contract (supabase/functions/agent). Every argument is
/// validated here exactly as the server validates it; the deterministic fallback uses this router.
public struct ToolRouter: Sendable {
    public let repo: LocalDemoRepository
    public init(repo: LocalDemoRepository) { self.repo = repo }

    public static let toolNames = ["get_shared_availability", "get_scheduling_preferences", "get_recent_scheduling_burden",
                                   "rank_candidate_windows", "create_proposal", "confirm_proposal", "decline_proposal"]

    private func people(_ args: [String: JSONValue], _ s: AppState) throws -> [Person] {
        guard let ids = args["participants"]?.strings, (2...6).contains(ids.count), Set(ids).count == ids.count else {
            throw ToolError(message: "participants must be 2–6 unique ids")
        }
        let ps = ids.compactMap { s.person($0) }
        guard ps.count == ids.count else { throw ToolError(message: "unknown participant") }
        return ps
    }
    private func date(_ v: JSONValue?, _ name: String) throws -> Date {
        guard let s = v?.string, let d = ISO8601DateFormatter().date(from: s) else {
            throw ToolError(message: "\(name) must be an ISO-8601 instant")
        }
        return d
    }
    private func minutes(_ args: [String: JSONValue]) throws -> Int {
        guard let n = args["duration_minutes"]?.number else { return 30 }
        guard n == n.rounded(), (15...120).contains(Int(n)) else { throw ToolError(message: "duration_minutes must be 15–120") }
        return Int(n)
    }

    public func call(_ name: String, _ args: [String: JSONValue], as caller: ToolCaller) async throws -> JSONValue {
        let s = await repo.loadState()
        let now = await repo.now()
        switch name {
        case "get_shared_availability":
            let ps = try people(args, s)
            let start = try date(args["start"], "start"), end = try date(args["end"], "end")
            guard end > start, end.timeIntervalSince(start) <= 7 * 86_400 else { throw ToolError(message: "invalid range") }
            let models = repo.models(s, now: now)
            // Coarse level + confidence bucket only. Raw scores are never shared.
            let out: [JSONValue] = ps.map { p in
                let e = repo.engine.scorer.estimate(person: p, at: start, model: models[p.id], overrides: s.overrides)
                let bucket = e.confidence >= 0.66 ? "high" : (e.confidence >= 0.25 ? "medium" : "low")
                return .object(["person": .string(p.id), "level": .string(e.level.rawValue), "confidence": .string(bucket)])
            }
            return .array(out)
        case "get_scheduling_preferences":
            guard let id = args["person"]?.string, let p = s.person(id) else { throw ToolError(message: "unknown person") }
            return .object(["person": .string(id), "time_zone": .string(p.timeZoneID),
                            "quiet_start_minute": .number(Double(p.prefs.bedMinute)),
                            "quiet_end_minute": .number(Double(p.prefs.wakeMinute)),
                            "preferred_minutes": .number(Double(p.prefs.preferredCallMinutes))])
        case "get_recent_scheduling_burden":
            let ps = try people(args, s)
            return .object(Dictionary(uniqueKeysWithValues: ps.map {
                ($0.id, JSONValue.number(repo.engine.burdenLoad($0.id, burdens: s.burdens, now: now))) }))
        case "rank_candidate_windows":
            let ps = try people(args, s)
            let ranked = repo.engine.rank(participants: ps, models: repo.models(s, now: now), overrides: s.overrides,
                                          bookings: repo.bookings(s), burdens: s.burdens, now: now,
                                          durationMinutes: try minutes(args))
            let f = ISO8601DateFormatter()
            return .array(ranked.map { w in .object([
                "id": .string(w.id), "start": .string(f.string(from: w.start)), "end": .string(f.string(from: w.end)),
                "explanation": .string(w.explanation)]) })
        case "create_proposal":
            let ps = try people(args, s)
            let start = try date(args["start"], "start")
            let creator: String
            switch caller { case .agent: creator = "agent"; case .user(let id): creator = id }
            do {
                let p = try repo.createProposal(participants: ps.map(\.id), start: start, minutes: try minutes(args),
                                                createdBy: creator, explanation: args["explanation"]?.string.map { String($0.prefix(240)) } ?? "")
                return .object(["id": .string(p.id), "status": .string(p.status.rawValue)])
            } catch RepositoryError.invalid(let why) { throw ToolError(message: why) }
        case "confirm_proposal", "decline_proposal":
            // Consent belongs to people. The agent can never act for a participant.
            guard case .user(let actor) = caller else { throw ToolError(message: "agent cannot impersonate participant consent") }
            guard let pid = args["proposal_id"]?.string, let who = args["person"]?.string, who == actor else {
                throw ToolError(message: "person must be the authenticated user")
            }
            if name == "confirm_proposal" {
                let o = try await repo.confirm(proposalID: pid, as: actor)
                if case .rejected(let r) = o.result { throw ToolError(message: r.rawValue) }
                return .object(["status": .string(o.proposal?.status.rawValue ?? "unknown")])
            }
            let r = try await repo.decline(proposalID: pid, as: actor)
            if case .rejected(let why) = r { throw ToolError(message: why.rawValue) }
            return .object(["status": .string("declined")])
        default:
            throw ToolError(message: "unknown tool")
        }
    }
}

// MARK: - Explanations (Claude when reachable, deterministic otherwise)

public protocol ExplanationProviding: Sendable {
    func explain(_ window: RankedWindow) async -> String
}

public struct DeterministicExplainer: ExplanationProviding {
    public init() {}
    public func explain(_ window: RankedWindow) async -> String { window.explanation }
}

/// Calls the server-side function. The request carries only scheduling facts (levels, coarse
/// confidence, inconvenience, fairness) and never message content, audio, or raw events.
/// Any failure falls back to the deterministic explanation. The model cannot change the window.
public struct RemoteClaudeExplainer: ExplanationProviding {
    public var endpoint: URL
    public var bearerToken: String   // user's Supabase JWT, never a service key
    public var session: URLSession
    public init(endpoint: URL, bearerToken: String, session: URLSession = .shared) {
        self.endpoint = endpoint; self.bearerToken = bearerToken; self.session = session
    }
    public func explain(_ w: RankedWindow) async -> String {
        struct Fit: Encodable { var name: String; var level: String; var confidence: Double; var inconvenience: Double }
        struct Body: Encodable { var window_id: String; var fits: [Fit]; var fairness_penalty: Double; var fallback: String }
        let body = Body(window_id: w.id,
                        fits: w.fits.map { .init(name: $0.name, level: $0.level.rawValue, confidence: $0.confidence, inconvenience: $0.inconvenience) },
                        fairness_penalty: w.fairnessPenalty, fallback: w.explanation)
        var req = URLRequest(url: endpoint, timeoutInterval: 6)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        guard let data = try? JSONEncoder().encode(body) else { return w.explanation }
        req.httpBody = data
        guard let (out, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
              let text = obj["explanation"] as? String, !text.isEmpty, text.count < 300 else { return w.explanation }
        return text
    }
}
