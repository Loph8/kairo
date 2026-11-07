import SwiftUI
import GoldenHourCore

struct MemberDetailView: View {
    @Environment(AppModel.self) private var model
    let person: Person

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = model.effectiveNow(ctx.date)
            let est = model.repo.estimate(person.id, at: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Avatar(initials: person.initials, size: 52)
                                VStack(alignment: .leading) {
                                    Text(person.name).font(.title2.weight(.bold))
                                    Text("\(person.city) · \(person.timeZoneID)").font(.caption).foregroundStyle(GH.inkSoft)
                                }
                            }
                            Text(TimeKit.describe(now, in: person.timeZone, reference: model.effectiveNow(), use24Hour: model.state.settings.use24Hour))
                                .font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                            AvailabilityBadge(level: est?.level ?? .learning)
                            if let est {
                                Text(model.repo.engine.scorer.explanation(for: est, name: person.relationship))
                                    .font(.subheadline).foregroundStyle(GH.inkSoft)
                                Text("Evidence level \(Int(est.confidence * 100))% · ranking score, not a probability")
                                    .font(.caption2).foregroundStyle(GH.inkSoft)
                            }
                        }.foregroundStyle(GH.ink)
                    }
                    Heatmap(person: person)
                    Text("Suggested shared windows").font(.headline)
                    let props = model.state.proposals.filter { $0.participants.contains(person.id) && $0.participants.contains(model.state.viewerID) && ($0.status.isOpen || $0.status == .confirmed) }.sorted { $0.start < $1.start }
                    if props.isEmpty { Text("No windows right now.").font(.subheadline).foregroundStyle(GH.inkSoft) }
                    ForEach(props) { ProposalCard(proposal: $0, now: now) }
                    HStack {
                        Button { model.openCall(personID: person.id, proposalID: model.state.proposals.first { $0.status == .confirmed && $0.participants.contains(person.id) }?.id) } label: {
                            Label("Call", systemImage: "phone.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                    }
                    Text("Only a summary of when \(person.relationship) tends to be reachable is shown. Individual calls and messages are never shown to family members.")
                        .font(.caption).foregroundStyle(GH.inkSoft)
                }.padding(16)
            }
            .background(GH.sunrise.ignoresSafeArea())
            .navigationTitle(person.relationship)
            .navigationBarTitleDisplayMode(.inline)
            .task { try? await model.repo.setFocus(person.id); await model.reload() }
        }
    }
}

/// Weekly pattern in the PERSON's local time. Color + symbol + accessibility summary, never color alone.
struct Heatmap: View {
    @Environment(AppModel.self) private var model
    let person: Person
    private let days = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        let cells = model.repo.slotModel(person.id)?.cells ?? []
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Typical week · \(person.city) time").font(.subheadline.weight(.semibold))
                if cells.count != TimeKit.slotsPerWeek {
                    Text("Still learning.").font(.caption).foregroundStyle(GH.inkSoft)
                } else {
                    HStack(spacing: 2) {
                        Text("").frame(width: 14)
                        ForEach([0, 6, 12, 18], id: \.self) { h in Text("\(h)").font(.system(size: 9)).frame(maxWidth: .infinity, alignment: .leading) }
                    }.foregroundStyle(GH.inkSoft)
                    ForEach(0..<7, id: \.self) { d in
                        HStack(spacing: 1) {
                            Text(days[d]).font(.system(size: 10, weight: .semibold)).frame(width: 14)
                            ForEach(0..<24, id: \.self) { h in cell(cells, d, h) }
                        }
                    }
                    HStack(spacing: 12) {
                        legend("checkmark", GH.green, "Often free")
                        legend("moon.fill", GH.red, "Quiet hours")
                        legend("questionmark", GH.neutral, "Learning")
                    }.font(.caption2).foregroundStyle(GH.inkSoft)
                }
            }
            .foregroundStyle(GH.ink)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly availability pattern for \(person.name). \(summary(cells))")
        }
    }

    func cell(_ cells: [SlotCell], _ d: Int, _ h: Int) -> some View {
        let a = cells[d * 48 + h * 2], b = cells[d * 48 + h * 2 + 1]
        let score = (a.score + b.score) / 2, conf = (a.confidence + b.confidence) / 2
        let quiet = person.prefs.isQuiet(minuteOfDay: h * 60 + 30)
        let (color, symbol): (Color, String?) = quiet ? (GH.red.opacity(0.25), "moon.fill")
            : conf < 0.25 ? (GH.neutral.opacity(0.18), "questionmark")
            : (GH.green.opacity(0.15 + 0.75 * score), score >= 0.62 ? "checkmark" : nil)
        return RoundedRectangle(cornerRadius: 2).fill(color).frame(height: 16)
            .overlay { if let symbol { Image(systemName: symbol).font(.system(size: 6, weight: .bold)).foregroundStyle(GH.ink.opacity(0.7)) } }
    }

    func legend(_ s: String, _ c: Color, _ t: String) -> some View {
        HStack(spacing: 3) { Image(systemName: s).foregroundStyle(c); Text(t) }
    }

    func summary(_ cells: [SlotCell]) -> String {
        guard cells.count == TimeKit.slotsPerWeek else { return "Still learning." }
        var best: [Int: Double] = [:]
        for h in 0..<24 { best[h] = (1...5).map { cells[$0 * 48 + h * 2].score }.reduce(0, +) / 5 }
        let top = best.filter { $0.value >= 0.62 }.keys.sorted()
        guard let lo = top.first, let hi = top.last else { return "No clear pattern on weekdays yet. This is an estimate." }
        return "On weekdays, most often free between \(lo):00 and \(hi + 1):00 local time. This is an estimate."
    }
}
