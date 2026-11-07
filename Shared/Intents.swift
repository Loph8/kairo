import AppIntents
import WidgetKit
import GoldenHourCore

enum GHIntentError: Error, CustomLocalizedStringResourceConvertible {
    case storageUnavailable, notSetUp, invalidID
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .storageUnavailable: return "Golden Hour can't reach its shared data. Open the app."
        case .notSetUp: return "Open Golden Hour to finish setup."
        case .invalidID: return "That proposal isn't valid."
        }
    }
}

/// Runs in the widget extension process without opening the app. Writes go through the same
/// locked repository as the app, so repeated taps and concurrent confirmations are idempotent.
struct BookProposalIntent: AppIntent {
    static var title: LocalizedStringResource = "Book this time"
    static var description = IntentDescription("Confirms YOUR side of a proposed call. The other person must confirm separately.")
    static var openAppWhenRun = false

    @Parameter(title: "Proposal ID") var proposalID: String
    init() {}
    init(proposalID: String) { self.proposalID = proposalID }

    func perform() async throws -> some IntentResult {
        guard DeepLink.validID(proposalID) else { throw GHIntentError.invalidID }
        guard let repo = AppGroup.sharedRepository() else { throw GHIntentError.storageUnavailable }
        let state = await repo.loadState()
        guard !state.viewerID.isEmpty else { throw GHIntentError.notSetUp }
        _ = try await repo.confirm(proposalID: proposalID, as: state.viewerID)
        WidgetCenter.shared.reloadAllTimelines()
        // A Live Activity cannot be requested from here (app not foreground). The repository sets
        // pendingLiveActivityProposalID; the app starts it on next foreground. See LiveActivityManager.
        return .result()
    }
}

struct BusyIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Busy"
    static var description = IntentDescription("Marks you as busy for a while. Overrides any estimate.")
    static var openAppWhenRun = false

    @Parameter(title: "Minutes", default: 60) var minutes: Int
    init() {}
    init(minutes: Int) { self.minutes = minutes }

    func perform() async throws -> some IntentResult {
        guard let repo = AppGroup.sharedRepository() else { throw GHIntentError.storageUnavailable }
        let state = await repo.loadState()
        guard !state.viewerID.isEmpty else { throw GHIntentError.notSetUp }
        try await repo.setBusy(personID: state.viewerID, minutes: minutes, replaceExisting: false)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct ClearBusyIntent: AppIntent {
    static var title: LocalizedStringResource = "Clear Busy"
    static var openAppWhenRun = false
    init() {}
    func perform() async throws -> some IntentResult {
        guard let repo = AppGroup.sharedRepository() else { throw GHIntentError.storageUnavailable }
        let state = await repo.loadState()
        guard !state.viewerID.isEmpty else { throw GHIntentError.notSetUp }
        try await repo.clearBusy(personID: state.viewerID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
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
        return s.people.map { MemberEntity(id: $0.id, name: $0.relationship) }
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
