import Foundation
import GoldenHourCore

/// Shared-container access. The identifier comes from Info.plist GH_APP_GROUP, which project.yml sets to
/// group.$(BUNDLE_ID_BASE), the same value as the App Group entitlement on BOTH the app and the widget.
enum AppGroup {
    static let identifier: String = {
        let v = Bundle.main.object(forInfoDictionaryKey: "GH_APP_GROUP") as? String ?? ""
        return v.hasPrefix("group.") && !v.contains("$(") ? v : "group.com.example.goldenhour"
    }()

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
            .appendingPathComponent("GoldenHour", isDirectory: true)
        return (LocalDemoRepository(directory: dir), false)
    }
}
