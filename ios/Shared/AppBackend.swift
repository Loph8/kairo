import Foundation
import WidgetKit
import GoldenHourCore

/// One wiring point for the family server, shared by the app, the widget and App Intents.
/// Signing in stores a session in the shared Keychain; every request carries that user's token,
/// and the server answers only with that user's family.
enum AppBackend {
    static let config = BackendConfig(info: Bundle.main.infoDictionary)
    static let sessions = KeychainSessionStore(accessGroup: AppGroup.identifier)
    static let auth: AuthClient? = config.map { AuthClient(config: $0) }
    static let tokens: TokenProvider? = auth.map { TokenProvider(auth: $0, store: sessions) }
    private static let remoteClient: BackendClient? = {
        guard let config, let tokens else { return nil }
        return BackendClient(config: config, token: { try await tokens.accessToken() },
                             familyID: { selectedFamilyID })
    }()

    /// Simulator-only "Try the demo": talks to `bun scripts/local_demo_server.ts` on this Mac, no sign-in.
    static let localDemoURL = URL(string: "http://127.0.0.1:8787")!
    private static let localClient = BackendClient(
        config: BackendConfig(baseURL: localDemoURL, anonKey: "local-demo"), token: { "local-demo" },
        familyID: { selectedFamilyID })
    private static let localDemoKey = "gh.localDemo"

    static var isLocalDemo: Bool {
        #if targetEnvironment(simulator)
        defaults.bool(forKey: localDemoKey)
        #else
        false
        #endif
    }

    static func setLocalDemo(_ on: Bool) {
        defaults.set(on, forKey: localDemoKey)
        if !on { defaults.removeObject(forKey: viewerKey) }
    }

    static var client: BackendClient? { isLocalDemo ? localClient : remoteClient }

    private static let defaults = UserDefaults(suiteName: AppGroup.identifier) ?? .standard
    private static let viewerKey = "gh.memberID"
    private static let familyKey = "gh.familyID"

    /// The family the app and widget are showing, for accounts in more than one family.
    static var selectedFamilyID: String? {
        (UserDefaults(suiteName: AppGroup.identifier) ?? .standard).string(forKey: familyKey)
    }

    static func selectFamily(_ id: String?) {
        if let id { defaults.set(id, forKey: familyKey) } else { defaults.removeObject(forKey: familyKey) }
    }

    static var isSignedIn: Bool { isLocalDemo || sessions.load() != nil }
    static var signedInEmail: String? { isLocalDemo ? "Demo (no sign-in)" : sessions.load()?.email }

    /// This account's member id in its family, remembered so the widget can draw before the network answers.
    static var viewerID: String? { defaults.string(forKey: viewerKey) }

    static func signIn(_ session: AuthSession) async {
        await tokens?.signIn(session)
    }

    static func signOut() async {
        setLocalDemo(false)
        await tokens?.signOut()
        defaults.removeObject(forKey: viewerKey)
        defaults.removeObject(forKey: familyKey)
        try? AppGroup.snapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Saves what the widget should show for this account. Returns nil until the account has a family.
    @discardableResult
    static func publish(_ result: ServerResult, focusPersonID: String? = nil) -> WidgetSnapshot? {
        guard let account = result.account, let state = result.state else {
            defaults.removeObject(forKey: viewerKey)
            if result.account == nil { defaults.removeObject(forKey: familyKey) }
            return nil
        }
        defaults.set(account.memberId, forKey: viewerKey)
        selectFamily(account.familyId)
        var snap = ServerSnapshot.make(state, viewerID: account.memberId, focusPersonID: focusPersonID)
        if case .loaded(let old) = AppGroup.snapshotStore.load() { snap.busyUntil = old.busyUntil }
        try? AppGroup.snapshotStore.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
        return snap
    }

    /// Fetches the latest family state and republishes it. nil when signed out or not configured.
    @discardableResult
    static func refresh(focusPersonID: String? = nil) async throws -> ServerResult? {
        guard let client, isSignedIn else { return nil }
        let result = try await client.state()
        publish(result, focusPersonID: focusPersonID)
        return result
    }
}
