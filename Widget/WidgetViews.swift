import WidgetKit
import SwiftUI
import AppIntents
import KairoCore

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
            Image(systemName: "sun.horizon.fill").foregroundStyle(Palette.apricot).widgetAccentable()
            Text("Kairo").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink)
            Spacer(minLength: 4)
            FreshnessLabel(entry: entry).font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.inkSoft)
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
                Label(proposal.state == .awaitingYou ? "Confirm" : "Book", systemImage: "calendar.badge.plus")
            }
        case .awaitingOther:
            Label("Waiting for \(proposal.personName)", systemImage: "hourglass").foregroundStyle(Palette.amber)
        case .confirmed:
            Link(destination: DeepLink.proposal(proposal.id).url) { Label("Booked", systemImage: "checkmark.seal.fill") }
                .foregroundStyle(Palette.green)
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
            Image(systemName: "sun.horizon.fill").font(.title2).foregroundStyle(Palette.apricot).widgetAccentable()
            Text(title).font(.footnote.weight(.semibold)).multilineTextAlignment(.center)
            Text(detail).font(.caption2).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
        }
        .foregroundStyle(Palette.ink)
        .widgetURL(DeepLink.dashboard.url)
    }
    var title: String {
        switch status {
        case .empty: return "Find a little time together"
        case .unavailable: return "Shared data unavailable"
        case .corrupted: return "Couldn't read saved data"
        case .unsupported: return "Update Kairo"
        case .ok: return "No family yet"
        }
    }
    var detail: String {
        switch status {
        case .empty: return "Open Kairo to set up your family."
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
                            MemberRow(entry: entry, person: p)
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
                .buttonStyle(.bordered).tint(Palette.apricot).controlSize(.mini)
                .lineLimit(1).minimumScaleFactor(0.7)
            }
        } else {
            EmptyStateView(status: entry.status == .ok ? .ok : entry.status)
        }
    }
}

struct MemberRow: View {
    let entry: GoldenEntry
    let person: WidgetPerson
    var body: some View {
        HStack(spacing: 5) {
            Avatar(initials: person.initials, size: 20)
            Text("\(person.relationship) · \(person.city)").font(.caption2.weight(.medium))
                .lineLimit(1).truncationMode(.tail).foregroundStyle(Palette.ink)
            Spacer(minLength: 2)
            Text(entry.time(person)).font(.caption2.monospacedDigit()).foregroundStyle(Palette.inkSoft).lineLimit(1)
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
                Text("Next with \(p.relationship)").font(.caption2.weight(.semibold)).foregroundStyle(Palette.amber)
                Text(entry.yourTime(n.start)).font(.footnote.weight(.bold)).foregroundStyle(Palette.ink)
                    .lineLimit(2).minimumScaleFactor(0.8)
                Text("\(entry.theirTime(n.start, p)) for \(p.relationship)").font(.system(size: 10))
                    .foregroundStyle(Palette.inkSoft).lineLimit(2)
            }
            .padding(6).background(RoundedRectangle(cornerRadius: 10).fill(Palette.peach.opacity(0.45)))
            .widgetURL(DeepLink.proposal(n.id).url)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("No suggestion yet").font(.caption2.weight(.semibold)).foregroundStyle(Palette.inkSoft)
                Text("Open the app to find a time.").font(.system(size: 10)).foregroundStyle(Palette.inkSoft)
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
                        .foregroundStyle(Palette.inkSoft)
                    BookControl(entry: entry, proposal: n).font(.caption2.weight(.semibold))
                        .buttonStyle(.bordered).tint(Palette.apricot).controlSize(.mini)
                } else {
                    Link(destination: DeepLink.call(p.id).url) { Label("Call", systemImage: "phone.fill") }
                        .font(.caption2.weight(.semibold))
                }
            }
            .foregroundStyle(Palette.ink)
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
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(entry: entry)
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(s.people.prefix(5)) { MemberRow(entry: entry, person: $0).font(.footnote) }
                }
                Divider()
                if let p = entry.focus {
                    Text("Suggested times with \(p.relationship)").font(.caption.weight(.semibold)).foregroundStyle(Palette.amber)
                    let list = s.proposals.filter { $0.personID == p.id && [.suggested, .awaitingYou, .awaitingOther, .confirmed].contains($0.state) }
                        .sorted { $0.start < $1.start }.prefix(3)
                    if list.isEmpty {
                        Text("No suggestions right now. Open the app to refresh.").font(.caption).foregroundStyle(Palette.inkSoft)
                    }
                    ForEach(Array(list)) { w in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.yourTime(w.start)).font(.footnote.weight(.semibold))
                                Text("\(entry.theirTime(w.start, p)) for \(p.relationship)").font(.caption2).foregroundStyle(Palette.inkSoft)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Label(w.state.label(otherName: p.relationship), systemImage: w.state.symbol)
                                    .font(.caption2.weight(.semibold)).foregroundStyle(w.state == .confirmed ? Palette.green : Palette.amber)
                                if w.state == .suggested || w.state == .awaitingYou {
                                    Button(intent: BookProposalIntent(proposalID: w.id)) { Text(w.state == .awaitingYou ? "Confirm" : "Book") }
                                        .buttonStyle(.bordered).tint(Palette.apricot).controlSize(.mini)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    if let p = entry.focus {
                        Link(destination: DeepLink.call(p.id).url) { Label("Call", systemImage: "phone.fill") }
                    }
                    BusyControl(entry: entry)
                }
                .font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(Palette.apricot).controlSize(.small)
            }
            .foregroundStyle(Palette.ink)
        } else {
            EmptyStateView(status: entry.status)
        }
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
                Label("Kairo", systemImage: "sun.horizon.fill").font(.caption.weight(.semibold)).widgetAccentable()
                Text(entry.status == .ok ? "No call planned" : "Open Kairo").font(.caption2)
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
            Label("Kairo", systemImage: "sun.horizon.fill")
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
            if family.isAccessory { Color.clear } else { Palette.sunrise }
        }
    }
}

extension WidgetFamily {
    var isAccessory: Bool { [.accessoryRectangular, .accessoryCircular, .accessoryInline].contains(self) }
}
