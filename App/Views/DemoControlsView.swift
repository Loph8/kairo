import SwiftUI
import KairoCore

/// Presenter tools. Everything here is simulation and is labeled as such.
struct DemoControlsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.state
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = model.effectiveNow(ctx.date)
            List {
                Section {
                    Label("Simulation controls. Not part of the product.", systemImage: "flask").foregroundStyle(GH.amber)
                    if let me = model.viewer {
                        Text("Demo clock: \(TimeKit.describe(now, in: me.timeZone, reference: now, use24Hour: s.settings.use24Hour)) · \(me.city)")
                    }
                }
                Section("Active family member") {
                    Picker("Acting as", selection: Binding(get: { s.viewerID }, set: { id in Task { await model.perform { try await model.repo.switchViewer(id) } } })) {
                        ForEach(s.people) { Text($0.name).tag($0.id) }
                    }.pickerStyle(.menu)
                    if let p = pendingForOther {
                        Button("Confirm as \(p.other.name) (second participant)") {
                            Task { await model.perform { _ = try await model.repo.confirm(proposalID: p.proposal.id, as: p.other.id) } }
                        }
                    } else { Text("No proposal is waiting on the other participant.").font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Demo clock") {
                    ForEach([("+1 hour", 3600.0), ("+6 hours", 21600.0), ("+1 day", 86400.0)], id: \.0) { l, secs in
                        Button(l) { Task { await model.perform { try await model.repo.advanceClock(by: secs) } } }
                    }
                    if let next = s.proposals.filter({ $0.status == .confirmed }).sorted(by: { $0.start < $1.start }).first {
                        Button("Advance to call time") { Task { await model.perform { try await model.repo.advanceClock(to: next.start) } } }
                    }
                }
                Section("Connectivity") {
                    Toggle("Simulate offline", isOn: Binding(get: { s.settings.simulateOffline }, set: { v in Task { await model.perform { try await model.repo.setSimulatedOffline(v) } } }))
                    Text("Offline changes are saved locally and counted as not synced. There is no real backend in demo mode.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Data") {
                    Button("Reset seeded history", role: .destructive) { Task { await model.perform { try await model.repo.resetDemo() } } }
                }
                Section("Decision log (tool actions and outcomes only)") {
                    ForEach(s.log.suffix(25).reversed()) { e in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.kind.rawValue.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(GH.amber)
                            Text(e.text).font(.caption)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(GH.sunrise.ignoresSafeArea())
            .navigationTitle("Demo controls")
        }
    }

    var pendingForOther: (proposal: Proposal, other: Person)? {
        let s = model.state
        for p in s.proposals where p.status == .pending && p.confirmations[s.viewerID] != nil {
            if let oid = p.participants.first(where: { $0 != s.viewerID && p.confirmations[$0] == nil }), let o = s.person(oid) { return (p, o) }
        }
        return nil
    }
}
