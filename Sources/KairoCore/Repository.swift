import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Time source (injected so demos and tests are repeatable)

public protocol TimeSource: Sendable { var now: Date { get } }
public struct SystemTimeSource: TimeSource { public init() {}; public var now: Date { Date() } }
public struct FixedTimeSource: TimeSource {
    public var now: Date
    public init(_ now: Date) { self.now = now }
}

public enum RepositoryError: Error, Sendable { case storageUnavailable, notConfigured, invalid(String) }

// MARK: - Persisted state

public struct AppSettings: Codable, Sendable {
    public var use24Hour = false
    public var learningPaused = false
    public var simulateOffline = false
    public var pendingSyncCount = 0
    public var onboardingComplete = false
    /// User-configured FaceTime audio destination (phone/email). Never invented by the app.
    public var callDestination: String?
    public var focusIntegrationEnabled = false
    public var notificationsEnabled = false
    public var proposalLifetimeHours = 24
    public init() {}
}

public struct AppState: Codable, Sendable {
    public var schemaVersion = 1
    public var viewerID = ""
    public var focusPersonID = ""
    public var people: [Person] = []
    public var events: [ActivityEvent] = []
    public var overrides: [BusyOverride] = []
    public var proposals: [Proposal] = []
    public var burdens: [Burden] = []
    public var log: [LogEntry] = []
    public var settings = AppSettings()
    public var clockOffset: TimeInterval = 0
    public var isDemo = false
    /// Set when a booking is confirmed from a context that cannot start a Live Activity
    /// (e.g. a widget button). The app starts it when next foregrounded.
    public var pendingLiveActivityProposalID: String?
    public init() {}

    public func person(_ id: String) -> Person? { people.first { $0.id == id } }
    public var viewer: Person? { person(viewerID) }
    public var focus: Person? { person(focusPersonID) }
}

public struct ConfirmOutcome: Sendable {
    public var result: TransitionResult
    public var proposal: Proposal?
    public var becameConfirmed: Bool
}

// MARK: - Repository abstraction

public protocol FamilyRepository: Sendable {
    func loadState() async -> AppState
    func now() async -> Date
    func refresh() async throws
    func completeOnboarding(profile: Person, useDemoFamily: Bool) async throws
    func confirm(proposalID: String, as personID: String) async throws -> ConfirmOutcome
    func decline(proposalID: String, as personID: String) async throws -> TransitionResult
    func cancel(proposalID: String, as personID: String) async throws -> TransitionResult
    func reschedule(proposalID: String, as personID: String) async throws
    @discardableResult func setBusy(personID: String, minutes: Int, replaceExisting: Bool) async throws -> BusyOverride
    func clearBusy(personID: String) async throws
    func submitFeedback(proposalID: String, choice: FeedbackChoice) async throws
}

// MARK: - Local demo implementation

/// Fully functional, backend-free repository. State and widget snapshot are written to a shared
/// directory (the App Group container in the app). Cross-process safe via `flock`; every mutation is
/// read-modify-write under the lock, so concurrent confirmations from the app and a widget intent
/// serialize instead of overwriting each other.
public final class LocalDemoRepository: FamilyRepository, @unchecked Sendable {
    public let directory: URL
    let clock: TimeSource
    public let engine: SchedulingEngine
    public let snapshotStore: SnapshotStore
    private static let mutex = NSLock()
    private var stateURL: URL { directory.appendingPathComponent("state.json") }
    private var lockURL: URL { directory.appendingPathComponent("state.lock") }

    public init(directory: URL, clock: TimeSource = SystemTimeSource(), engine: SchedulingEngine = .init()) {
        self.directory = directory; self.clock = clock; self.engine = engine
        self.snapshotStore = SnapshotStore(directory: directory)
    }

    // MARK: locking & persistence

