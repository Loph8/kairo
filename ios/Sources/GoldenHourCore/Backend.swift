import Foundation

/// Where the Supabase `api` edge function lives. Read from Info.plist (filled by Config/Secrets.xcconfig).
/// The anon key is public by design: it can only read; every write goes through the `api` function.
public struct BackendConfig: Sendable, Equatable {
    public var baseURL: URL
    public var anonKey: String

    public init(baseURL: URL, anonKey: String) { self.baseURL = baseURL; self.anonKey = anonKey }

    /// nil when the keys are missing or still the example placeholders, so the app stays in local demo mode.
    public init?(info: [String: Any]?) {
        guard let raw = (info?["SUPABASE_URL"] as? String)?.trimmingCharacters(in: .whitespaces),
              let key = (info?["SUPABASE_ANON_KEY"] as? String)?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty, !key.isEmpty, !raw.contains("YOUR-PROJECT"), !key.hasPrefix("YOUR_"),
              let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        self.init(baseURL: url, anonKey: key)
    }

    public var endpoint: URL { baseURL.appendingPathComponent("functions/v1/api") }
}

// MARK: wire format (mirrors supabase/functions/_shared/familyState.ts and api.ts)

public struct ServerState: Decodable, Sendable, Equatable {
    public struct Member: Decodable, Sendable, Equatable, Identifiable {
        public var id: String, name: String, city: String, tz: String
        public var simulated: Bool
        /// Next 24h in 30-minute slots: "G", "Y" or "R".
        public var levels: [String]
        /// What the AI learned: 48 weekday + 48 weekend local slots.
        public var week: String
        /// What onboarding said, same layout as `week`.
        public var said: String
        public var insights: [String]
        public var signals: Int
        /// Their verified-account phone number (E.164). Older servers don't send it.
        public var phone: String?
        /// Usernames or numbers for connected apps, keyed by app id ("whatsapp", "wechat"…).
        public var apps: [String: String]?
    }
    public struct Suggestion: Decodable, Sendable, Equatable {
        public var start: Date, end: Date
        public var levels: [String: String]
        public var pickup: [String: Double]
        public var everyoneLikely: Bool
    }
    public struct Move: Decodable, Sendable, Equatable {
        public var blockId: String, memberId: String
        public var from: Date, to: Date, frees: Date
    }
    public struct Booking: Decodable, Sendable, Equatable {
        public var id: String, start: Date, end: Date
        public var acceptedBy: [String]
        public var status: String
    }
    /// The most recent live signal and which cells of that person's week it changed.
    public struct Change: Decodable, Sendable, Equatable {
        public struct Cell: Decodable, Sendable, Equatable { public var cell: Int; public var from: String; public var to: String }
        public var memberId: String
        public var at: Date
        public var source: String
        public var kind: String
        public var positive: Bool
        public var changed: [Cell]
    }
    public var now: Date
    public var forecastStart: Date
    public var isDemo: Bool
    public var members: [Member]
    public var suggestion: Suggestion?
    public var moves: [Move]
    public var bookings: [Booking]
    public var lastChange: Change?
    /// One-line reason for the suggestion (Claude, or a template when Claude is unavailable).
    public var note: String?
}

/// One family this account belongs to.
/// Someone opened the family's group call link. Shown to everyone as "Join" for a while.
public struct GroupCall: Decodable, Sendable, Equatable {
    public var startedBy: String
    public var at: Date
}

public struct FamilyRef: Decodable, Sendable, Equatable, Identifiable {
    public var familyId: String
    public var familyName: String
    public var inviteCode: String
    /// The family's shared group-call link (FaceTime, Zoom, Meet…). Nil until someone sets one.
    public var callLink: String? = nil
    public var id: String { familyId }
}

