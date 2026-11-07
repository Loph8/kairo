import Testing
import Foundation
@testable import GoldenHourCore

@Suite struct BookingTests {
    let now = DemoSeed.anchor
    func make() -> Proposal {
        Proposal(id: "p1", participants: ["you", "mom"], start: now.addingTimeInterval(3600), end: now.addingTimeInterval(5400),
                 createdAt: now, expiresAt: now.addingTimeInterval(3600), createdBy: "agent", explanation: "")
    }
    func applied(_ r: TransitionResult) -> Proposal? { if case .applied(let p) = r { return p }; return nil }

    @Test func oneConfirmationDoesNotConfirmTheOther() {
        let p = applied(BookingStateMachine.apply(.confirm(by: "you"), to: make(), now: now))!
        expectEq(p.status, .pending)
        expectEq(p.viewerState("you"), .awaitingOther)   // "Waiting for Mom"
        expectEq(p.viewerState("mom"), .awaitingYou)
        expectNil(p.confirmations["mom"])
    }

    @Test func bothConfirmedBecomesBookedInEitherOrder() {
        for order in [["you", "mom"], ["mom", "you"]] {
            var p = make()
            for who in order { p = applied(BookingStateMachine.apply(.confirm(by: who), to: p, now: now))! }
            expectEq(p.status, .confirmed); expectEq(p.viewerState("you"), .confirmed)
        }
    }

    @Test func duplicateConfirmationIsIdempotent() {
        let p1 = applied(BookingStateMachine.apply(.confirm(by: "you"), to: make(), now: now))!
        if case .unchanged(let p2) = BookingStateMachine.apply(.confirm(by: "you"), to: p1, now: now.addingTimeInterval(5)) {
            expectEq(p2, p1)   // version and timestamp untouched
        } else { fail("expected unchanged") }
        let done = applied(BookingStateMachine.apply(.confirm(by: "mom"), to: p1, now: now))!
        if case .unchanged = BookingStateMachine.apply(.confirm(by: "mom"), to: done, now: now) {} else { fail() }
    }

    @Test func expiredProposalCannotBeConfirmed() {
        let late = now.addingTimeInterval(3601)
        expectEq(BookingStateMachine.normalized(make(), now: late).status, .expired)
        if case .rejected(let r) = BookingStateMachine.apply(.confirm(by: "you"), to: make(), now: late) { expectEq(r, .expired) }
        else { fail("expected rejection") }
    }

    @Test func nonParticipantRejectedAndDeclineCancelComplete() {
        if case .rejected(let r) = BookingStateMachine.apply(.confirm(by: "dad"), to: make(), now: now) { expectEq(r, .notParticipant) } else { fail() }
        let d = applied(BookingStateMachine.apply(.decline(by: "mom"), to: make(), now: now))!
        expectEq(d.status, .declined)
        if case .rejected = BookingStateMachine.apply(.confirm(by: "you"), to: d, now: now) {} else { fail() }
        var c = make()
        for w in ["you", "mom"] { c = applied(BookingStateMachine.apply(.confirm(by: w), to: c, now: now))! }
        expectEq(applied(BookingStateMachine.apply(.cancel(by: "mom"), to: c, now: now))!.status, .canceled)
        expectEq(BookingStateMachine.normalized(c, now: c.end).status, .completed)
        if case .rejected(let r) = BookingStateMachine.apply(.complete, to: c, now: now) { expectEq(r, .notEnded) } else { fail() }
    }
}
