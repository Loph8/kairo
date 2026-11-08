import Testing
import Foundation
@testable import GoldenHourCore

@Suite struct AuthTests {
    @Test func normalizesEmails() {
        #expect(AuthClient.normalizedEmail("  Mom@Example.COM ") == "mom@example.com")
        #expect(AuthClient.normalizedEmail("mom@example") == nil)
        #expect(AuthClient.normalizedEmail("@example.com") == nil)
        #expect(AuthClient.normalizedEmail("a b@example.com") == nil)
        #expect(AuthClient.normalizedEmail("a@@example.com") == nil)
    }

    @Test func acceptsOnlyDigitCodes() {
        #expect(AuthClient.normalizedCode("123 456") == "123456")
        #expect(AuthClient.normalizedCode("12345") == nil)
        #expect(AuthClient.normalizedCode("12a456") == nil)
        #expect(AuthClient.normalizedCode("12345678") == "12345678")
    }

    @Test func decodesTokenResponse() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let auth = AuthClient(config: BackendConfig(baseURL: URL(string: "https://x.supabase.co")!, anonKey: "k"), now: { now })
        let json = #"{"access_token":"a","refresh_token":"r","expires_in":3600,"token_type":"bearer","user":{"id":"u1","email":"a@b.co"}}"#
        let s = try auth.decodeSession(Data(json.utf8))
        #expect(s == AuthSession(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(3600), userID: "u1", email: "a@b.co"))
        #expect(!s.needsRefresh(at: now))
        #expect(s.needsRefresh(at: now.addingTimeInterval(3550)))
    }

    @Test func friendlyErrors() {
        let bad = Data(#"{"code":403,"msg":"Token has expired or is invalid"}"#.utf8)
        #expect(AuthClient.message(bad, 403).hasPrefix("That code didn't work"))
        #expect(AuthError.server(status: 429, message: "x").errorDescription?.hasPrefix("Too many") == true)
    }

    final class MemoryStore: SessionStore, @unchecked Sendable {
        var value: AuthSession?
        init(_ v: AuthSession?) { value = v }
        func load() -> AuthSession? { value }
        func save(_ session: AuthSession?) { value = session }
    }

    @Test func tokenProviderReturnsFreshTokenWithoutNetwork() async throws {
        let s = AuthSession(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600), userID: "u", email: nil)
        let p = TokenProvider(auth: AuthClient(config: BackendConfig(baseURL: URL(string: "https://x.supabase.co")!, anonKey: "k")), store: MemoryStore(s))
        #expect(try await p.accessToken() == "a")
        await p.signOut()
        await #expect(throws: AuthError.signedOut) { try await p.accessToken() }
    }
}
