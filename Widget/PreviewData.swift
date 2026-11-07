import WidgetKit
import SwiftUI
import GoldenHourCore

/// Synthetic preview data derived from the real seed, so previews match the app's demo.
enum PreviewData {
    enum Variant { case suggested, waiting, confirmed, busy, unknown, longNames, stale, empty }

    static func snapshot(_ v: Variant) -> WidgetSnapshot {
        let now = DemoSeed.anchor
        let repo = LocalDemoRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("gh-preview"),
                                       clock: FixedTimeSource(now))
        var state = DemoSeed.makeState(realNow: now)
        if v == .longNames {
            state.people[1].relationship = "Grandmother Eleanor"; state.people[1].city = "Seongnam-si, Gyeonggi"
            state.people[2].relationship = "Uncle Bartholomew"
        }
        if v == .unknown { state.events.removeAll() }
        if v == .busy { state.overrides = [BusyOverride(personID: "you", start: now, end: now.addingTimeInterval(3600), setAt: now)] }
        var snap = repo.makeSnapshot(state, now: now)
        let starts = [now.addingTimeInterval(75 * 60), now.addingTimeInterval(25 * 3600), now.addingTimeInterval(49 * 3600)]
        let states: [ViewerBookingState] = v == .waiting ? [.awaitingOther, .suggested, .suggested]
            : v == .confirmed ? [.confirmed, .suggested, .suggested] : [.suggested, .suggested, .suggested]
        snap.proposals = starts.enumerated().map { i, s in
            WidgetProposal(id: "p-preview-\(i)", personID: "mom", personName: "Mom", start: s,
                           end: s.addingTimeInterval(1800), state: states[i], explanation: "Preview")
        }
        if v == .stale { snap.generatedAt = now.addingTimeInterval(-8 * 3600) }
        if v == .empty { snap.people = []; snap.proposals = [] }
        // Previews run at wall-clock time; offset so "effective now" equals the demo anchor.
        snap.clockOffset = now.timeIntervalSince(Date())
        return snap
    }

    static func entry(_ v: Variant) -> GoldenEntry {
        GoldenEntry(date: .now, snapshot: snapshot(v), status: v == .empty ? .empty : .ok, selectedID: nil)
    }
}

#Preview("Medium · suggested", as: .systemMedium) { GoldenHourWidget() } timeline: { PreviewData.entry(.suggested) }
#Preview("Medium · waiting for Mom", as: .systemMedium) { GoldenHourWidget() } timeline: { PreviewData.entry(.waiting) }
#Preview("Medium · confirmed", as: .systemMedium) { GoldenHourWidget() } timeline: { PreviewData.entry(.confirmed) }
#Preview("Medium · busy", as: .systemMedium) { GoldenHourWidget() } timeline: { PreviewData.entry(.busy) }
#Preview("Medium · unknown", as: .systemMedium) { GoldenHourWidget() } timeline: { PreviewData.entry(.unknown) }
#Preview("Medium · long names", as: .systemMedium) { GoldenHourWidget() } timeline: { PreviewData.entry(.longNames) }
#Preview("Medium · stale", as: .systemMedium) { GoldenHourWidget() } timeline: { PreviewData.entry(.stale) }
#Preview("Medium · empty", as: .systemMedium) { GoldenHourWidget() } timeline: { PreviewData.entry(.empty) }
#Preview("Small", as: .systemSmall) { GoldenHourWidget() } timeline: { PreviewData.entry(.suggested) }
#Preview("Small · waiting", as: .systemSmall) { GoldenHourWidget() } timeline: { PreviewData.entry(.waiting) }
#Preview("Large", as: .systemLarge) { GoldenHourWidget() } timeline: { PreviewData.entry(.confirmed) }
#Preview("Lock · rectangular", as: .accessoryRectangular) { GoldenHourWidget() } timeline: { PreviewData.entry(.confirmed) }
#Preview("Lock · circular", as: .accessoryCircular) { GoldenHourWidget() } timeline: { PreviewData.entry(.confirmed) }
#Preview("Lock · inline", as: .accessoryInline) { GoldenHourWidget() } timeline: { PreviewData.entry(.suggested) }

// Dark mode: toggle the appearance in Xcode's preview canvas; colors in Shared/Theme.swift are dynamic.

#Preview("Live Activity", as: .content,
         using: GoldenHourActivityAttributes(proposalID: "p-preview-0", personID: "mom", personName: "Mom", scheduledLabel: "Today, 8:30 PM")) {
    GoldenHourLiveActivity()
} contentStates: {
    GoldenHourActivityAttributes.ContentState(callStart: .now.addingTimeInterval(1800), booking: .confirmed, otherLocalTimeLabel: "Tomorrow, 10:30 AM for Mom")
    GoldenHourActivityAttributes.ContentState(callStart: .now.addingTimeInterval(1800), booking: .canceled, otherLocalTimeLabel: "")
}
