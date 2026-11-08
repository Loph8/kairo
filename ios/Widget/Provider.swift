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
        // Backend mode: pull the family's latest times first. On failure the last saved snapshot is shown.
        _ = try? await AppBackend.refresh()
        let first = Self.entry(at: start, configuration: configuration)
        var entries = [first]
        // One entry at the start of every minute, so the family's local clocks tick like the app's,
        // plus proposal start times. WidgetKit doesn't charge reload budget for entries.
        let nextMinute = (start.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60 + 60
        let horizon = start.addingTimeInterval(Self.clockHorizon)
        var dates = (0..<Int(Self.clockHorizon / 60)).map { Date(timeIntervalSinceReferenceDate: nextMinute + Double($0) * 60) }
        if let s = first.snapshot {
            dates += s.proposals.map { $0.start.addingTimeInterval(-s.clockOffset) }.filter { $0 > start && $0 < horizon }
        }
        for d in Set(dates).sorted() { entries.append(Self.entry(at: d, configuration: configuration, reuse: first)) }
        // Fetch the family's latest times again in 15 minutes (iOS may stretch this; the clock keeps ticking meanwhile).
        return Timeline(entries: entries, policy: .after(start.addingTimeInterval(Self.serverRefresh)))
    }

    /// How far ahead minute-by-minute clock entries are prepared.
    static let clockHorizon: TimeInterval = 3 * 3600
    /// How often the widget asks the server for new times and suggestions.
    static let serverRefresh: TimeInterval = 15 * 60

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
