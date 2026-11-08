import Foundation
import CryptoKit

/// The pure parts of "Connect Google Calendar": the sign-in URL (OAuth 2 with PKCE, no client secret,
/// as Google requires for iOS apps), the token responses and the free/busy reply.
/// Kairos asks only for free/busy: Google sends start and end times, never titles, places or guests.
public enum GoogleOAuth {
    public static let scopes = ["openid", "email", "https://www.googleapis.com/auth/calendar.freebusy"]
    public static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    public static let freeBusyEndpoint = URL(string: "https://www.googleapis.com/calendar/v3/freeBusy")!

    public enum Failure: LocalizedError, Equatable {
        case badReply, stateMismatch, denied(String), notSignedIn
        public var errorDescription: String? {
            switch self {
            case .badReply: "Google sent an unexpected reply. Try again."
            case .stateMismatch: "The Google sign-in didn't match. Try again."
            case .denied(let why): "Google said no: \(why)."
            case .notSignedIn: "Google Calendar isn't connected."
            }
        }
    }

    /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc". Google's iOS redirect scheme.
    public static func redirectScheme(clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    public static func redirectURI(clientID: String) -> String { "\(redirectScheme(clientID: clientID)):/oauth2redirect" }

    /// A random 64-character verifier (RFC 7636 allows 43–128 unreserved characters).
    public static func makeVerifier() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var rng = SystemRandomNumberGenerator()
        return String((0..<64).map { _ in chars[Int(rng.next() % UInt64(chars.count))] })
    }

    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    public static func authURL(clientID: String, verifier: String, state: String) -> URL {
        var c = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI(clientID: clientID)),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "consent"),        // always returns a refresh token
            .init(name: "access_type", value: "offline"),
        ]
        return c.url!
    }

    /// The `code` from Google's redirect, after checking `state` and any error.
    public static func code(fromRedirect url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let error = value("error") { throw Failure.denied(error.replacingOccurrences(of: "_", with: " ")) }
        guard value("state") == expectedState else { throw Failure.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw Failure.badReply }
        return code
    }

    /// Form body for the token endpoint (exchange or refresh).
    public static func formBody(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = fields.map { k, v in "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)" }
        return Data(pairs.joined(separator: "&").utf8)
    }

    public struct Tokens: Decodable, Sendable, Equatable {
        public var accessToken: String
        public var expiresIn: Double
        public var refreshToken: String?
        public var idToken: String?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", expiresIn = "expires_in", refreshToken = "refresh_token", idToken = "id_token"
        }
    }

    public static func tokens(from data: Data) throws -> Tokens {
        if let err = try? JSONDecoder().decode([String: String].self, from: data), let e = err["error"] {
            throw Failure.denied(err["error_description"] ?? e)
        }
        guard let t = try? JSONDecoder().decode(Tokens.self, from: data) else { throw Failure.badReply }
        return t
    }

    /// The signed-in email, read from the ID token Google just sent us over TLS (display only, not trusted for auth).
    public static func email(fromIDToken token: String?) -> String? {
        guard let token, case let parts = token.split(separator: "."), parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["email"] as? String
    }

    public static func freeBusyBody(window: DateInterval) -> Data {
        let f = ISO8601DateFormatter()
        let body: [String: Any] = [
            "timeMin": f.string(from: window.start), "timeMax": f.string(from: window.end),
            "items": [["id": "primary"]],
        ]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    /// Google's busy intervals as calendar events. They can't be moved from Kairos, so they count as meetings with others.
    public static func busyEvents(from data: Data) throws -> [CalendarEventInfo] {
        struct Reply: Decodable {
            struct Cal: Decodable {
                struct Span: Decodable { var start: String; var end: String }
                struct Err: Decodable { var reason: String }
                var busy: [Span]?
                var errors: [Err]?
            }
            var calendars: [String: Cal]?
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), let cal = reply.calendars?["primary"] else {
            throw Failure.badReply
        }
        if let reason = cal.errors?.first?.reason { throw Failure.denied(reason) }
        let plain = ISO8601DateFormatter()
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parse = { (s: String) in plain.date(from: s) ?? frac.date(from: s) }
        return (cal.busy ?? []).compactMap { span in
            guard let start = parse(span.start), let end = parse(span.end), end > start else { return nil }
            return CalendarEventInfo(identifier: "google|\(span.start)|\(span.end)", start: start, end: end, hasOtherAttendees: true)
        }
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
