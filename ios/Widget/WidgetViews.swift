import WidgetKit
import SwiftUI
import AppIntents
import GoldenHourCore

// MARK: - Helpers

extension GoldenEntry {
    func level(_ p: WidgetPerson) -> AvailabilityLevel { snapshot?.level(of: p.id, at: now) ?? .learning }
    func time(_ p: WidgetPerson) -> String {
        TimeKit.formatTime(now, p.timeZone, use24Hour: snapshot?.use24Hour ?? false)
    }
    var focus: WidgetPerson? {
        guard let s = snapshot else { return nil }
        return s.people.first { $0.id == (selectedID ?? s.focusPersonID) } ?? s.people.first
    }
    var next: WidgetProposal? { snapshot?.nextProposal(for: focus?.id) }
    func yourTime(_ d: Date) -> String {
        guard let s = snapshot else { return "" }
        return TimeKit.describe(d, in: s.viewerTimeZone, reference: now, use24Hour: s.use24Hour)
    }
    func theirTime(_ d: Date, _ p: WidgetPerson) -> String {
        TimeKit.describe(d, in: p.timeZone, reference: now, use24Hour: snapshot?.use24Hour ?? false)
    }
    func a11y(_ p: WidgetPerson) -> String { "\(p.relationship), \(time(p)) in \(p.city), \(level(p).label)" }
    /// Real-clock target for system timer rendering (demo offset removed).
    func realTarget(_ d: Date) -> Date { d.addingTimeInterval(-(snapshot?.clockOffset ?? 0)) }
}

struct FreshnessLabel: View {
    let entry: GoldenEntry
    var body: some View {
        if let s = entry.snapshot {
            if case .offlinePending = s.sync {
                Label("Offline", systemImage: "icloud.slash").labelStyle(.titleAndIcon)
            } else if entry.isStale {
                Label("Estimates may be old", systemImage: "clock.badge.exclamationmark")
            } else if s.isDemo {
                Text("Demo")
            }
        }
    }
}

struct WidgetHeader: View {
    let entry: GoldenEntry
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sun.horizon.fill").foregroundStyle(GH.apricot).widgetAccentable()
            Text("Kairos").font(.caption.weight(.semibold)).foregroundStyle(GH.ink)
            Spacer(minLength: 4)
            FreshnessLabel(entry: entry).font(.system(size: 9, weight: .medium)).foregroundStyle(GH.inkSoft)
        }
    }
}

/// Book / waiting / booked control for the next proposal. Real App Intent button where actionable.
struct BookControl: View {
    let entry: GoldenEntry
    let proposal: WidgetProposal
    var body: some View {
        switch proposal.state {
        case .suggested, .awaitingYou:
            Button(intent: BookProposalIntent(proposalID: proposal.id)) {
                Label(proposal.state == .awaitingYou ? "Confirm" : "Join", systemImage: "calendar.badge.plus")
            }
        case .awaitingOther:
            Label("Waiting for \(proposal.personName)", systemImage: "hourglass").foregroundStyle(GH.amber)
        case .confirmed:
            Link(destination: DeepLink.proposal(proposal.id).url) { Label("We'll be there", systemImage: "checkmark.seal.fill") }
                .foregroundStyle(GH.green)
        default:
            Link(destination: DeepLink.schedule.url) { Label("Schedule", systemImage: "calendar") }
        }
    }
}

struct BusyControl: View {
    let entry: GoldenEntry
    var body: some View {
        if let until = entry.snapshot?.busyUntil, until > entry.now, let s = entry.snapshot {
            Button(intent: ClearBusyIntent()) {
                Label("Busy · until \(TimeKit.formatTime(until, s.viewerTimeZone, use24Hour: s.use24Hour))", systemImage: "xmark.circle")
            }
        } else {
            Button(intent: BusyIntent(minutes: 60)) { Label("Busy", systemImage: "moon.zzz") }
        }
    }
}

struct EmptyStateView: View {
    let status: EntryStatus
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "sun.horizon.fill").font(.title2).foregroundStyle(GH.apricot).widgetAccentable()
            Text(title).font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
            Text(detail).font(.caption2).foregroundStyle(GH.inkSoft).multilineTextAlignment(.center)
        }
        .foregroundStyle(GH.ink)
        .widgetURL(DeepLink.dashboard.url)
    }
    var title: String {
        switch status {
        case .empty: return "Find a little time together"
        case .unavailable: return "Shared data unavailable"
        case .corrupted: return "Couldn't read saved data"
        case .unsupported: return "Update Kairos"
        case .ok: return "No family yet"
        }
    }
    var detail: String {
        switch status {
        case .empty: return "Open Kairos to set up your family."
        case .unavailable: return "Open the app. Widgets can't reach the App Group."
        case .corrupted: return "Open the app to rebuild the widget."
        case .unsupported: return "This widget needs a newer app version."
        case .ok: return "Add or invite someone in the app."
        }
    }
}

