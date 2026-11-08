import Testing
import Foundation
@testable import KairoCore

@Suite struct SnapshotTests {
    func sample() -> WidgetSnapshot {
        var s = WidgetSnapshot.placeholder(now: DemoSeed.anchor)
        s.people = [WidgetPerson(id: "mom", name: "Mom", relationship: "Mom", city: "Seoul", flag: "🇰🇷", initials: "M",
                                 timeZoneID: "Asia/Seoul", forecast: Array(repeating: .likelyFree, count: 48))]
        s.viewerID = "you"; s.focusPersonID = "mom"
        return s
    }

    @Test func roundTripAtomicWrite() throws {
        let store = SnapshotStore(directory: TestEnv.tempDir())
        try store.save(sample())
        guard case .loaded(let s) = store.load() else { return fail("expected loaded") }
        expectEq(s.people.first?.id, "mom")
        expectEq(s.generatedAt, DemoSeed.anchor)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: store.fileURL!.deletingLastPathComponent().path)
        expectEq(leftovers, ["snapshot.json"])   // no stray temp files
    }

    @Test func fallbacks() throws {
        let dir = TestEnv.tempDir(); let store = SnapshotStore(directory: dir)
        if case .empty = store.load() {} else { fail("expected empty") }
        try Data("{not json".utf8).write(to: store.fileURL!)
        if case .corrupted = store.load() {} else { fail("expected corrupted") }
        try Data(#"{"schemaVersion": 99}"#.utf8).write(to: store.fileURL!)
        if case .unsupportedVersion = store.load() {} else { fail("expected unsupported") }
        if case .unavailable = SnapshotStore(directory: nil).load() {} else { fail("expected unavailable") }
        expectThrows(try SnapshotStore(directory: nil).save(sample()))
    }

    @Test func forecastLookupAndStaleness() {
        let s = sample()
        expectEq(s.level(of: "mom", at: DemoSeed.anchor.addingTimeInterval(3600)), .likelyFree)
        expectNil(s.level(of: "mom", at: DemoSeed.anchor.addingTimeInterval(25 * 3600)))   // beyond forecast
        expectNil(s.level(of: "ghost", at: DemoSeed.anchor))
        expectFalse(s.isStale(at: DemoSeed.anchor.addingTimeInterval(3600)))
        expectTrue(s.isStale(at: DemoSeed.anchor.addingTimeInterval(7 * 3600)))
    }

    @Test func deepLinkValidation() {
        expectEq(DeepLink(url: URL(string: "kairo://proposal/p-20261109T0012Z-mom+you")!), .proposal("p-20261109T0012Z-mom+you"))
        expectEq(DeepLink(url: URL(string: "kairo://schedule")!), .schedule)
        expectNil(DeepLink(url: URL(string: "kairo://member/../etc")!))
        expectNil(DeepLink(url: URL(string: "kairo://member/a%20b")!))
        expectNil(DeepLink(url: URL(string: "https://evil.example/member/mom")!))
        expectNil(DeepLink(url: URL(string: "kairo://call/\(String(repeating: "a", count: 200))")!))
    }
}

@Suite struct SyncSummaryTests {
    @Test func summariesContainOnlyCoarseFieldsAndExpire() throws {
        let people = DemoSeed.people()
        let scorer = AvailabilityScorer()
        let mom = people[1]
        let model = scorer.buildModel(person: mom, events: DemoSeed.syntheticEvents(for: people), now: DemoSeed.anchor)
        let s = SummaryBuilder.make(person: mom, model: model, overrides: [], now: DemoSeed.anchor)
        expectEq(s.count, 96)
        expectTrue(s.allSatisfy { $0.validUntil > DemoSeed.anchor })
        let json = String(data: try Codec.encoder().encode(s), encoding: .utf8)!
        expectFalse(json.contains("score")); expectFalse(json.contains("magnitude"))
        expectEq(s[0].level, .likelyFree)
    }
}