public struct Account: Decodable, Sendable, Equatable {
    public var email: String?
    /// The family this result is about. Older servers don't send it.
    public var familyId: String?
    public var familyName: String
    public var inviteCode: String
    /// The open family's shared group-call link. Older servers don't send it.
    public var callLink: String?
    /// A group call someone started in the last 45 minutes.
    public var groupCall: GroupCall?
    public var memberId: String
    /// Every family this account is in, oldest first.
    public var families: [FamilyRef]?

    public var allFamilies: [FamilyRef] {
        families ?? familyId.map { [FamilyRef(familyId: $0, familyName: familyName, inviteCode: inviteCode, callLink: callLink)] } ?? []
    }
}

/// What every call returns: who you are and your family's state. Both nil until you create or join a family.
public struct ServerResult: Sendable, Equatable {
    public var account: Account?
    public var state: ServerState?
}

public struct Profile: Sendable, Equatable {
    public var name: String
    public var timeZoneID: String
    public var city: String
    public var wake: String
    public var bed: String
    public var busy: [[String]]
    /// Your number with country code, used by your family to call you (one-to-one and group).
    public var phone: String?

    public init(name: String, timeZoneID: String, city: String, wake: String, bed: String, busy: [[String]],
                phone: String? = nil) {
        self.name = name; self.timeZoneID = timeZoneID; self.city = city
        self.wake = wake; self.bed = bed; self.busy = busy; self.phone = phone
    }

    var body: [String: Any] {
        var b: [String: Any] = ["name": name, "tz": timeZoneID, "city": city, "wake": wake, "bed": bed, "busy": busy]
        if let phone { b["phone"] = phone }
        return b
    }
}

public enum SimulatedEvent: String, CaseIterable, Sendable {
    case answerCall = "answer_call", missCall = "miss_call", replyFast = "reply_fast", noReply = "no_reply", free, busy

    public var title: String {
        switch self {
        case .answerCall: return "Picked up"
        case .missCall: return "Missed a call"
        case .replyFast: return "Replied fast"
        case .noReply: return "Didn't reply"
        case .free: return "Tapped Free"
        case .busy: return "Tapped Busy"
        }
    }

    public var symbol: String {
        switch self {
        case .answerCall: return "phone.fill"
        case .missCall: return "phone.down.fill"
        case .replyFast: return "bubble.left.fill"
        case .noReply: return "bubble.left"
        case .free: return "checkmark.circle.fill"
        case .busy: return "moon.fill"
        }
    }
}

public enum BackendError: Error, LocalizedError, Equatable {
    case server(status: Int, message: String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .server(_, let message): return message.prefix(1).uppercased() + message.dropFirst() + "."
        case .badResponse: return "The server sent something we couldn't read."
        }
    }

    public var isSignedOut: Bool { if case .server(401, _) = self { return true }; return false }
}

// MARK: client

public struct BackendClient: Sendable {
    public typealias TokenSource = @Sendable () async throws -> String
    public let config: BackendConfig
    private let token: TokenSource
    private let session: URLSession
    /// Which of your families to talk about. nil means your first family.
    private let familyID: @Sendable () -> String?
    public static let timeout: TimeInterval = 15

    public init(config: BackendConfig, token: @escaping TokenSource, session: URLSession = .shared,
                familyID: @escaping @Sendable () -> String? = { nil }) {
        self.config = config; self.token = token; self.session = session; self.familyID = familyID
    }

    public func me() async throws -> ServerResult { try await send(["action": "me"]) }
    public func state() async throws -> ServerResult { try await send(["action": "state"]) }

    public func createFamily(name familyName: String, profile: Profile) async throws -> ServerResult {
        try await send(profile.body.merging(["action": "create_family", "family_name": familyName]) { $1 })
    }

    /// Loads one of your families by id.
    public func state(familyID: String) async throws -> ServerResult {
        try await send(["action": "state", "family_id": familyID])
    }

    public func joinFamily(code: String, profile: Profile) async throws -> ServerResult {
        try await send(profile.body.merging(["action": "join_family", "invite_code": code]) { $1 })
    }

