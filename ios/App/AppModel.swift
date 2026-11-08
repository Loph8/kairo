import Foundation
import Observation
import UIKit
import WidgetKit
import GoldenHourCore

enum AppTab: Hashable { case family, insights, settings }

/// Where the app is in its life: sign in, then make or join a family, then the main tabs.
enum AppPhase: Equatable { case loading, signedOut, needsFamily, ready }

/// App state for the signed-in account. All family data comes from the server, scoped to this account.
@MainActor
@Observable
final class AppModel {
    var phase: AppPhase = .loading
    var account: Account?
    var serverState: ServerState?
    var server: WidgetSnapshot?
    var banner: String?
    var working = false
    var tab: AppTab = .family
    var insightsMemberID: String?
    /// The person whose FaceTime call we just opened; when the user comes back we ask whether they picked up.
    var callingMemberID: String?
    private let callDetector = CallDetector()
    /// Set once we've really left for the call app, so dismissing iOS's "Call?" alert doesn't count as coming back.
    private var leftForCall = false
    var askPickedUp: ServerState.Member?
    /// Bumps when the AI changes someone's map, so views can animate the change.
    var changeTick = 0

    let calendar = CalendarSync()
    let contacts = ContactsLink()
    let liveActivities = LiveActivityManager()
    var configured: Bool { AppBackend.client != nil }

    // MARK: lifecycle

    func reload() async {
        guard let client = AppBackend.client else { phase = .signedOut; return }
        guard AppBackend.isSignedIn else { phase = .signedOut; return }
        calendar.observeChanges { [weak self] in Task { await self?.pushCalendar() } }
        do {
            var fresh = try await client.me()
            if fresh.account != nil, let pushed = try await calendar.push(with: client) { fresh = pushed }
            apply(fresh)
        } catch {
            fail(error)
        }
    }

    func apply(_ result: ServerResult) {
        let before = serverState?.lastChange
        account = result.account
        serverState = result.state
        phase = result.account == nil ? .needsFamily : .ready
        server = AppBackend.publish(result)
        if let s = result.state, let me = account?.memberId {
            contacts.refresh(members: s.members, me: me)
            if s.lastChange != nil, s.lastChange != before { changeTick += 1 }
            Task { await syncLiveActivity() }
        }
    }

    func fail(_ error: Error) {
        if (error as? AuthError) == .signedOut || (error as? BackendError)?.isSignedOut == true {
            Task { await signOut() }
            return
        }
        banner = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach Kairos. Check your connection."
    }

    /// Runs one server call with a spinner and friendly errors.
    func run(_ work: (BackendClient) async throws -> ServerResult) async {
        guard let client = AppBackend.client else { banner = "Kairos isn't set up on this build."; return }
        working = true
        defer { working = false }
        do { apply(try await work(client)); banner = nil } catch { fail(error) }
    }

    // MARK: account

    func sendCode(to email: String) async throws {
        guard let auth = AppBackend.auth else { throw AuthError.signedOut }
        try await auth.sendCode(to: email)
    }

    func verify(email: String, code: String) async throws {
        guard let auth = AppBackend.auth else { throw AuthError.signedOut }
        let session = try await auth.verify(email: email, code: code)
        await AppBackend.signIn(session)
        await reload()
    }

    /// Simulator only: skips sign-in and uses the in-memory demo server on this Mac.
    func startLocalDemo() async {
        AppBackend.setLocalDemo(true)
        phase = .loading
        await reload()
        if phase == .signedOut || account == nil {
            AppBackend.setLocalDemo(false)
            phase = .signedOut
            banner = "Start the demo server first: bun scripts/local_demo_server.ts"
        }
    }

    func signOut() async {
        await AppBackend.signOut()
        await liveActivities.endAll()
        account = nil; serverState = nil; server = nil; banner = nil
        phase = .signedOut
        tab = .family
    }

    func createFamily(name: String, profile: Profile) async { await run { try await $0.createFamily(name: name, profile: profile) } }
    func joinFamily(code: String, profile: Profile) async { await run { try await $0.joinFamily(code: code, profile: profile) } }
    func addDemoFamily() async { await run { try await $0.addDemoFamily() } }
    func resetFamily() async { await run { try await $0.resetFamily() } }
    /// Opens another of your families. The widget follows, because it reads the same saved choice.
    func switchFamily(_ id: String) async {
        guard id != account?.familyId else { return }
        AppBackend.selectFamily(id)
        await liveActivities.endAll()
        await run { try await $0.state(familyID: id) }
    }

    func leaveFamily() async {
        await run { try await $0.leaveFamily() }
        guard account == nil else { return }
        await liveActivities.endAll()
        tab = .family
    }
    /// Saves your number and connected apps on every family you're in.
    func setContact(phone: String?, apps: [String: String]) async {
        await run { try await $0.setContact(phone: phone, apps: apps) }
    }

    /// Saves the family's shared group-call link (nil removes it). Everyone in the family sees the change.
    func setCallLink(_ link: String?) async { await run { try await $0.setCallLink(link) } }
    func simulate(_ event: SimulatedEvent, for memberID: String) async { await run { try await $0.simulate(event, for: memberID) } }
    func join(_ start: Date) async { await run { try await $0.join(start: start) } }
    func markBusy() async { await run { try await $0.logLabel(free: false) } }
    func markFree() async { await run { try await $0.logLabel(free: true) } }

    // MARK: family helpers

