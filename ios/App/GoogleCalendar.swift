import AuthenticationServices
import Foundation
import GoldenHourCore
import Security
import UIKit

/// "Connect Google Calendar": signs in with Google in a secure browser sheet, keeps the refresh token
/// in this phone's Keychain, and reads only free/busy times. The token never goes to the Kairos server.
@MainActor @Observable
final class GoogleCalendar: NSObject {
    /// From Info.plist GOOGLE_CLIENT_ID (Config/Secrets.xcconfig). Empty means the button is hidden.
    let clientID: String = {
        let v = (Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
        return v.hasSuffix(".apps.googleusercontent.com") ? v : ""
    }()

    private(set) var isConnected = GoogleCalendar.keychainRead() != nil
    private(set) var email: String? = UserDefaults.standard.string(forKey: GoogleCalendar.emailKey)
    private(set) var lastError: String?

    var isConfigured: Bool { !clientID.isEmpty }

    private var accessToken: String?
    private var accessExpires = Date.distantPast
    private var session: ASWebAuthenticationSession?

    private static let emailKey = "gh.google.email"
    private static let service = "kairos.google.refresh-token"
    private static let earlyRefresh: TimeInterval = 60

    // MARK: sign in / out

    /// Opens Google's sign-in sheet. Throws ASWebAuthenticationSessionError.canceledLogin if the user closes it.
    func connect() async throws {
        guard isConfigured else { throw GoogleOAuth.Failure.notSignedIn }
        let verifier = GoogleOAuth.makeVerifier()
        let state = UUID().uuidString
        let url = GoogleOAuth.authURL(clientID: clientID, verifier: verifier, state: state)
        let redirect = try await signInSheet(url: url, scheme: GoogleOAuth.redirectScheme(clientID: clientID))
        let code = try GoogleOAuth.code(fromRedirect: redirect, expectedState: state)
        let tokens = try await tokenRequest([
            ("client_id", clientID), ("code", code), ("code_verifier", verifier),
            ("grant_type", "authorization_code"), ("redirect_uri", GoogleOAuth.redirectURI(clientID: clientID)),
        ])
        guard let refresh = tokens.refreshToken else { throw GoogleOAuth.Failure.badReply }
        Self.keychainWrite(refresh)
        remember(tokens)
        email = GoogleOAuth.email(fromIDToken: tokens.idToken)
        UserDefaults.standard.set(email, forKey: Self.emailKey)
        isConnected = true
        lastError = nil
    }

    /// Forgets the token on this phone and asks Google to revoke it.
    func disconnect() async {
        if let token = Self.keychainRead() {
            var req = URLRequest(url: GoogleOAuth.revokeEndpoint)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = GoogleOAuth.formBody([("token", token)])
            _ = try? await URLSession.shared.data(for: req)   // best effort: the token is deleted below either way
        }
        Self.keychainDelete()
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
        accessToken = nil; accessExpires = .distantPast
        email = nil; isConnected = false; lastError = nil
    }

    // MARK: free/busy

    /// Busy times on the user's main Google calendar in `window`. Records the error for Settings and rethrows.
    func busyEvents(in window: DateInterval) async throws -> [CalendarEventInfo] {
        do {
            let token = try await validAccessToken()
            var req = URLRequest(url: GoogleOAuth.freeBusyEndpoint)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = GoogleOAuth.freeBusyBody(window: window)
            let (data, response) = try await URLSession.shared.data(for: req)
            if (response as? HTTPURLResponse)?.statusCode == 401 { accessToken = nil }
            let events = try GoogleOAuth.busyEvents(from: data)
            lastError = nil
            return events
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func validAccessToken() async throws -> String {
        if let t = accessToken, accessExpires > Date() { return t }
        guard let refresh = Self.keychainRead() else { throw GoogleOAuth.Failure.notSignedIn }
        do {
            let tokens = try await tokenRequest([("client_id", clientID), ("refresh_token", refresh), ("grant_type", "refresh_token")])
            remember(tokens)
            return tokens.accessToken
        } catch GoogleOAuth.Failure.denied(let why) {
            // The user revoked access in their Google account: show "Connect" again instead of failing forever.
            Self.keychainDelete()
            isConnected = false
            throw GoogleOAuth.Failure.denied(why)
        }
    }

    private func remember(_ t: GoogleOAuth.Tokens) {
        accessToken = t.accessToken
        accessExpires = Date().addingTimeInterval(t.expiresIn - Self.earlyRefresh)
    }

    private func tokenRequest(_ fields: [(String, String)]) async throws -> GoogleOAuth.Tokens {
        var req = URLRequest(url: GoogleOAuth.tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = GoogleOAuth.formBody(fields)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try GoogleOAuth.tokens(from: data)
    }

    private func signInSheet(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback { cont.resume(returning: callback) } else { cont.resume(throwing: error ?? GoogleOAuth.Failure.badReply) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false   // reuse the Google account already signed in on Safari
            session = s
            if !s.start() { cont.resume(throwing: GoogleOAuth.Failure.badReply) }
        }
    }

    // MARK: Keychain (this app only; the widget never needs Google)

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    private static func keychainRead() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainWrite(_ token: String) {
        keychainDelete()
        var q = query()
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    private static func keychainDelete() { SecItemDelete(query() as CFDictionary) }
}

extension GoogleCalendar: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}
