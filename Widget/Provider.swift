import WidgetKit
import SwiftUI
import GoldenHourCore

enum EntryStatus { case ok, empty, corrupted, unsupported, unavailable }

struct GoldenEntry: TimelineEntry {
    let date: Date                       // real clock instant WidgetKit schedules
    let snapshot: WidgetSnapshot?
    let status: EntryStatus
    let selectedID: String?

    /// Demo-adjusted time. Every displayed time in the widget derives from THIS one instant.
    var now: Date { (snapshot?.clockOffset).map { date.addingTimeInterval($0) } ?? date }
    var isStale: Bool { snapshot.map { $0.isStale(at: now) } ?? false }
}

/// Renders only from the cached snapshot. No network, no model execution at render time.
/// Refresh timing is system-controlled: entries are pre-computed, reloads are best effort.
struct GoldenProvider: AppIntentTimelineProvider {
    typealias Intent = SelectMemberIntent

    func placeholder(in context: Context) -> GoldenEntry {
        GoldenEntry(date: .now, snapshot: PreviewData.snapshot(.suggested), status: .ok, selectedID: nil)
    }

    func snapshot(for configuration: SelectMemberIntent, in context: Context) async -> GoldenEntry {
        if context.isPreview { return placeholder(in: context) }
        return Self.entry(at: .now, configuration: configuration)
    }

    func timeline(for configuration: SelectMemberIntent, in context: Context) async -> Timeline<GoldenEntry> {
        let start = Date()
        let first = Self.entry(at: start, configuration: configuration)
        var entries = [first]
        // One entry every 30 minutes for 6 hours (forecast resolution), plus proposal start times.
        var dates = (1...12).map { start.addingTimeInterval(Double($0) * 1800) }
        if let s = first.snapshot {
            dates += s.proposals.map { $0.start.addingTimeInterval(-s.clockOffset) }.filter { $0 > start && $0 < start.addingTimeInterval(6 * 3600) }
            // Forecast slot boundaries, so the "In Sync" clock flips state when a window opens or closes.
            dates += (0..<48).map { s.forecastStart.addingTimeInterval(Double($0) * 1800 - s.clockOffset) }
                .filter { $0 > start && $0 < start.addingTimeInterval(6 * 3600) }
        }
        for d in Set(dates).sorted() { entries.append(Self.entry(at: d, configuration: configuration, reuse: first)) }
        return Timeline(entries: entries, policy: .after(start.addingTimeInterval(30 * 60)))
    }

    static func entry(at date: Date, configuration: SelectMemberIntent, reuse: GoldenEntry? = nil) -> GoldenEntry {
        let sel = configuration.member?.id
        if let r = reuse { return GoldenEntry(date: date, snapshot: r.snapshot, status: r.status, selectedID: sel) }
        switch AppGroup.snapshotStore.load() {
        case .loaded(let s): return GoldenEntry(date: date, snapshot: s, status: .ok, selectedID: sel)
        case .empty: return GoldenEntry(date: date, snapshot: nil, status: .empty, selectedID: sel)
        case .corrupted: return GoldenEntry(date: date, snapshot: nil, status: .corrupted, selectedID: sel)
        case .unsupportedVersion: return GoldenEntry(date: date, snapshot: nil, status: .unsupported, selectedID: sel)
        case .unavailable: return GoldenEntry(date: date, snapshot: nil, status: .unavailable, selectedID: sel)
        }
    }
}