    private func locked<T>(_ body: () throws -> T) throws -> T {
        Self.mutex.lock(); defer { Self.mutex.unlock() }
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { throw RepositoryError.storageUnavailable }
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw RepositoryError.storageUnavailable }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN); close(fd) }
        return try body()
    }

    private func readState() -> AppState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return AppState() }
        guard let data = try? Data(contentsOf: stateURL),
              let s = try? Codec.decoder().decode(AppState.self, from: data) else {
            // Corrupted: keep the bad file for inspection and start empty instead of crashing.
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("state.corrupt.json"))
            try? FileManager.default.moveItem(at: stateURL, to: directory.appendingPathComponent("state.corrupt.json"))
            return AppState()
        }
        return s
    }

    private func write(_ s: AppState) throws {
        try Codec.encoder().encode(s).write(to: stateURL, options: .atomic)
    }

    private func effectiveNow(_ s: AppState) -> Date { clock.now.addingTimeInterval(s.clockOffset) }

    /// Locked read-modify-write. Always normalizes, persists, and refreshes the widget snapshot.
    @discardableResult
    private func mutate<T>(_ body: (inout AppState, Date) throws -> T) throws -> T {
        try locked {
            var s = readState()
            let now = effectiveNow(s)
            normalize(&s, now: now)
            let r = try body(&s, now)
            if s.log.count > 100 { s.log.removeFirst(s.log.count - 100) }
            try write(s)
            try? snapshotStore.save(makeSnapshot(s, now: now))
            return r
        }
    }

    private func readOnly<T>(_ body: (AppState, Date) -> T) -> T? {
        try? locked {
            var s = readState()
            let now = effectiveNow(s)
            normalize(&s, now: now)
            return body(s, now)
        }
    }

    private func touch(_ s: inout AppState) { if s.settings.simulateOffline { s.settings.pendingSyncCount += 1 } }
    private func log(_ s: inout AppState, _ now: Date, _ kind: LogEntry.Kind, _ text: String) {
        s.log.append(LogEntry(at: now, kind: kind, text: text))
    }

    private func normalize(_ s: inout AppState, now: Date) {
        for i in s.proposals.indices {
            let n = BookingStateMachine.normalized(s.proposals[i], now: now)
            if n.version != s.proposals[i].version {
                log(&s, now, .outcome, "Proposal \(n.id) is now \(n.status.rawValue).")
                s.proposals[i] = n
            }
        }
        s.overrides.removeAll { $0.end < now.addingTimeInterval(-86_400) }
    }

    // MARK: derived data

    public func models(_ s: AppState, now: Date) -> [String: SlotModel] {
        Dictionary(uniqueKeysWithValues: s.people.map {
            ($0.id, engine.scorer.buildModel(person: $0, events: s.events, now: now)) })
    }

    func bookings(_ s: AppState, excluding id: String? = nil) -> [BookedInterval] {
        s.proposals.filter { $0.status == .confirmed && $0.id != id }
            .map { BookedInterval(personIDs: $0.participants, interval: $0.interval) }
    }

    /// Ranked windows for the viewer and focus person.
    public func rankedWindows(_ s: AppState, now: Date) -> [RankedWindow] {
        guard let v = s.viewer, let f = s.focus, v.id != f.id else { return [] }
        let dur = max(15, v.prefs.preferredCallMinutes)
        return engine.rank(participants: [v, f], models: models(s, now: now), overrides: s.overrides,
                           bookings: bookings(s), burdens: s.burdens, now: now, durationMinutes: dur)
    }

    private func refreshProposals(_ s: inout AppState, now: Date) {
        guard let v = s.viewer, let f = s.focus, v.id != f.id else { return }
        let top = rankedWindows(s, now: now)
        log(&s, now, .tool, "rank_candidate_windows(\(v.id), \(f.id)) → \(top.count) windows")
        let pair = [v.id, f.id].sorted()
        let keep = Set(top.map(\.id))
        // Expire unconfirmed suggestions that fell out of the top set (availability changed).
        for i in s.proposals.indices where s.proposals[i].participants == pair
            && s.proposals[i].status == .suggested && !keep.contains(s.proposals[i].id) {
            s.proposals[i].status = .expired; s.proposals[i].version += 1
        }
        for w in top where !s.proposals.contains(where: { $0.id == w.id }) {
            let p = Proposal(id: w.id, participants: pair, start: w.start, end: w.end, createdAt: now,
                             expiresAt: min(w.start, now.addingTimeInterval(Double(s.settings.proposalLifetimeHours) * 3600)),
                             createdBy: "agent", explanation: w.explanation)
            s.proposals.append(p)
            log(&s, now, .tool, "create_proposal(\(p.id)) · \(w.explanation)")
        }
        // Reopen nothing automatically; bound history so state stays small.
        let closed = s.proposals.filter { !$0.status.isOpen && $0.status != .confirmed }
        if closed.count > 30 {
            let drop = Set(closed.sorted { $0.createdAt < $1.createdAt }.prefix(closed.count - 30).map(\.id))
            s.proposals.removeAll { drop.contains($0.id) }
        }
    }

    public func makeSnapshot(_ s: AppState, now: Date) -> WidgetSnapshot {
        let models = self.models(s, now: now)
        let start = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 1800) * 1800)
        let others = s.people.filter { $0.id != s.viewerID }
        let people = others.map { p -> WidgetPerson in
            let forecast = (0..<48).map { i in
                engine.scorer.estimate(person: p, at: start.addingTimeInterval(Double(i) * 1800 + 60),
                                       model: models[p.id], overrides: s.overrides).level
            }
            return WidgetPerson(id: p.id, name: p.name, relationship: p.relationship, city: p.city, flag: p.flag,
                                initials: p.initials, timeZoneID: p.timeZoneID, forecast: forecast)
        }
        let props = s.proposals.filter { $0.participants.contains(s.viewerID) }.compactMap { p -> WidgetProposal? in
            guard let other = p.participants.first(where: { $0 != s.viewerID }),
                  let op = s.person(other) else { return nil }
            return WidgetProposal(id: p.id, personID: other, personName: op.relationship, start: p.start, end: p.end,
                                  state: p.viewerState(s.viewerID), explanation: p.explanation)
        }
        let busy = s.overrides.first { $0.personID == s.viewerID && $0.isActive(at: now) }?.end
        let sync: SyncStatus = s.settings.simulateOffline ? .offlinePending(s.settings.pendingSyncCount) : .localOnly
        return WidgetSnapshot(generatedAt: now, forecastStart: start, clockOffset: s.clockOffset,
                              viewerID: s.viewerID, viewerName: s.viewer?.name ?? "You",
                              viewerTimeZoneID: s.viewer?.timeZoneID ?? TimeZone.current.identifier,
                              use24Hour: s.settings.use24Hour, focusPersonID: s.focusPersonID,
                              people: people, proposals: props, busyUntil: busy, sync: sync, isDemo: s.isDemo)
    }

    // MARK: reads

    public func loadState() async -> AppState { readOnly { s, _ in s } ?? AppState() }
    public func now() async -> Date { readOnly { _, n in n } ?? clock.now }
    public func snapshot() -> WidgetSnapshot? { readOnly { s, n in makeSnapshot(s, now: n) } }
    public func windows() -> [RankedWindow] { readOnly { s, n in rankedWindows(s, now: n) } ?? [] }
    public func slotModel(_ personID: String) -> SlotModel? {
        readOnly { s, n in s.person(personID).map { engine.scorer.buildModel(person: $0, events: s.events, now: n) } } ?? nil
    }
    public func estimate(_ personID: String, at instant: Date? = nil) -> AvailabilityEstimate? {
        readOnly { s, n in
            guard let p = s.person(personID) else { return nil }
            let m = engine.scorer.buildModel(person: p, events: s.events, now: n)
            return engine.scorer.estimate(person: p, at: instant ?? n, model: m, overrides: s.overrides)
        } ?? nil
    }

    // MARK: onboarding & demo controls

    public func completeOnboarding(profile: Person, useDemoFamily: Bool) async throws {
        try mutate { s, _ in
            if useDemoFamily {
                var me = profile; me.id = "you"
                s = DemoSeed.makeState(realNow: clock.now, you: me)
                s.settings.onboardingComplete = true
            } else {
                var me = profile; me.id = "you"
                s = AppState(); s.people = [me]; s.viewerID = me.id; s.settings.onboardingComplete = true
            }
            let n = effectiveNow(s)
            refreshProposals(&s, now: n)
        }
    }

    public func resetDemo() async throws {
        try mutate { s, _ in
            let settings = s.settings
            s = DemoSeed.makeState(realNow: clock.now)
            s.settings = settings; s.settings.onboardingComplete = true
            s.settings.simulateOffline = false; s.settings.pendingSyncCount = 0
            refreshProposals(&s, now: effectiveNow(s))
        }
    }

    public func clearDemoData() async throws {
        try mutate { s, now in
            guard let me = s.viewer else { return }
            let settings = s.settings
            s = AppState(); s.people = [me]; s.viewerID = me.id; s.settings = settings
            s.settings.pendingSyncCount = 0
            log(&s, now, .system, "Cleared demo family and synthetic history.")
        }
    }

    public func switchViewer(_ id: String) async throws {
        try mutate { s, now in
            guard s.person(id) != nil else { throw RepositoryError.invalid("unknown person") }
            s.viewerID = id
            s.focusPersonID = s.people.first { $0.id != id && $0.id == (id == "you" ? "mom" : "you") }?.id
                ?? s.people.first { $0.id != id }?.id ?? ""
            log(&s, now, .user, "Demo: switched active participant to \(s.person(id)?.name ?? id).")
            refreshProposals(&s, now: now)
        }
    }

    public func setFocus(_ id: String) async throws {
        try mutate { s, now in
            guard s.person(id) != nil, id != s.viewerID else { throw RepositoryError.invalid("invalid focus") }
            s.focusPersonID = id
            refreshProposals(&s, now: now)
        }
    }

    public func advanceClock(by seconds: TimeInterval) async throws {
        try mutate { s, _ in
            s.clockOffset += seconds
            let n = effectiveNow(s)
            normalize(&s, now: n)
            log(&s, n, .system, "Demo clock advanced \(Int(seconds / 60)) min.")
            refreshProposals(&s, now: n)
        }
    }

    public func advanceClock(to target: Date) async throws {
        let n = await now()
        try await advanceClock(by: max(0, target.timeIntervalSince(n)))
    }

    public func setSimulatedOffline(_ offline: Bool) async throws {
        try mutate { s, now in
            if s.settings.simulateOffline && !offline {
                log(&s, now, .system, "Simulated reconnect: \(s.settings.pendingSyncCount) local changes would sync now (no real backend in demo).")
                s.settings.pendingSyncCount = 0
            }
            s.settings.simulateOffline = offline
        }
    }

    public func updateSettings(_ f: @Sendable (inout AppSettings) -> Void) async throws {
        try mutate { s, now in f(&s.settings); refreshProposals(&s, now: now) }
    }

    public func updatePreferences(personID: String, _ prefs: LocalPreferences) async throws {
        try mutate { s, now in
            guard let i = s.people.firstIndex(where: { $0.id == personID }) else { return }
            s.people[i].prefs = prefs; touch(&s)
            log(&s, now, .user, "Updated preferences for \(s.people[i].name).")
            refreshProposals(&s, now: now)
        }
    }

    // MARK: privacy controls

    public func setLearningPaused(_ paused: Bool) async throws {
        try mutate { s, now in
            s.settings.learningPaused = paused
            log(&s, now, .user, paused ? "Paused availability learning." : "Resumed availability learning.")
        }
    }

    public func deleteLearnedAvailability() async throws {
        try mutate { s, now in
            let n = s.events.count; s.events.removeAll()
            log(&s, now, .user, "Deleted \(n) learned activity events.")
            refreshProposals(&s, now: now)
        }
    }

    /// Records in-app metadata. Dropped while learning is paused.
    public func record(_ event: ActivityEvent) async throws {
        try mutate { s, _ in if !s.settings.learningPaused { s.events.append(event) } }
    }

    // MARK: proposals

    public func refresh() async throws { try mutate { s, now in refreshProposals(&s, now: now) } }

    public func confirm(proposalID: String, as personID: String) async throws -> ConfirmOutcome {
        try mutate { s, now in
            guard let i = s.proposals.firstIndex(where: { $0.id == proposalID }) else {
                return ConfirmOutcome(result: .rejected(.notFound), proposal: nil, becameConfirmed: false)
            }
            let before = s.proposals[i]
            // Re-validate hard constraints only for a confirmation that would change state.
            if before.status.isOpen && before.participants.contains(personID) && before.confirmations[personID] == nil {
                let bk = bookings(s, excluding: before.id)
                for pid in before.participants {
                    guard let person = s.person(pid) else { continue }
                    let mine = bk.filter { $0.personIDs.contains(pid) }.map(\.interval)
                    if let why = Constraints.blockReason(person: person, overrides: s.overrides, bookings: mine,
                                                         start: before.start, end: before.end) {
                        s.proposals[i].status = .expired; s.proposals[i].version += 1
                        log(&s, now, .constraint, "confirm_proposal(\(before.id)) refused: \(person.name) now has \(why.rawValue). Proposal marked stale.")
                        refreshProposals(&s, now: now)
                        return ConfirmOutcome(result: .rejected(.availabilityChanged), proposal: s.proposals[i], becameConfirmed: false)
                    }
                }
            }
            let result = BookingStateMachine.apply(.confirm(by: personID), to: before, now: now)
            var becameConfirmed = false
            if case .applied(let p) = result {
                s.proposals[i] = p; touch(&s)
                log(&s, now, .user, "\(s.person(personID)?.name ?? personID) confirmed \(p.id).")
                if p.status == .confirmed {
                    becameConfirmed = true
                    s.pendingLiveActivityProposalID = p.id
                    log(&s, now, .outcome, "Both participants confirmed. Booked.")
                    for pid in p.participants {
                        guard let person = s.person(pid) else { continue }
                        let inc = engine.inconvenience(person, at: p.start)
                        if inc > 0 { s.burdens.append(Burden(personID: pid, at: now, amount: inc, proposalID: p.id)) }
                        let mine = s.burdens.filter { $0.personID == pid }.sorted { $0.at > $1.at }
                            .prefix(engine.config.burdenHistoryLimit)
                        let keepIDs = Set(mine.map { $0.at.timeIntervalSince1970.description + $0.proposalID })
                        s.burdens.removeAll { $0.personID == pid && !keepIDs.contains($0.at.timeIntervalSince1970.description + $0.proposalID) }
                    }
                }
            }
            return ConfirmOutcome(result: result, proposal: s.proposals[i], becameConfirmed: becameConfirmed)
        }
    }

    private func transition(_ id: String, _ action: BookingAction, who: String, verb: String) throws -> TransitionResult {
        try mutate { s, now in
            guard let i = s.proposals.firstIndex(where: { $0.id == id }) else { return .rejected(.notFound) }
            let r = BookingStateMachine.apply(action, to: s.proposals[i], now: now)
            if case .applied(let p) = r {
                s.proposals[i] = p; touch(&s)
                log(&s, now, .user, "\(s.person(who)?.name ?? who) \(verb) \(p.id).")
                if s.pendingLiveActivityProposalID == p.id { s.pendingLiveActivityProposalID = nil }
                refreshProposals(&s, now: now)
            }
            return r
        }
    }

    public func decline(proposalID: String, as personID: String) async throws -> TransitionResult {
        try transition(proposalID, .decline(by: personID), who: personID, verb: "declined")
    }
    public func cancel(proposalID: String, as personID: String) async throws -> TransitionResult {
        try transition(proposalID, .cancel(by: personID), who: personID, verb: "canceled")
    }
    /// Cancels and lets the scheduler propose fresh windows (the canceled window is excluded by status).
    public func reschedule(proposalID: String, as personID: String) async throws {
        _ = try transition(proposalID, .cancel(by: personID), who: personID, verb: "canceled (to reschedule)")
        try await refresh()
    }

    public func submitFeedback(proposalID: String, choice: FeedbackChoice) async throws {
        try mutate { s, now in
            guard let i = s.proposals.firstIndex(where: { $0.id == proposalID }),
                  s.proposals[i].feedback == nil else { return }   // idempotent
            s.proposals[i].feedback = choice
            log(&s, now, .user, "Self-reported connection feedback: \(choice.rawValue) (not verified call telemetry).")
            if !s.settings.learningPaused, !s.viewerID.isEmpty {
                switch choice {
                case .yes: s.events.append(ActivityEvent(personID: s.viewerID, at: now, kind: .selfReportedConnected))
                case .no: s.events.append(ActivityEvent(personID: s.viewerID, at: now, kind: .selfReportedNotConnected))
                case .skip: break
                }
            }
        }
    }

    // MARK: Busy

    @discardableResult
    public func setBusy(personID: String, minutes: Int = 60, replaceExisting: Bool = false) async throws -> BusyOverride {
        try mutate { s, now in
            guard s.person(personID) != nil else { throw RepositoryError.invalid("unknown person") }
            let m = min(max(minutes, 5), 24 * 60)
            if !replaceExisting, let existing = s.overrides.first(where: { $0.personID == personID && $0.isActive(at: now) }) {
                return existing     // repeated tap: do not extend or duplicate
            }
            s.overrides.removeAll { $0.personID == personID }
            let o = BusyOverride(personID: personID, start: now, end: now.addingTimeInterval(Double(m) * 60), setAt: now)
            s.overrides.append(o); touch(&s)
            log(&s, now, .user, "\(s.person(personID)?.name ?? personID) set Busy for \(m) min.")
            refreshProposals(&s, now: now)
            return o
        }
    }

    public func clearBusy(personID: String) async throws {
        try mutate { s, now in
            guard s.overrides.contains(where: { $0.personID == personID }) else { return }
            s.overrides.removeAll { $0.personID == personID }; touch(&s)
            log(&s, now, .user, "\(s.person(personID)?.name ?? personID) cleared Busy.")
            refreshProposals(&s, now: now)
        }
    }

    public func clearPendingLiveActivity() async throws {
        try mutate { s, _ in s.pendingLiveActivityProposalID = nil }
    }

    // MARK: agent tool backend (validated by ToolRouter)

    func createProposal(participants: [String], start: Date, minutes: Int, createdBy: String, explanation: String) throws -> Proposal {
        try mutate { s, now in
            let people = participants.compactMap { s.person($0) }
            guard people.count == participants.count, people.count >= 2 else { throw RepositoryError.invalid("participants") }
            guard start > now else { throw RepositoryError.invalid("start must be in the future") }
            let end = start.addingTimeInterval(Double(minutes) * 60)
            let bk = bookings(s)
            for p in people {
                let mine = bk.filter { $0.personIDs.contains(p.id) }.map(\.interval)
                if let why = Constraints.blockReason(person: p, overrides: s.overrides, bookings: mine, start: start, end: end) {
                    log(&s, now, .constraint, "create_proposal refused: \(p.name) has \(why.rawValue).")
                    throw RepositoryError.invalid("window violates \(why.rawValue) for \(p.name)")
                }
            }
            let id = SchedulingEngine.proposalID(start: start, participants: participants)
            if let existing = s.proposals.first(where: { $0.id == id }) { return existing }
            let p = Proposal(id: id, participants: participants, start: start, end: end, createdAt: now,
                             expiresAt: min(start, now.addingTimeInterval(Double(s.settings.proposalLifetimeHours) * 3600)),
                             createdBy: createdBy, explanation: explanation)
            s.proposals.append(p)
            log(&s, now, .tool, "create_proposal(\(id)) by \(createdBy)")
            return p
        }
    }
}
