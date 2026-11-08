import Foundation
import Security
import GoldenHourCore

/// Keeps the sign-in session in the Keychain, shared with the widget through the App Group
/// (an App Group name is a valid Keychain access group). If the group entitlement is missing,
/// for example on a free signing team that refused the App Group, it falls back to an app-only item.
struct KeychainSessionStore: SessionStore {
    private static let service = "golden-hour.session"
    private static let account = "default"
    let accessGroup: String

    func load() -> AuthSession? {
        for group in [accessGroup, nil] as [String?] {
            var q = query(group)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data {
                return try? JSONDecoder().decode(AuthSession.self, from: data)
            }
        }
        return nil
    }

    func save(_ session: AuthSession?) {
        for group in [accessGroup, nil] as [String?] { SecItemDelete(query(group) as CFDictionary) }
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var add = query(accessGroup)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) == errSecMissingEntitlement {
            add = query(nil)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func query(_ group: String?) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        if let group { q[kSecAttrAccessGroup as String] = group }
        return q
    }
}
