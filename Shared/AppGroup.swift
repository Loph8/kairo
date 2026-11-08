import Foundation
import KairoCore

/// Shared-container access. The identifier MUST match the App Group capability on BOTH the app and
/// widget targets (see Config/*.entitlements). Replace the placeholder with your own team's group id.
enum AppGroup {
    static let identifier = "group.com.example.kairo"

    /// nil when the App Group container is unreachable (misconfigured entitlement, etc.).
    static func container() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var snapshotStore: SnapshotStore { SnapshotStore(directory: container()) }

    /// Used by widget extension and App Intents. Never falls back to a private directory,
    /// because the app could not see it.
    static func sharedRepository() -> LocalDemoRepository? {
        container().map { LocalDemoRepository(directory: $0) }
    }

    /// App only. Falls back to Application Support so the app still works; widgets then show
    /// an honest "shared data unavailable" state.
    static func appRepository() -> (repo: LocalDemoRepository, usingAppGroup: Bool) {
        if let c = container() { return (LocalDemoRepository(directory: c), true) }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kairo", isDirectory: true)
        return (LocalDemoRepository(directory: dir), false)
    }
}
