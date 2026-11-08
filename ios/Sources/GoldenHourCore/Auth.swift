import Foundation

/// A signed-in Supabase user. Stored in the Keychain (shared with the widget), never in UserDefaults.
public struct AuthSession: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userID: String
    public var email: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, userID: String, email: String?) {
        self.accessToken = accessToken; self.refreshToken = refreshToken
        self.expiresAt = expiresAt; self.userID = userID; self.email = email
    }

    /// Refresh a minute early so a request never goes out with a token that dies in flight.
    public func needsRefresh(at now: Date = Date()) -> Bool { expiresAt.timeIntervalSince(now) < 60 }
}

public protocol SessionStore: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession?)
}

public enum AuthError: Error, LocalizedError, Equatable {
    case invalidEmail
    case invalidCode
    case signedOut
    case server(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidEmail: return "That doesn't look like an email address."
        case .invalidCode: return "Enter the code from the email (6 to 10 digits)."
        case .signedOut: return "Please sign in again."
        case .server(429, _): return "Too many emails right now. Wait a minute and try again."
        case .server(_, let message): return message
        }
    }
}

/// Email one-time-code sign-in against Supabase Auth's REST API (no SDK dependency).
public struct AuthClient: Sendable {
    public let config: BackendConfig
    private let session: URLSession
    private let now: @Sendable () -> Date

    public init(config: BackendConfig, session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config; self.session = session; self.now = now
    }

    public static func normalizedEmail(_ raw: String) -> String? {
        let e = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = e.split(separator: "@", omittingEmptySubsequences: false)
        guard e.count <= 254, parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."), !e.contains(" ") else { return nil }
        return e
    }

    public static func normalizedCode(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        return (6...10).contains(digits.count) && digits.count == raw.filter({ !$0.isWhitespace }).count ? digits : nil
    }

    /// Emails a sign-in code. Creates the account the first time.
    public func sendCode(to rawEmail: String) async throws {
        guard let email = Self.normalizedEmail(rawEmail) else { throw AuthError.invalidEmail }
        _ = try await post("otp", body: ["email": email, "create_user": true])
    }

    public func verify(email rawEmail: String, code rawCode: String) async throws -> AuthSession {
        guard let email = Self.normalizedEmail(rawEmail) else { throw AuthError.invalidEmail }
        guard let code = Self.normalizedCode(rawCode) else { throw AuthError.invalidCode }
        return try decodeSession(try await post("verify", body: ["type": "email", "email": email, "token": code]))
    }

    public func refresh(_ old: AuthSession) async throws -> AuthSession {
        do {
            return try decodeSession(try await post("token?grant_type=refresh_token", body: ["refresh_token": old.refreshToken]))
        } catch AuthError.server(let status, _) where (400..<500).contains(status) {
            throw AuthError.signedOut
        }
    }

    // MARK: wire

    struct TokenResponse: Decodable {
        struct User: Decodable { var id: String; var email: String? }
        var access_token: String
        var refresh_token: String
        var expires_in: Double
        var user: User
    }

    func decodeSession(_ data: Data) throws -> AuthSession {
        guard let t = try? JSONDecoder().decode(TokenResponse.self, from: data) else { throw BackendError.badResponse }
        return AuthSession(accessToken: t.access_token, refreshToken: t.refresh_token,
                           expiresAt: now().addingTimeInterval(t.expires_in), userID: t.user.id,
                           email: t.user.email?.isEmpty == false ? t.user.email : nil)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "auth/v1/\(path)", relativeTo: config.baseURL.appendingPathComponent("")) else {
            throw BackendError.badResponse
        }
        var req = URLRequest(url: url, timeoutInterval: BackendClient.timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AuthError.server(status: status, message: Self.message(data, status)) }
        return data
    }

    /// Supabase Auth errors come as {msg}, {message}, {error_description} or {error}.
    static func message(_ data: Data, _ status: Int) -> String {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let raw = ["msg", "message", "error_description", "error"].lazy.compactMap { obj?[$0] as? String }.first
        if status == 403 || raw?.localizedCaseInsensitiveContains("expired") == true || raw?.localizedCaseInsensitiveContains("invalid") == true {
            return "That code didn't work. Check the newest email, or send a new code."
        }
        return raw ?? "Sign-in failed (\(status))."
    }
}

/// Hands out a valid access token, refreshing and saving it when needed. One refresh at a time.
public actor TokenProvider {
    private let auth: AuthClient
    private let store: SessionStore
    private var inFlight: Task<AuthSession, Error>?

    public init(auth: AuthClient, store: SessionStore) { self.auth = auth; self.store = store }

    public var session: AuthSession? { store.load() }

    public func accessToken() async throws -> String {
        guard let s = store.load() else { throw AuthError.signedOut }
        if !s.needsRefresh() { return s.accessToken }
        if let inFlight { return try await inFlight.value.accessToken }
        let task = Task { try await auth.refresh(s) }
        inFlight = task
        defer { inFlight = nil }
        do {
            let fresh = try await task.value
            store.save(fresh)
            return fresh.accessToken
        } catch AuthError.signedOut {
            store.save(nil)
            throw AuthError.signedOut
        }
    }

    public func signIn(_ session: AuthSession) { store.save(session) }
    public func signOut() { store.save(nil) }
}
