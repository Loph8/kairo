import Testing
import Foundation
@testable import GoldenHourCore

@Suite struct CalendarBusyTests {
    let now = Date(timeIntervalSince1970: 1_794_273_120)
    func at(_ h: Double) -> Date { now.addingTimeInterval(h * 3600) }
    var window: DateInterval { CalendarBusy.window(now: now) }

    @Test func idsAreOpaqueStableAndPerOccurrence() {
        let a = CalendarBusy.blockID(identifier: "ABC-123:secret", start: at(1))
        #expect(a == CalendarBusy.blockID(identifier: "ABC-123:secret", start: at(1)))
        #expect(a != CalendarBusy.blockID(identifier: "ABC-123:secret", start: at(25)))  // recurring next day
        #expect(a.hasPrefix("cal-") && a.count == 28 && !a.contains("ABC"))
        #expect(DeepLink.validID(a))
    }

    @Test func dropsAllDayFreeAndDeclined() {
        let events = [
            CalendarEventInfo(identifier: "allday", start: at(0), end: at(24), isAllDay: true),
            CalendarEventInfo(identifier: "free", start: at(2), end: at(3), showsAsFree: true),
            CalendarEventInfo(identifier: "no", start: at(4), end: at(5), declined: true),
            CalendarEventInfo(identifier: "gym", start: at(6), end: at(7)),
        ]
        let blocks = CalendarBusy.blocks(from: events, in: window)
        #expect(blocks.count == 1)
        #expect(blocks[0].start == at(6) && blocks[0].movable)
    }

    @Test func meetingsWithOthersAreNotMovable() {
        let b = CalendarBusy.blocks(from: [CalendarEventInfo(identifier: "m", start: at(1), end: at(2), hasOtherAttendees: true)], in: window)
        #expect(b.first?.movable == false)
    }

    @Test func keepsFourWeeksOfPastAndClipsToWindow() {
        let events = [
            CalendarEventInfo(identifier: "too-old", start: at(-30 * 24), end: at(-30 * 24 + 1)),
            CalendarEventInfo(identifier: "past", start: at(-3), end: at(-2)),
            CalendarEventInfo(identifier: "trip", start: at(2), end: at(40)),
            CalendarEventInfo(identifier: "far", start: at(5 * 24), end: at(5 * 24 + 1)),
        ]
        let blocks = CalendarBusy.blocks(from: events, in: window)
        #expect(blocks.map(\.start) == [at(-3), at(2)])   // past weeks teach the AI; too old and too far are dropped
        #expect(blocks[1].end == at(26))
        #expect(blocks.allSatisfy { $0.end.timeIntervalSince($0.start) <= CalendarBusy.maxDuration })
    }

    @Test func sortedDedupedAndCapped() {
        let many = (0..<(CalendarBusy.maxBlocks + 100)).map { CalendarEventInfo(identifier: "e\($0)", start: at(Double(300 - $0) * 0.1), end: at(Double(300 - $0) * 0.1 + 0.05)) }
        let blocks = CalendarBusy.blocks(from: many + many, in: window)
        #expect(blocks.count == CalendarBusy.maxBlocks)
        #expect(blocks == blocks.sorted { $0.start < $1.start })
        #expect(Set(blocks.map(\.id)).count == blocks.count)
        #expect(blocks.last?.start == many.map(\.start).max())   // over the cap, the newest are kept
    }
}
