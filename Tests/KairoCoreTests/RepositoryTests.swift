import Testing
import Foundation
@testable import KairoCore

@Suite struct RepositoryTests {
    @Test func seededDemoCreatesThreeProposalsWithMom() async throws {
        let repo = try await TestEnv.seededRepo()
        let s = await repo.loadState()
        expectEq(s.viewerID, "you"); expectEq(s.focusPersonID, "mom")
        expectEq(s.proposals.filter { $0.status == .suggested }.count, 3)
        expectTrue(s.events.allSatisfy(\.synthetic))
        expectTrue(s.isDemo)
    }

    @Test func fullBookingFlowAcrossParticipantsUpdatesWidgetSnapshot() async throws {
        let repo = try await TestEnv.seededRepo()
        let pid = (await repo.loadState()).proposals.first { $0.status == .suggested }!.id

        let first = try await repo.confirm(proposalID: pid, as: "you")
        guard case .applied(let p1) = first.result else { return fail() }
        expectEq(p1.status, .pending); expectFalse(first.becameConfirmed)
        var snap = repo.snapshot()!
        expectEq(snap.proposals.first { $0.id == pid }?.state, .awaitingOther)   // "Waiting for Mom"

        // Repeated tap: no duplicate, no change.
        let repeatTap = try await repo.confirm(proposalID: pid, as: "you")
        if case .unchanged = repeatTap.result {} else { fail("expected idempotent") }
        expectEq((await repo.loadState()).proposals.filter { $0.id == pid }.count, 1)

        try await repo.switchViewer("mom")
        snap = repo.snapshot()!
        expectEq(snap.proposals.first { $0.id == pid }?.state, .awaitingYou)
        let second = try await repo.confirm(proposalID: pid, as: "mom")
        expectTrue(second.becameConfirmed)
        let s = await repo.loadState()
        expectEq(s.pendingLiveActivityProposalID, pid)
        expectEq(repo.snapshot()!.proposals.first { $0.id == pid }?.state, .confirmed)
    }

    @Test func busyIsIdempotentExpiresAndRefreshesSnapshot() async throws {
        let repo = try await TestEnv.seededRepo()
        let o1 = try await repo.setBusy(personID: "you", minutes: 60)
        let o2 = try await repo.setBusy(personID: "you", minutes: 60)   // repeated tap
        expectEq(o1, o2)
        expectEq(repo.snapshot()!.busyUntil, DemoSeed.anchor.addingTimeInterval(3600))
        let changed = try await repo.setBusy(personID: "you", minutes: 120, replaceExisting: true)
        expectEq(changed.end, DemoSeed.anchor.addingTimeInterval(7200))
        try await repo.clearBusy(personID: "you")
        expectNil(repo.snapshot()!.busyUntil)
        try await repo.setBusy(personID: "you", minutes: 60)
        try await repo.advanceClock(by: 61 * 60)
        expectNil(repo.snapshot()!.busyUntil)   // expired
    }

    @Test func busyOnOtherPersonStalesProposalAndConfirmIsRejected() async throws {
        let repo = try await TestEnv.seededRepo()
        let first = (await repo.loadState()).proposals.filter { $0.status == .suggested }.sorted { $0.start < $1.start }[0]
        try await repo.advanceClock(to: first.start.addingTimeInterval(-7200))
        guard (await repo.loadState()).proposals.first(where: { $0.id == first.id })?.status == .suggested else {
            return fail("precondition: proposal should still be open two hours before it starts")
        }
        try await repo.setBusy(personID: "mom", minutes: 240)   // overlaps the window
        let out = try await repo.confirm(proposalID: first.id, as: "you")
        if case .rejected = out.result {} else { fail("stale proposal must not be confirmable") }
        expectNE((await repo.loadState()).proposals.first { $0.id == first.id }?.status, .confirmed)
    }

