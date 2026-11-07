import Testing
import Foundation
@testable import GoldenHourCore

@Suite struct SchedulingTests {
    let engine = SchedulingEngine()
    let people = DemoSeed.people()
    func models(_ ps: [Person], events: [ActivityEvent]) -> [String: SlotModel] {
        Dictionary(uniqueKeysWithValues: ps.map { ($0.id, engine.scorer.buildModel(person: $0, events: events, now: DemoSeed.anchor)) })
    }

    func rankYouMom(overrides: [BusyOverride] = [], burdens: [Burden] = []) -> [RankedWindow] {
        let ps = [people[0], people[1]]
        return engine.rank(participants: ps, models: models(ps, events: DemoSeed.syntheticEvents(for: people)),
                           overrides: overrides, bookings: [], burdens: burdens, now: DemoSeed.anchor)
    }

    @Test func returnsThreeWindowsSortedByInstantAndRespectingHardConstraints() {
        let w = rankYouMom()
        expectEq(w.count, 3)
        expectEq(w.map(\.start), w.map(\.start).sorted())
        for win in w {
            expectGT(win.start, DemoSeed.anchor)
            for p in [people[0], people[1]] {
                expectNil(Constraints.blockReason(person: p, overrides: [], bookings: [], start: win.start, end: win.end))
            }
            expectFalse(win.explanation.isEmpty)
        }
    }

    @Test func busyOverrideExcludesOverlappingWindows() {
        let baseline = rankYouMom()
        let o = BusyOverride(personID: "mom", start: DemoSeed.anchor, end: baseline[0].end.addingTimeInterval(600), setAt: DemoSeed.anchor)
        let after = rankYouMom(overrides: [o])
        for w in after { expectGE(w.start, o.end) }
        expectFalse(after.contains { $0.id == baseline[0].id })
    }

    @Test func existingBookingBlocksOverlap() {
        let ps = [people[0], people[1]]
        let first = rankYouMom()[0]
        let booked = BookedInterval(personIDs: ["you", "mom"], interval: Interval(start: first.start, end: first.end))
        let w = engine.rank(participants: ps, models: models(ps, events: DemoSeed.syntheticEvents(for: people)),
                            overrides: [], bookings: [booked], burdens: [], now: DemoSeed.anchor)
        expectFalse(w.contains { $0.id == first.id })
    }

    @Test func proposalIDStableAndOrderIndependent() {
        let s = DemoSeed.anchor
        expectEq(SchedulingEngine.proposalID(start: s, participants: ["you", "mom"]),
                       SchedulingEngine.proposalID(start: s, participants: ["mom", "you"]))
        expectEq(SchedulingEngine.proposalID(start: s, participants: ["you", "mom"]), "p-20261109T0012Z-mom+you")
    }

    @Test func fairnessShiftsInconvenienceToTheLessBurdenedPerson() {
        // Two zones 12h apart: every shared window is comfortable for exactly one person.
        let a = Person(id: "a", name: "A", relationship: "A", city: "UTC", timeZoneID: "UTC",
                       prefs: .init(wakeMinute: 6 * 60, bedMinute: 23 * 60))
        let b = Person(id: "b", name: "B", relationship: "B", city: "Fiji", timeZoneID: "Pacific/Fiji",
                       prefs: .init(wakeMinute: 6 * 60, bedMinute: 23 * 60))
        let ps = [a, b]
        let m = Dictionary(uniqueKeysWithValues: ps.map { ($0.id, engine.scorer.buildModel(person: $0, events: [], now: DemoSeed.anchor)) })
        func top(_ burdens: [Burden]) -> RankedWindow {
            var cfg = SchedulingConfig(); cfg.horizonHours = 48; cfg.topCount = 20; cfg.minSeparationMinutes = 30
            let e = SchedulingEngine(config: cfg)
            // The highest total, not the earliest.
            let all = e.rank(participants: ps, models: m, overrides: [], bookings: [], burdens: burdens, now: DemoSeed.anchor)
            return all.max { $0.total < $1.total }!
        }
        func inc(_ w: RankedWindow, _ id: String) -> Double { w.fits.first { $0.personID == id }!.inconvenience }
        let burdenB = (1...4).map { Burden(personID: "b", at: DemoSeed.anchor.addingTimeInterval(-Double($0) * 86400), amount: 0.5, proposalID: "x\($0)") }
        let burdenA = burdenB.map { Burden(personID: "a", at: $0.at, amount: $0.amount, proposalID: $0.proposalID) }
        expectEq(inc(top(burdenB), "b"), 0)
        expectEq(inc(top(burdenA), "a"), 0)
        expectNE(top(burdenA).id, top(burdenB).id)
        expectTrue(top(burdenB).explanation.contains("B had a less convenient call recently"))
    }

    @Test func burdenHistoryIsBoundedAndDecays() {
        let many = (0..<30).map { Burden(personID: "a", at: DemoSeed.anchor.addingTimeInterval(-Double($0) * 3600), amount: 1, proposalID: "p\($0)") }
        let load = engine.burdenLoad("a", burdens: many, now: DemoSeed.anchor)
        expectLE(load, 1)
        let old = [Burden(personID: "a", at: DemoSeed.anchor.addingTimeInterval(-120 * 86400), amount: 1, proposalID: "o")]
        expectLT(engine.burdenLoad("a", burdens: old, now: DemoSeed.anchor), 0.01)
    }

    @Test func needsTwoParticipants() {
        expectTrue(engine.rank(participants: [people[0]], models: [:], overrides: [], bookings: [], burdens: [], now: DemoSeed.anchor).isEmpty)
    }
}