    var myMemberID: String { account?.memberId ?? "" }
    var members: [ServerState.Member] { serverState?.members ?? [] }
    var me: ServerState.Member? { members.first { $0.id == myMemberID } }
    var others: [ServerState.Member] { members.filter { $0.id != myMemberID } }
    /// Kept for ContactViews.
    var liveOthers: [ServerState.Member] { others }
    func member(_ id: String) -> ServerState.Member? { members.first { $0.id == id } }
    /// The server's clock, so demo state and countdowns agree with what the server computed.
    func serverNow(_ date: Date = Date()) -> Date {
        guard let s = server else { return date }
        return date.addingTimeInterval(s.clockOffset)
    }
    var myBooking: ServerState.Booking? {
        serverState?.bookings.first { $0.status == "booked" && $0.acceptedBy.contains(myMemberID) && $0.end > serverNow() }
    }

    // MARK: calendar + contacts

    func connectCalendar() async {
        guard await calendar.requestAccess() else {
            banner = "Calendar access is off. Turn it on in Settings → Kairos → Calendars, then come back."
            return
        }
        await pushCalendar()
    }

    func pushCalendar() async {
        guard let client = AppBackend.client, account != nil else { return }
        do { if let r = try await calendar.push(with: client) { apply(r) } } catch { fail(error) }
    }

    func approveMove(_ move: ServerState.Move) async {
        do { try calendar.move(blockID: move.blockId, to: move.to) } catch {
            banner = "Couldn't move that event. It may have been changed or deleted."
            return
        }
        await run { client in
            _ = try await self.calendar.push(with: client)
            return try await client.join(start: move.frees)
        }
    }

    func connectContacts() async {
        guard await contacts.requestAccess() else {
            banner = "Contacts access is off. Turn it on in Settings → Kairos → Contacts."
            return
        }
        contacts.refresh(members: members, me: myMemberID)
    }

    // MARK: calls

    /// Opens a FaceTime audio call to this person's linked contact. Returns false if there's nothing to call.
    /// Which app each family member is called on (this phone only).
    var callChoices: [String: CallChoice] = CallChoices.all()

    func callChoice(for m: ServerState.Member) -> CallChoice? { callChoices[m.id] }

    func setCallChoice(_ choice: CallChoice?, for m: ServerState.Member) {
        CallChoices.save(choice, for: m.id)
        callChoices = CallChoices.all()
    }

    /// Opens the member's chosen call app (or FaceTime Audio to their linked contact).
    /// Returns false when there's nothing to call yet, so the UI can ask which app to use.
    func call(_ m: ServerState.Member) -> Bool {
        let linked = contacts.linked[m.id]
        // Their number from sign-up comes first, so nobody has to type it in.
        let number = m.phone ?? linked?.phone
        let url: URL?
        if let choice = callChoices[m.id] {
            let handle = choice.handle ?? m.apps?[choice.app.rawValue] ?? number ?? linked?.email
            url = choice.app.url(handle: handle)
        } else if let number {
            url = CallApp.facetimeAudio.url(handle: number)
        } else {
            url = linked?.callURL
        }
        guard let url else { return false }
        callingMemberID = m.id   // when we come back: did it connect?
        leftForCall = false
        callDetector.start()
        let appName = callChoices[m.id]?.app.name ?? "FaceTime"
        UIApplication.shared.open(url) { [weak self] opened in
            guard !opened, let self else { return }
            self.callingMemberID = nil
            #if targetEnvironment(simulator)
            self.banner = "Calls need a real iPhone. The simulator has no FaceTime or Phone app."
            #else
            self.banner = "Couldn't open \(appName) to call \(m.name). Touch and hold the call button to pick another app."
            #endif
        }
        return true
    }

    /// Opens the family's shared group-call link, so everyone can join the same call at once.
    /// Returns false when the family has no link yet, so the UI can ask for one.
    func groupCall() -> Bool {
        guard let raw = account?.callLink, let url = URL(string: raw) else { return false }
        if account?.groupCall == nil {   // first one in: tell the family so their app shows "Join"
            Task { [weak self] in await self?.run { try await $0.startGroupCall() } }
        }
        UIApplication.shared.open(url) { [weak self] opened in
            guard !opened, let self else { return }
            self.banner = "Couldn't open the group call link. Check it under Call → Group call link."
        }
        return true
    }

    /// The one "best time" every screen shows: the booked call if there is one, else the agent's suggestion.
    func bestCallTime(_ state: ServerState, now: Date) -> Date? {
        if let b = myBooking ?? state.bookings.first(where: { $0.end > now }) { return b.start }
        return state.suggestion?.start
    }

    func enteredBackground() {
        if callingMemberID != nil { leftForCall = true }
    }

    /// Back from the call app. If iOS saw the call connect (or end unanswered), log it with no question.
    /// Otherwise fall back to asking "Did they pick up?".
    func returnedToApp() {
        guard leftForCall, let id = callingMemberID, let m = member(id) else { return }
        callingMemberID = nil
        leftForCall = false
        switch callDetector.finish() {
        case .connected:
            Task { await reportCall(id, answered: true) }
            banner = "\(m.name) picked up. Kairos learned from it."
        case .notConnected:
            Task { await reportCall(id, answered: false) }
            banner = "\(m.name) didn't pick up. Kairos will suggest a better time."
        case .unknown:
            askPickedUp = m
        }
    }

    func reportCall(_ memberID: String, answered: Bool) async {
        await run { try await $0.logCall(answered: answered, for: memberID) }
    }

    // MARK: deep links + live activity

    func handle(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .dashboard, .schedule, .proposal: tab = .family
        case .member(let id): insightsMemberID = id; tab = .insights
        case .call(let id): if let m = member(id), !call(m) { tab = .family }
        }
    }

    func syncLiveActivity() async {
        guard let s = serverState else { return }
        if let msg = await liveActivities.sync(state: s, viewerID: myMemberID, clockOffset: server?.clockOffset ?? 0) {
            banner = msg
        }
        await Reminders.schedule(for: myBooking, state: s, viewerID: myMemberID, clockOffset: server?.clockOffset ?? 0)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