// MARK: - Medium (hero)

struct MediumView: View {
    let entry: GoldenEntry
    var body: some View {
        if let s = entry.snapshot, !s.people.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                WidgetHeader(entry: entry)
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(s.people.prefix(3)) { p in
                            WidgetMemberRow(entry: entry, person: p)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    NextBlock(entry: entry).frame(width: 118, alignment: .leading)
                }
                HStack(spacing: 6) {
                    if let p = entry.focus {
                        Link(destination: DeepLink.call(p.id).url) { Label("Call", systemImage: "phone.fill") }
                    }
                    if let n = entry.next { BookControl(entry: entry, proposal: n) }
                    BusyControl(entry: entry)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered).tint(GH.apricot).controlSize(.mini)
                .lineLimit(1).minimumScaleFactor(0.7)
            }
        } else {
            EmptyStateView(status: entry.status == .ok ? .ok : entry.status)
        }
    }
}

struct WidgetMemberRow: View {
    let entry: GoldenEntry
    let person: WidgetPerson
    var body: some View {
        HStack(spacing: 5) {
            Avatar(initials: person.initials, size: 20)
            Text("\(person.relationship) · \(person.city)").font(.caption2.weight(.medium))
                .lineLimit(1).truncationMode(.tail).foregroundStyle(GH.ink)
            Spacer(minLength: 2)
            Text(entry.time(person)).font(.caption2.monospacedDigit()).foregroundStyle(GH.inkSoft).lineLimit(1)
            AvailabilityBadge(level: entry.level(person), compact: true).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.a11y(person))
        .widgetURL(nil)
    }
}

struct NextBlock: View {
    let entry: GoldenEntry
    var body: some View {
        if let p = entry.focus, let n = entry.next {
            VStack(alignment: .leading, spacing: 2) {
                Text("Next with \(p.relationship)").font(.caption2.weight(.semibold)).foregroundStyle(GH.amber)
                Text(entry.yourTime(n.start)).font(.footnote.weight(.bold)).foregroundStyle(GH.ink)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text("\(entry.theirTime(n.start, p)) for \(p.relationship)").font(.system(size: 10))
                    .foregroundStyle(GH.inkSoft).lineLimit(2)
            }
            .padding(6).background(RoundedRectangle(cornerRadius: 10).fill(GH.peach.opacity(0.45)))
            .widgetURL(DeepLink.proposal(n.id).url)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("No suggestion yet").font(.caption2.weight(.semibold)).foregroundStyle(GH.inkSoft)
                Text("Open the app to find a time.").font(.system(size: 10)).foregroundStyle(GH.inkSoft)
            }
        }
    }
}

// MARK: - Small (also the StandBy-friendly layout: large local time, high contrast)

struct SmallView: View {
    let entry: GoldenEntry
    var body: some View {
        if let p = entry.focus, entry.snapshot != nil {
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(entry: entry)
                HStack(spacing: 6) {
                    Avatar(initials: p.initials, size: 24)
                    Text(p.relationship).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                Text(entry.time(p)).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
                    .minimumScaleFactor(0.7).lineLimit(1)
                AvailabilityBadge(level: entry.level(p))
                Spacer(minLength: 0)
                if let n = entry.next {
                    Text("Next · \(entry.yourTime(n.start))").font(.caption2.weight(.medium)).lineLimit(2)
                        .foregroundStyle(GH.inkSoft)
                    BookControl(entry: entry, proposal: n).font(.caption2.weight(.semibold))
                        .buttonStyle(.bordered).tint(GH.apricot).controlSize(.mini)
                } else {
                    Link(destination: DeepLink.call(p.id).url) { Label("Call", systemImage: "phone.fill") }
                        .font(.caption2.weight(.semibold))
                }
            }
            .foregroundStyle(GH.ink)
            .accessibilityElement(children: .contain)
        } else {
            EmptyStateView(status: entry.status)
        }
    }
}

// MARK: - Large