    /// Adds Mom, Grandpa and Dad as simulated relatives with two weeks of history.
    public func addDemoFamily() async throws -> ServerResult { try await send(["action": "add_demo_family"]) }
    public func resetFamily() async throws -> ServerResult { try await send(["action": "reset_family"]) }
    /// Removes you from your family. If nobody real is left, the family and its invite code are deleted.
    public func leaveFamily() async throws -> ServerResult { try await send(["action": "leave_family"]) }
    /// Saves your number and connected apps (WhatsApp, WeChat…) on every family you're in.
    public func setContact(phone: String?, apps: [String: String]) async throws -> ServerResult {
        try await send(["action": "set_contact", "phone": phone ?? NSNull(), "apps": apps])
    }

    /// Tells the family you opened the group call, so their app shows "Join".
    public func startGroupCall() async throws -> ServerResult { try await send(["action": "start_group_call"]) }
    /// Sets (or with nil, removes) the open family's shared group-call link.
    public func setCallLink(_ link: String?) async throws -> ServerResult {
        var body: [String: Any] = ["action": "set_call_link"]
        body["link"] = link ?? NSNull()
        return try await send(body)
    }

    public func simulate(_ event: SimulatedEvent, for memberID: String) async throws -> ServerResult {
        try await send(["action": "simulate", "member_id": memberID, "event": event.rawValue])
    }

    /// Adds you to the family call at `start`. It becomes booked when everyone real has joined.
    public func join(start: Date) async throws -> ServerResult {
        try await send(["action": "join", "start": Self.iso(start)])
    }

    /// Timing and outcome only. There is deliberately no parameter for message content.
    public func logCall(answered: Bool, for memberID: String) async throws -> ServerResult {
        try await send(["action": "log_outcome", "member_id": memberID, "kind": "call", "answered": answered, "source": "family_call"])
    }

    /// A text from `memberID` just arrived (from the Shortcuts automation): they were awake and active.
    public func logTextArrived(from memberID: String) async throws -> ServerResult {
        try await send(["action": "log_outcome", "member_id": memberID, "kind": "text", "reply_seconds": 60, "source": "shortcut"])
    }

    public func logLabel(free: Bool) async throws -> ServerResult {
        try await send(["action": "log_outcome", "kind": "label", "free": free, "source": "widget"])
    }

    /// Replaces your calendar busy blocks on the server (ids are opaque hashes, no titles).
    public func pushBusy(_ blocks: [BusyBlockPayload]) async throws -> ServerResult {
        let rows: [[String: Any]] = blocks.map {
            ["id": $0.id, "start": Self.iso($0.start), "end": Self.iso($0.end), "movable": $0.movable]
        }
        return try await send(["action": "push_busy", "blocks": rows])
    }

    private struct Envelope: Decodable { var ok: Bool?; var account: Account?; var state: ServerState?; var error: String? }

    private func send(_ body: [String: Any]) async throws -> ServerResult {
        var req = URLRequest(url: config.endpoint, timeoutInterval: Self.timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        var body = body
        if body["family_id"] == nil, let id = familyID() { body["family_id"] = id }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let env: Envelope?
        do { env = try Self.decoder.decode(Envelope.self, from: data) } catch {
            guard (200..<300).contains(status) else { throw BackendError.server(status: status, message: "server error \(status)") }
            throw BackendError.badResponse
        }
        guard (200..<300).contains(status) else {
            throw BackendError.server(status: status, message: env?.error ?? "server error \(status)")
        }
        guard let env, env.ok == true else { throw BackendError.badResponse }
        return ServerResult(account: env.account, state: env.state)
    }

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    /// The server sends `2026-11-10T23:00:00.000Z` (with milliseconds), which `.iso8601` rejects.
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()
}

// MARK: server state → widget snapshot

/// Family calls are identified by their start time, so a widget tap needs no lookup.
public enum FamilyProposalID {
    static let prefix = "family-"
    public static func make(_ start: Date) -> String { prefix + String(Int(start.timeIntervalSince1970)) }
    public static func start(of id: String) -> Date? {
        guard id.hasPrefix(prefix), let secs = Int(id.dropFirst(prefix.count)) else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(secs))
    }
}

