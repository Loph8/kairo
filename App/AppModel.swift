import SwiftUI
import WidgetKit
import KairoCore

enum AppTab: Hashable { case family, schedule, settings }

/// Single source of UI state. All mutations go through the repository, then reload, so the app,
/// the widget snapshot and Live Activity always derive from the same persisted state.
@MainActor @Observable
final class AppModel {
    let repo: LocalDemoRepository
    let usingAppGroup: Bool
    let liveActivities = LiveActivityManager()

    var state = AppState()
    var windows: [RankedWindow] = []
    var banner: String?
    var tab: AppTab = .family
    var path: [DeepLink] = []
    var callPersonID: String?               // presents the call flow sheet
    var callingProposalID: String?
    var leftForFaceTime = false             // set when the user hands off to FaceTime
    var feedbackProposalID: String?         // drives the "Did you connect?" prompt
    var liveActivityNote: String?
    var loaded = false

    init() {
        let r = AppGroup.appRepository()
        repo = r.repo; usingAppGroup = r.usingAppGroup
    }

    // MARK: time
    func effectiveNow(_ real: Date = Date()) -> Date { real.addingTimeInterval(state.clockOffset) }
    var viewer: Person? { state.viewer }
    var others: [Person] { state.people.filter { $0.id != state.viewerID } }

    func reload() async {
        state = await repo.loadState()
        windows = repo.windows()
        if !usingAppGroup {
            banner = "Shared data is unavailable (App Group not configured). The app works, but widgets can't show your data."
        }
        loaded = true
        WidgetCenter.shared.reloadAllTimelines()
        await syncLiveActivity()
    }

    func perform(_ work: () async throws -> Void) async {
        do { try await work() } catch { banner = "Couldn't save that change. \(error.localizedDescription)" }
        await reload()
    }

    // MARK: booking
    func confirm(_ id: String) async {
        guard let me = state.viewerID.nonEmpty else { return }
        await perform {
            let out = try await repo.confirm(proposalID: id, as: me)
            switch out.result {
            case .rejected(let r): banner = rejectionText(r)
            case .applied, .unchanged: banner = nil
            }
            if out.becameConfirmed { await NotificationScheduler.requestIfNeeded(model: self) }
        }
    }
    func decline(_ id: String) async { if let me = state.viewerID.nonEmpty { await perform { _ = try await repo.decline(proposalID: id, as: me) } } }
    func cancel(_ id: String) async { if let me = state.viewerID.nonEmpty { await perform { _ = try await repo.cancel(proposalID: id, as: me) } } }
    func reschedule(_ id: String) async { if let me = state.viewerID.nonEmpty { await perform { try await repo.reschedule(proposalID: id, as: me) } } }

    func rejectionText(_ r: RejectReason) -> String {
        switch r {
        case .expired: return "That time has passed or the proposal expired. Pick a fresh suggestion."
        case .availabilityChanged: return "Availability changed since this was suggested. We marked it stale; pick a new time."
        case .alreadyDecided: return "That proposal was already decided."
        case .notParticipant, .agentCannotConsent: return "Only participants can confirm."
        case .notFound: return "That proposal no longer exists."
        case .notConfirmed, .notEnded: return "That isn't possible yet."
        }
    }

    // MARK: busy
    var myBusy: BusyOverride? { state.overrides.first { $0.personID == state.viewerID && $0.isActive(at: effectiveNow()) } }
    func setBusy(minutes: Int = 60, replace: Bool = false) async {
        guard let me = state.viewerID.nonEmpty else { return }
        await perform { try await repo.setBusy(personID: me, minutes: minutes, replaceExisting: replace) }
    }
    func clearBusy() async { if let me = state.viewerID.nonEmpty { await perform { try await repo.clearBusy(personID: me) } } }

    // MARK: calling
    /// FaceTime audio only if the user configured a destination. Never invents a number.
    func callURL() -> URL? {
        guard let d = state.settings.callDestination?.trimmingCharacters(in: .whitespaces), !d.isEmpty,
              let enc = d.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) else { return nil }
        return URL(string: "facetime-audio://\(enc)")
    }

    func openCall(personID: String, proposalID: String?) {
        callPersonID = personID; callingProposalID = proposalID; feedbackProposalID = nil
    }
    /// Feedback is self-reported. We cannot observe whether a FaceTime call connected or how long it lasted.
    func callEnded() {
        if let id = callingProposalID { feedbackProposalID = id }
        callPersonID = nil; callingProposalID = nil
    }

    func submitFeedback(_ c: FeedbackChoice) async {
        guard let id = feedbackProposalID else { return }
        feedbackProposalID = nil
        await perform { try await repo.submitFeedback(proposalID: id, choice: c) }
    }

    // MARK: deep links (validated in KairoCore.DeepLink)
    func handle(_ url: URL) {
        guard let link = DeepLink(url: url) else { banner = "That link isn't valid."; return }
        switch link {
        case .dashboard: tab = .family; path = []
        case .schedule: tab = .schedule
        case .member(let id): if state.person(id) != nil { tab = .family; path = [link] }
        case .proposal(let id): if state.proposals.contains(where: { $0.id == id }) { tab = .schedule }
        case .call(let id):
            let pid = state.proposals.filter { $0.status == .confirmed && $0.participants.contains(id) }.sorted { $0.start < $1.start }.first?.id
            if state.person(id) != nil { openCall(personID: id, proposalID: pid) }
        }
    }

    // MARK: Live Activity
    func syncLiveActivity() async {
        let now = effectiveNow()
        liveActivityNote = await liveActivities.sync(state: state, now: now, clockOffset: state.clockOffset)
        if state.pendingLiveActivityProposalID != nil, liveActivityNote != nil { /* keep pending until started */ }
    }
}

extension String { var nonEmpty: String? { isEmpty ? nil : self } }
