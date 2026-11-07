import SwiftUI
import GoldenHourCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Re-evaluates every minute so local times and "now" stay current.
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = model.effectiveNow(ctx.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let b = model.banner { BannerView(text: b) }
                    if let n = model.liveActivityNote { BannerView(text: n) }
                    header
                    if model.others.isEmpty { emptyState } else {
                        busyCard(now)
                        ForEach(model.others) { p in
                            NavigationLink(value: DeepLink.member(p.id)) { MemberCard(person: p, now: now) }.buttonStyle(.plain)
                        }
                        nextSection(now)
                    }
                }
                .padding(16)
            }
            .background(GH.sunrise.ignoresSafeArea())
            .navigationTitle("Golden Hour")
            .navigationDestination(for: DeepLink.self) { link in
                if case .member(let id) = link, let p = model.state.person(id) { MemberDetailView(person: p) }
            }
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Find a little time together.").font(.title3.weight(.semibold)).foregroundStyle(GH.ink)
            if let me = model.viewer {
                Text("You're \(me.name) in \(me.city)").font(.subheadline).foregroundStyle(GH.inkSoft)
            }
            Label(model.state.settings.simulateOffline
                  ? SyncStatus.offlinePending(model.state.settings.pendingSyncCount).label : SyncStatus.localOnly.label,
                  systemImage: model.state.settings.simulateOffline ? "icloud.slash" : "internaldrive")
                .font(.caption).foregroundStyle(GH.inkSoft)
            if model.state.isDemo {
                Label("Demo family · synthetic history", systemImage: "flask").font(.caption).foregroundStyle(GH.amber)
            }
        }
    }

    var emptyState: some View {
        Card {
            VStack(spacing: 8) {
                Image(systemName: "person.2.slash").font(.largeTitle).foregroundStyle(GH.apricot)
                Text("No family yet").font(.headline)
                Text("Invitations are deferred in this build. Load the demo family from Settings → Demo controls.")
                    .font(.subheadline).foregroundStyle(GH.inkSoft).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
        }
    }

    func busyCard(_ now: Date) -> some View {
        Card {
            if let b = model.myBusy, let me = model.viewer {
                VStack(alignment: .leading, spacing: 8) {
                    Label("You're Busy until \(TimeKit.formatTime(b.end, me.timeZone, use24Hour: model.state.settings.use24Hour))",
                          systemImage: "moon.zzz.fill").font(.subheadline.weight(.semibold)).foregroundStyle(GH.red)
                    Text("This overrides any estimate until it ends.").font(.caption).foregroundStyle(GH.inkSoft)
                    HStack {
                        Button("Clear") { Task { await model.clearBusy() } }
                        Menu("Change") {
                            ForEach([30, 60, 120, 240], id: \.self) { m in
                                Button("\(m >= 60 ? "\(m / 60) hr" : "\(m) min")") { Task { await model.setBusy(minutes: m, replace: true) } }
                            }
                        }
                    }.buttonStyle(.bordered)
                }
            } else {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Need quiet?").font(.subheadline.weight(.semibold))
                        Text("Set Busy for an hour. Everyone sees you're unavailable.").font(.caption).foregroundStyle(GH.inkSoft)
                    }
                    Spacer()
                    Button { Task { await model.setBusy() } } label: { Label("Busy 1 hr", systemImage: "moon.zzz") }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    @ViewBuilder func nextSection(_ now: Date) -> some View {
        let open = model.state.proposals.filter { $0.participants.contains(model.state.viewerID) && ($0.status.isOpen || $0.status == .confirmed) }
            .sorted { $0.start < $1.start }
        if !open.isEmpty {
            Text("Next connection").font(.headline).foregroundStyle(GH.ink)
            ForEach(open.prefix(3)) { ProposalCard(proposal: $0, now: now) }
        }
    }
}

struct MemberCard: View {
    @Environment(AppModel.self) private var model
    let person: Person
    let now: Date

    var body: some View {
        let est = model.repo.estimate(person.id, at: now)
        let level = est?.level ?? .learning
        Card {
            HStack(spacing: 12) {
                Avatar(initials: person.initials, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(person.name).font(.headline).lineLimit(1)
                        if let f = person.flag { Text(f).accessibilityHidden(true) }   // decorative only
                    }
                    Text("\(TimeKit.dayLabel(now, reference: model.effectiveNow(), in: person.timeZone)) · \(person.city)")
                        .font(.caption).foregroundStyle(GH.inkSoft).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(TimeKit.formatTime(now, person.timeZone, use24Hour: model.state.settings.use24Hour))
                        .font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                    AvailabilityBadge(level: level)
                }
            }
            .foregroundStyle(GH.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(person.name), \(TimeKit.formatTime(now, person.timeZone, use24Hour: model.state.settings.use24Hour)) in \(person.city), \(level.label)")
        .accessibilityHint("Opens details")
    }
}