struct LargeView: View {
    let entry: GoldenEntry
    var body: some View {
        if let s = entry.snapshot, !s.people.isEmpty {
            let now = s.effectiveNow(real: entry.date)
            let dial = OverlapDial(snapshot: s, now: now)
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(entry: entry)
                RingClockView(dial: dial, nowHour: Self.localHour(now, s.viewerTimeZone))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.headline(dial, s, now: now))
                        .font(.subheadline.weight(.bold)).foregroundStyle(GH.ink)
                    RingKey(total: dial.total)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GH.card.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
            }
            .foregroundStyle(GH.ink)
        } else {
            EmptyStateView(status: entry.status)
        }
    }

    static func localHour(_ now: Date, _ tz: TimeZone) -> Double {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let c = cal.dateComponents([.hour, .minute], from: now)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    /// "All 4 free 7:00–8:30" or a gentle fallback; times in the viewer's zone.
    static func headline(_ dial: OverlapDial, _ s: WidgetSnapshot, now: Date) -> String {
        guard let w = dial.allFree else {
            let best = dial.counts.max() ?? 0
            return best > 1 ? "Up to \(best) of \(dial.total) free together" : "No shared time in the next day"
        }
        let tz = s.viewerTimeZone
        let from = TimeKit.formatTime(w.start, tz, use24Hour: s.use24Hour)
        let to = TimeKit.formatTime(w.end, tz, use24Hour: s.use24Hour)
        return "All \(dial.total) free \(from)–\(to)"
    }
}

// MARK: - Lock Screen accessories (purpose-built, not the Home Screen layout squeezed down)

struct AccessoryRectangularView: View {
    let entry: GoldenEntry
    var body: some View {
        if let p = entry.focus, let n = entry.next, n.state == .confirmed || n.state == .awaitingOther || n.state == .suggested || n.state == .awaitingYou {
            VStack(alignment: .leading, spacing: 1) {
                Label(n.state == .confirmed ? "Call with \(p.relationship)" : "Next with \(p.relationship)", systemImage: "sun.horizon.fill")
                    .font(.caption.weight(.semibold)).widgetAccentable()
                Text(entry.yourTime(n.start)).font(.caption)
                if n.start > entry.now {
                    Text(timerInterval: entry.date...entry.realTarget(n.start), countsDown: true).font(.caption2.monospacedDigit())
                }
                if n.state != .confirmed { Text(n.state.label(otherName: p.relationship)).font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        } else {
            VStack(alignment: .leading) {
                Label("Kairos", systemImage: "sun.horizon.fill").font(.caption.weight(.semibold)).widgetAccentable()
                Text(entry.status == .ok ? "No call planned" : "Open Kairos").font(.caption2)
            }
        }
    }
}

struct AccessoryCircularView: View {
    let entry: GoldenEntry
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let n = entry.next, n.state == .confirmed, n.start > entry.now {
                VStack(spacing: 0) {
                    Image(systemName: "phone.fill").font(.system(size: 10)).widgetAccentable()
                    Text(timerInterval: entry.date...entry.realTarget(n.start), countsDown: true, showsHours: false)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit()).multilineTextAlignment(.center)
                }
            } else if let p = entry.focus {
                VStack(spacing: 0) {
                    Image(systemName: entry.level(p).symbol).widgetAccentable()
                    Text(p.initials).font(.caption2.weight(.bold))
                }
            } else {
                Image(systemName: "sun.horizon.fill").widgetAccentable()
            }
        }
    }
}

struct AccessoryInlineView: View {
    let entry: GoldenEntry
    var body: some View {
        if let p = entry.focus, let n = entry.next {
            Label("\(p.relationship) · \(entry.yourTime(n.start))", systemImage: "sun.horizon.fill")
        } else {
            Label("Kairos", systemImage: "sun.horizon.fill")
        }
    }
}

// MARK: - Entry view

struct GoldenWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GoldenEntry
    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallView(entry: entry)
            case .systemMedium: MediumView(entry: entry)
            case .systemLarge: LargeView(entry: entry)
            case .accessoryRectangular: AccessoryRectangularView(entry: entry)
            case .accessoryCircular: AccessoryCircularView(entry: entry)
            case .accessoryInline: AccessoryInlineView(entry: entry)
            default: MediumView(entry: entry)
            }
        }
        .containerBackground(for: .widget) {
            if family.isAccessory { Color.clear } else { GH.sunrise }
        }
    }
}

extension WidgetFamily {
    var isAccessory: Bool { [.accessoryRectangular, .accessoryCircular, .accessoryInline].contains(self) }
}
