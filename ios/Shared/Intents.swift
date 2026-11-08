import AppIntents
import WidgetKit
import GoldenHourCore

enum GHIntentError: Error, CustomLocalizedStringResourceConvertible {
    case storageUnavailable, notSetUp, invalidID
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storageUnavailable: return "Kairos can't reach its shared data. Open the app."
        case .notSetUp: return "Open Kairos to finish setup."
        case .invalidID: return "That proposal isn't valid."
        }
    }
}

/// Runs in the widget extension process without opening the app. It uses the signed-in account
/// shared through the Keychain, so a tap on the widget is the same as a tap in the app.
enum IntentBackend {
    static func client() throws -> BackendClient {
        guard let client = AppBackend.client, AppBackend.isSignedIn else { throw GHIntentError.notSetUp }
        return client
    }

    /// Updates only the local "busy until" on the widget snapshot, so the widget reacts instantly.
    static func setBusyUntil(_ date: Date?) {
        guard case .loaded(var snap) = AppGroup.snapshotStore.load() else { return }
        snap.busyUntil = date
        try? AppGroup.snapshotStore.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct BookProposalIntent: AppIntent {
    static var title: LocalizedStringResource = "Join this time"
    static var description = IntentDescription("Says you'll be there. The call is booked once everyone has joined.")
    static var openAppWhenRun = false

    @Parameter(title: "Proposal ID") var proposalID: String
    init() {}
    init(proposalID: String) { self.proposalID = proposalID }

    func perform() async throws -> some IntentResult {
        guard DeepLink.validID(proposalID), let start = FamilyProposalID.start(of: proposalID) else {
            throw GHIntentError.invalidID
        }
        AppBackend.publish(try await IntentBackend.client().join(start: start))
        // A Live Activity can't start from a widget process; the app starts it next time it opens.
        return .result()
    }
}

struct BusyIntent: AppIntent {
    static var title: LocalizedStringResource = "I'm busy"
    static var description = IntentDescription("Tells your family you're busy right now. Kairos learns from it.")
    static var openAppWhenRun = false

    @Parameter(title: "Minutes", default: 60) var minutes: Int
    init() {}
    init(minutes: Int) { self.minutes = minutes }

    func perform() async throws -> some IntentResult {
        let client = try IntentBackend.client()
        IntentBackend.setBusyUntil(Date().addingTimeInterval(TimeInterval(max(15, min(minutes, 720)) * 60)))
        AppBackend.publish(try await client.logLabel(free: false))
        return .result()
    }
}

struct ClearBusyIntent: AppIntent {
    static var title: LocalizedStringResource = "I'm free"
    static var description = IntentDescription("Tells your family you're free to talk now.")
    static var openAppWhenRun = false
    init() {}
    func perform() async throws -> some IntentResult {
        let client = try IntentBackend.client()
        IntentBackend.setBusyUntil(nil)
        AppBackend.publish(try await client.logLabel(free: true))
        return .result()
    }
}

/// For the Shortcuts automation "When I get a message from Mom → Family texted me".
/// Only the time is sent, never the message.
struct LogTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Family texted me"
    static var description = IntentDescription("Records that this person just texted you, so Kairos learns when they're awake. The message itself is never read or sent.")
    static var openAppWhenRun = false

    @Parameter(title: "Who texted") var member: MemberEntity
    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppBackend.publish(try await IntentBackend.client().logTextArrived(from: member.id))
        return .result(dialog: "Got it. Kairos noted the time, not the message.")
    }
}

/// For a Shortcuts automation after a phone call: "Did they pick up?" in one tap.
struct LogCallIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a family call"
    static var description = IntentDescription("Records whether this person picked up. Only the time and the answer are sent.")
    static var openAppWhenRun = false

    @Parameter(title: "Who") var member: MemberEntity
    @Parameter(title: "Picked up", default: true) var answered: Bool
    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppBackend.publish(try await IntentBackend.client().logCall(answered: answered, for: member.id))
        return .result(dialog: answered ? "Nice. Logged that \(member.name) picked up." : "Logged a missed call with \(member.name).")
    }
}

// MARK: - Widget configuration (choose the family member for the small widget)

struct MemberEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Family member"
    static var defaultQuery = MemberQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct MemberQuery: EntityQuery {
    private func all() -> [MemberEntity] {
        guard case .loaded(let s) = AppGroup.snapshotStore.load() else { return [] }
        return s.people.map { MemberEntity(id: $0.id, name: $0.name) }
    }
    func entities(for identifiers: [String]) async throws -> [MemberEntity] { all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [MemberEntity] { all() }
    func defaultResult() async -> MemberEntity? { all().first }
}

struct SelectMemberIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Family member"
    static var description = IntentDescription("Choose who this widget focuses on.")
    @Parameter(title: "Member") var member: MemberEntity?
    init() {}
}
