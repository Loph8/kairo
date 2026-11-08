import Testing
import Foundation
@testable import GoldenHourCore

@Suite struct TimeKitTests {
    @Test func sameInstantDifferentLocalDates() {
        let a = DemoSeed.anchor
        expectEq(TimeKit.formatTime(a, TestEnv.ny, use24Hour: false), "7:12 PM")
        expectEq(TimeKit.formatTime(a, TestEnv.seoul, use24Hour: false), "9:12 AM")
        expectEq(TimeKit.formatTime(a, TestEnv.addis, use24Hour: false), "3:12 AM")
        let ny = TimeKit.ymd(a, TestEnv.ny), seoul = TimeKit.ymd(a, TestEnv.seoul)
        expectEq(ny.2, 8); expectEq(seoul.2, 9)   // different local calendar dates
    }

    @Test func tomorrowLabelJudgedInViewerZone() {
        let later = DemoSeed.anchor.addingTimeInterval(20 * 3600)   // NY Nov 9 3:12 PM
        expectEq(TimeKit.dayLabel(later, reference: DemoSeed.anchor, in: TestEnv.ny), "Tomorrow")
        expectEq(TimeKit.dayLabel(DemoSeed.anchor, reference: DemoSeed.anchor, in: TestEnv.ny), "Today")
        expectEq(TimeKit.describe(DemoSeed.anchor.addingTimeInterval(48 * 60), in: TestEnv.ny,
                                        reference: DemoSeed.anchor, use24Hour: false), "Today, 8:00 PM")
    }

    @Test func twentyFourHourFormatting() {
        expectEq(TimeKit.formatTime(DemoSeed.anchor, TestEnv.ny, use24Hour: true), "19:12")
    }

    @Test func noHardcodedOffsets_NewYorkNoonShiftsWithDST() {
        let jan = TimeKit.resolve(year: 2027, month: 1, day: 15, minuteOfDay: 720, in: TestEnv.ny)!
        let jul = TimeKit.resolve(year: 2027, month: 7, day: 15, minuteOfDay: 720, in: TestEnv.ny)!
        expectEq(jan, TestEnv.iso("2027-01-15T17:00:00Z"))   // EST
        expectEq(jul, TestEnv.iso("2027-07-15T16:00:00Z"))   // EDT
    }

    @Test func springForwardNonexistentTimeMovesForward() {
        // 2026-03-08 02:30 does not exist in New York.
        let d = TimeKit.resolve(year: 2026, month: 3, day: 8, minuteOfDay: 150, in: TestEnv.ny)!
        expectEq(d, TestEnv.iso("2026-03-08T07:00:00Z"))      // 3:00 AM EDT
        expectEq(TimeKit.formatTime(d, TestEnv.ny, use24Hour: false), "3:00 AM")
    }

    @Test func fallBackRepeatedTimeResolvesToFirstOccurrence() {
        // 2026-11-01 01:30 happens twice; first is EDT (05:30Z).
        let d = TimeKit.resolve(year: 2026, month: 11, day: 1, minuteOfDay: 90, in: TestEnv.ny)!
        expectEq(d, TestEnv.iso("2026-11-01T05:30:00Z"))
    }

    @Test func localMinuteJumpsAcrossSpringForward() {
        let before = TimeKit.local(TestEnv.iso("2026-03-08T06:59:00Z"), TestEnv.ny)
        let after = TimeKit.local(TestEnv.iso("2026-03-08T07:00:00Z"), TestEnv.ny)
        expectEq(before.minuteOfDay, 119); expectEq(after.minuteOfDay, 180)
    }

    @Test func differentDSTRulesDoNotShareOffsets() {
        // In late March NY has sprung forward but Europe/London has not yet (until Mar 29).
        let london = TimeZone(identifier: "Europe/London")!
        let d = TestEnv.iso("2026-03-20T12:00:00Z")
        expectEq(TimeKit.formatTime(d, TestEnv.ny, use24Hour: true), "08:00")
        expectEq(TimeKit.formatTime(d, london, use24Hour: true), "12:00")
    }

    @Test func quietHoursCrossingMidnight() {
        let p = LocalPreferences(wakeMinute: 7 * 60, bedMinute: 22 * 60 + 30)
        expectTrue(p.isQuiet(minuteOfDay: 23 * 60))
        expectTrue(p.isQuiet(minuteOfDay: 3 * 60))
        expectTrue(p.isQuiet(minuteOfDay: 0))
        expectFalse(p.isQuiet(minuteOfDay: 7 * 60))
        expectFalse(p.isQuiet(minuteOfDay: 22 * 60 + 29))
        expectTrue(p.isQuiet(minuteOfDay: 22 * 60 + 30))
        let late = LocalPreferences(wakeMinute: 6 * 60, bedMinute: 60)   // bedtime after midnight
        expectTrue(late.isQuiet(minuteOfDay: 2 * 60)); expectFalse(late.isQuiet(minuteOfDay: 23 * 60))
    }

    @Test func callStraddlingBedtimeIsBlocked() {
        let sis = DemoSeed.people()[3]   // bed 22:30 Addis
        let start = TestEnv.iso("2026-11-09T19:10:00Z")  // 22:10 Addis → 22:40 crosses bedtime
        expectEq(Constraints.blockReason(person: sis, overrides: [], bookings: [], start: start,
                                               end: start.addingTimeInterval(30 * 60)), .quietHours)
    }
}