    @Test func proposalExpiresWhenClockPassesStart() async throws {
        let repo = try await TestEnv.seededRepo()
        let first = (await repo.loadState()).proposals.filter { $0.status == .suggested }.sorted { $0.start < $1.start }[0]
        try await repo.advanceClock(to: first.start.addingTimeInterval(60))
        expectEq((await repo.loadState()).proposals.first { $0.id == first.id }?.status, .expired)
        let out = try await repo.confirm(proposalID: first.id, as: "you")
        if case .rejected(let r) = out.result { expectEq(r, .expired) } else { fail() }
    }

    @Test func concurrentConfirmationsSerializeToOneBooking() async throws {
        let repo = try await TestEnv.seededRepo()
        let pid = (await repo.loadState()).proposals.first { $0.status == .suggested }!.id
        await withTaskGroup(of: Void.self) { g in
            for i in 0..<20 {
                g.addTask { _ = try? await repo.confirm(proposalID: pid, as: i % 2 == 0 ? "you" : "mom") }
            }
        }
        let s = await repo.loadState()
        let p = s.proposals.filter { $0.id == pid }
        expectEq(p.count, 1)
        expectEq(p[0].status, .confirmed)
        expectEq(p[0].confirmations.count, 2)
        expectEq(s.burdens.filter { $0.proposalID == pid }.count <= 2, true)
    }

    @Test func offlineSimulationDistinguishesLocalFromSynced() async throws {
        let repo = try await TestEnv.seededRepo()
        expectEq(repo.snapshot()!.sync, .localOnly)
        try await repo.setSimulatedOffline(true)
        try await repo.setBusy(personID: "you", minutes: 30)
        expectEq(repo.snapshot()!.sync, .offlinePending(1))
        try await repo.setSimulatedOffline(false)
        expectEq(repo.snapshot()!.sync, .localOnly)
    }

    @Test func privacyControls() async throws {
        let repo = try await TestEnv.seededRepo()
        try await repo.setLearningPaused(true)
        let before = (await repo.loadState()).events.count
        try await repo.record(ActivityEvent(personID: "mom", at: DemoSeed.anchor, kind: .callAnswered))
        expectEq((await repo.loadState()).events.count, before)   // dropped while paused
        try await repo.setLearningPaused(false)
        try await repo.deleteLearnedAvailability()
        expectEq((await repo.loadState()).events.count, 0)
        expectEq(repo.estimate("mom")?.level, .learning)
        try await repo.clearDemoData()
        let s = await repo.loadState()
        expectEq(s.people.count, 1); expectTrue(s.proposals.isEmpty); expectFalse(s.isDemo)
    }

    @Test func feedbackIsIdempotentAndSelfReported() async throws {
        let repo = try await TestEnv.seededRepo()
        let pid = (await repo.loadState()).proposals.first!.id
        try await repo.submitFeedback(proposalID: pid, choice: .yes)
        try await repo.submitFeedback(proposalID: pid, choice: .no)
        let s = await repo.loadState()
        expectEq(s.proposals.first { $0.id == pid }?.feedback, .yes)
        expectEq(s.events.filter { $0.kind == .selfReportedConnected }.count, 1)
    }

    @Test func corruptedStateFallsBackToEmptyWithoutCrashing() async throws {
        let repo = try await TestEnv.seededRepo()
        try Data("garbage".utf8).write(to: repo.directory.appendingPathComponent("state.json"))
        let s = await repo.loadState()
        expectTrue(s.people.isEmpty)
        expectTrue(FileManager.default.fileExists(atPath: repo.directory.appendingPathComponent("state.corrupt.json").path))
    }

    @Test func emptyFamilyHasNoProposals() async throws {
        let repo = LocalDemoRepository(directory: TestEnv.tempDir(), clock: FixedTimeSource(DemoSeed.anchor))
        let me = Person(id: "x", name: "A Very Long Name That Should Truncate Gracefully", relationship: "Me", city: "Durham", timeZoneID: "America/New_York")
        try await repo.completeOnboarding(profile: me, useDemoFamily: false)
        let s = await repo.loadState()
        expectEq(s.people.count, 1); expectTrue(s.proposals.isEmpty)
        expectTrue(repo.snapshot()!.people.isEmpty)
    }