public enum ServerSnapshot {
    public static func level(_ code: String) -> AvailabilityLevel {
        switch code {
        case "G": return .likelyFree
        case "Y": return .maybeFree
        case "R": return .unlikely
        default: return .learning
        }
    }

    public static func viewerState(_ b: ServerState.Booking, viewerID: String) -> ViewerBookingState {
        if b.status == "booked" { return .confirmed }
        if b.status == "completed" { return .completed }
        if b.acceptedBy.contains(viewerID) { return .awaitingOther }
        return b.acceptedBy.isEmpty ? .suggested : .awaitingYou
    }

    public static func make(_ s: ServerState, viewerID: String, realNow: Date = Date(),
                            use24Hour: Bool = false, focusPersonID: String? = nil) -> WidgetSnapshot {
        let viewer = s.members.first { $0.id == viewerID }
        let others = s.members.filter { $0.id != viewerID }
        let people = others.map { m in
            WidgetPerson(id: m.id, name: m.name, relationship: m.name, city: m.city, flag: nil,
                         initials: String(m.name.prefix(1)).uppercased(), timeZoneID: m.tz,
                         forecast: m.levels.map(level))
        }
        let calls = familyCalls(s, viewerID: viewerID)
        // One entry per other member so each member's widget shows the same family call.
        let proposals = others.flatMap { m in
            calls.map { c in
                WidgetProposal(id: c.id, personID: m.id, personName: m.name, start: c.start, end: c.end,
                               state: c.state, explanation: c.explanation)
            }
        }
        let focus = focusPersonID.flatMap { id in others.first { $0.id == id }?.id } ?? others.first?.id ?? ""
        return WidgetSnapshot(generatedAt: s.now, forecastStart: s.forecastStart,
                              clockOffset: s.now.timeIntervalSince(realNow), viewerID: viewerID,
                              viewerName: viewer?.name ?? "You",
                              viewerTimeZoneID: viewer?.tz ?? TimeZone.current.identifier,
                              use24Hour: use24Hour, focusPersonID: focus, people: people,
                              proposals: proposals, busyUntil: nil, sync: .synced(realNow), isDemo: s.isDemo,
                              viewerForecast: viewer.map { $0.levels.map(level) })
    }

    struct Call { var id: String; var start: Date; var end: Date; var state: ViewerBookingState; var explanation: String }

    /// Bookings first; the suggestion only when nobody has started joining it yet.
    static func familyCalls(_ s: ServerState, viewerID: String) -> [Call] {
        let total = s.members.filter { !$0.simulated }.count
        var calls = s.bookings.map { b in
            Call(id: FamilyProposalID.make(b.start), start: b.start, end: b.end,
                 state: viewerState(b, viewerID: viewerID),
                 explanation: b.status == "booked" ? "Everyone's in." : "\(b.acceptedBy.count) of \(total) joined.")
        }
        if let sug = s.suggestion, !s.bookings.contains(where: { $0.start == sug.start }) {
            calls.append(Call(id: FamilyProposalID.make(sug.start), start: sug.start, end: sug.end,
                              state: .suggested, explanation: explain(sug, s)))
        }
        return calls.sorted { $0.start < $1.start }
    }

    static func explain(_ sug: ServerState.Suggestion, _ s: ServerState) -> String {
        if let note = s.note, !note.isEmpty { return note }
        if sug.everyoneLikely { return "Everyone is likely free." }
        let names = s.members.filter { sug.levels[$0.id] == "R" }.map(\.name)
        let base = names.isEmpty ? "Best time we found." : "Best time we found; \(names.joined(separator: ", ")) may not pick up."
        return s.moves.isEmpty ? base : base + " Moving one calendar event would free everyone."
    }
}
