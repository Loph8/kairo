import Testing
import Foundation
@testable import GoldenHourCore

@Suite struct OverlapTests {
    /// Forecast that is likely free on the given 30-min steps and busy elsewhere.
    func forecast(free steps: Range<Int>) -> [AvailabilityLevel] {
        (0..<48).map { steps.contains($0) ? .likelyFree : .busy }
    }

    func person(_ id: String, free steps: Range<Int>) -> WidgetPerson {
        WidgetPerson(id: id, name: id, relationship: id, city: "", flag: nil, initials: "X",
                     timeZoneID: "Asia/Seoul", forecast: forecast(free: steps))
    }

    /// Forecast starts at UTC midnight and the viewer is in UTC, so step == local cell.
    func snapshot(viewer: Range<Int>?, others: [Range<Int>]) -> WidgetSnapshot {
        let start = Date(timeIntervalSince1970: 1_762_732_800)   // 2025-11-10 00:00 UTC
        var s = WidgetSnapshot.placeholder(now: start)
        s.viewerTimeZoneID = "UTC"
        s.forecastStart = start
        s.people = others.enumerated().map { person("p\($0.offset)", free: $0.element) }
        s.viewerForecast = viewer.map { forecast(free: $0) }
        return s
    }

    @Test func countsEveryoneIncludingViewer() {
        let s = snapshot(viewer: 10..<20, others: [12..<16, 14..<30])
        let dial = OverlapDial(snapshot: s, now: s.forecastStart)
        expectEq(dial.total, 3)
        expectEq(dial.counts[11], 1)
        expectEq(dial.counts[13], 2)
        expectEq(dial.counts[15], 3)
        expectEq(dial.counts[25], 1)
        expectEq(dial.counts[40], 0)
        expectEq(dial.allFree?.start, s.forecastStart.addingTimeInterval(14 * 1800))
        expectEq(dial.allFree?.end, s.forecastStart.addingTimeInterval(16 * 1800))
    }

    @Test func maybeFreeDoesNotCount() {
        var s = snapshot(viewer: nil, others: [0..<48])
        s.people[0].forecast[5] = .maybeFree
        let dial = OverlapDial(snapshot: s, now: s.forecastStart)
        expectEq(dial.counts[5], 0)
        expectEq(dial.counts[6], 1)
    }

    @Test func skipsAllFreeStretchThatAlreadyEnded() {
        let s = snapshot(viewer: 2..<4, others: [2..<4, 2..<4])
        let later = s.forecastStart.addingTimeInterval(5 * 1800)
        #expect(OverlapDial(snapshot: s, now: later).allFree == nil)
    }

    @Test func mapsToViewerLocalHours() {
        var s = snapshot(viewer: nil, others: [0..<2])
        s.viewerTimeZoneID = "Asia/Seoul"            // UTC+9: UTC 00:00 is 09:00 local
        let dial = OverlapDial(snapshot: s, now: s.forecastStart)
        expectEq(dial.counts[18], 1)
        expectEq(dial.counts[19], 1)
        expectEq(dial.counts[0], 0)
    }

    @Test func emptySnapshotHasNoOverlap() {
        let dial = OverlapDial(snapshot: .placeholder(now: Date()), now: Date())
        expectEq(dial.total, 0)
        #expect(dial.allFree == nil)
        expectEq(dial.counts.count, 48)
    }

    @Test func oldSnapshotWithoutViewerForecastStillDecodes() throws {
        let store = SnapshotStore(directory: TestEnv.tempDir())
        try store.save(snapshot(viewer: nil, others: [0..<4]))
        guard case .loaded(let s) = store.load() else { return fail("expected loaded") }
        #expect(s.viewerForecast == nil)
    }
}