    // MARK: agent tools

    @Test func agentCannotConfirmOrDecline() async throws {
        let repo = try await TestEnv.seededRepo()
        let router = ToolRouter(repo: repo)
        let pid = (await repo.loadState()).proposals.first!.id
        for tool in ["confirm_proposal", "decline_proposal"] {
            do {
                _ = try await router.call(tool, ["proposal_id": .string(pid), "person": .string("you")], as: .agent)
                fail("agent must not consent")
            } catch let e as ToolError { expectTrue(e.message.contains("impersonate")) }
        }
        do { _ = try await router.call("confirm_proposal", ["proposal_id": .string(pid), "person": .string("mom")], as: .user("you")); fail() }
        catch is ToolError {}
        expectTrue((await repo.loadState()).proposals.first { $0.id == pid }!.confirmations.isEmpty)
    }

    @Test func agentToolValidationAndQuietHoursCannotBeOverridden() async throws {
        let repo = try await TestEnv.seededRepo()
        let router = ToolRouter(repo: repo)
        // 3:12 AM in Addis is quiet hours: the agent cannot create a proposal there.
        let quiet = ISO8601DateFormatter().string(from: DemoSeed.anchor.addingTimeInterval(3600))
        do { _ = try await router.call("create_proposal", ["participants": .array([.string("you"), .string("sis")]),
                                                           "start": .string(quiet)], as: .agent); fail() }
        catch let e as ToolError { expectTrue(e.message.contains("quietHours") || e.message.contains("busy")) }
        // Bad arguments are rejected.
        do { _ = try await router.call("rank_candidate_windows", ["participants": .array([.string("you")])], as: .agent); fail() } catch is ToolError {}
        do { _ = try await router.call("rank_candidate_windows", ["participants": .array([.string("you"), .string("mom")]),
                                                                  "duration_minutes": .number(5)], as: .agent); fail() } catch is ToolError {}
        do { _ = try await router.call("nope", [:], as: .agent); fail() } catch is ToolError {}
        // A ranked window can be proposed by the agent, but stays unconfirmed.
        let ranked = try await router.call("rank_candidate_windows", ["participants": .array([.string("you"), .string("mom")])], as: .agent)
        guard case .array(let ws) = ranked, case .object(let w) = ws[0], let start = w["start"] else { return fail() }
        let made = try await router.call("create_proposal", ["participants": .array([.string("you"), .string("mom")]), "start": start], as: .agent)
        guard case .object(let o) = made else { return fail() }
        expectEq(o["status"], .string("suggested"))
        // Shared availability exposes coarse level and confidence bucket, never raw scores.
        let shared = try await router.call("get_shared_availability", ["participants": .array([.string("you"), .string("mom")]),
            "start": .string(ISO8601DateFormatter().string(from: DemoSeed.anchor)),
            "end": .string(ISO8601DateFormatter().string(from: DemoSeed.anchor.addingTimeInterval(1800)))], as: .agent)
        expectFalse(String(data: try JSONEncoder().encode(shared), encoding: .utf8)!.contains("score"))
    }

    @Test func remoteExplainerFallsBackWhenUnreachable() async {
        let w = RankedWindow(id: "x", start: DemoSeed.anchor, end: DemoSeed.anchor, participants: [], fits: [],
                             overall: 0, leastConvenient: 0, fairnessPenalty: 0, total: 0, explanation: "deterministic")
        let ex = RemoteClaudeExplainer(endpoint: URL(string: "http://127.0.0.1:9/none")!, bearerToken: "t")
        let text = await ex.explain(w)
        expectEq(text, "deterministic")
    }
}
