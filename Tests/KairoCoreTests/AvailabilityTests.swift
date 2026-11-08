import Testing
import Foundation
@testable import KairoCore

@Suite struct AvailabilityTests {
    let scorer = AvailabilityScorer()
    var people: [Person] { DemoSeed.people() }
    var events: [ActivityEvent] { DemoSeed.syntheticEvents(for: people) }

    func estimate(_ id: String, overrides: [BusyOverride] = [], at: Date = DemoSeed.anchor) -> AvailabilityEstimate {
        let p = people.first { $0.id == id }!
        return scorer.estimate(person: p, at: at, model: scorer.buildModel(person: p, events: events, now: DemoSeed.anchor),
                               overrides: overrides)
    }

    @Test func syntheticHistoryProducesExpectedAnchorStates() {
        expectEq(estimate("mom").level, .likelyFree)
        expectEq(estimate("dad").level, .maybeFree)
        expectEq(estimate("sis").level, .quietHours)   // 3:12 AM in Addis, from preferences
    }

    @Test func seedIsDeterministicAndLabeledSynthetic() {
        expectEq(events.map(\.id), DemoSeed.syntheticEvents(for: people).map(\.id))
        expectTrue(events.allSatisfy(\.synthetic))
        expectGT(events.count, 60)
    }

    @Test func lowConfidenceBecomesLearningNotFree() {
        let mom = people[1]
        let model = scorer.buildModel(person: mom, events: [], now: DemoSeed.anchor)
        let e = scorer.estimate(person: mom, at: DemoSeed.anchor, model: model, overrides: [])
        expectEq(e.level, .learning)
        expectLT(e.confidence, scorer.config.minConfidence)
    }

    @Test func missedCallsAreWeakAndNeverBusy() {
        let mom = people[1]
        let evs = (1...3).map { ActivityEvent(personID: "mom", at: DemoSeed.anchor.addingTimeInterval(-Double($0) * 86400),
                                              kind: .callMissed) }
        let model = scorer.buildModel(person: mom, events: evs, now: DemoSeed.anchor)
        let e = scorer.estimate(person: mom, at: DemoSeed.anchor, model: model, overrides: [])
        expectNE(e.level, .busy)
        expectFalse(e.level.isHardBlock)
    }

    @Test func busyOverrideBeatsLearnedAndQuietHoursAndExpires() {
        let o = BusyOverride(personID: "mom", start: DemoSeed.anchor, end: DemoSeed.anchor.addingTimeInterval(3600),
                             setAt: DemoSeed.anchor)
        let busy = estimate("mom", overrides: [o])
        expectEq(busy.level, .busy); expectEq(busy.source, .explicitOverride)
        expectEq(busy.until, o.end)
        let sisO = BusyOverride(personID: "sis", start: DemoSeed.anchor, end: DemoSeed.anchor.addingTimeInterval(3600), setAt: DemoSeed.anchor)
        expectEq(estimate("sis", overrides: [sisO]).source, .explicitOverride)   // override outranks quiet hours
        let after = estimate("mom", overrides: [o], at: DemoSeed.anchor.addingTimeInterval(3600))   // exactly at end
        expectNE(after.source, .explicitOverride)
    }

    @Test func overrideForOtherPersonDoesNotLeak() {
        let o = BusyOverride(personID: "dad", start: DemoSeed.anchor, end: DemoSeed.anchor.addingTimeInterval(3600), setAt: DemoSeed.anchor)
        expectEq(estimate("mom", overrides: [o]).level, .likelyFree)
    }

    @Test func recencyWeighting() {
        let p = people[1]
        let recent = ActivityEvent(personID: "mom", at: DemoSeed.anchor.addingTimeInterval(-86400), kind: .callAnswered)
        let old = ActivityEvent(personID: "mom", at: DemoSeed.anchor.addingTimeInterval(-40 * 86400), kind: .callAnswered)
        let m1 = scorer.buildModel(person: p, events: [recent], now: DemoSeed.anchor)
        let m2 = scorer.buildModel(person: p, events: [old], now: DemoSeed.anchor)
        expectGT(m1.cells.map(\.evidence).max()!, m2.cells.map(\.evidence).max()!)
    }
}
