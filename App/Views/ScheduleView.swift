import SwiftUI
import GoldenHourCore

struct ScheduleView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let now = model.effectiveNow(ctx.date)
            let mine = model.state.proposals.filter { $0.participants.contains(model.state.viewerID) }
            let upcoming = mine.filter { $0.status == .confirmed }.sorted { $0.start < $1.start }
            let pending = mine.filter { $0.status.isOpen }.sorted { $0.start < $1.start }
            let past = mine.filter { !$0.status.isOpen && $0.status != .confirmed }.sorted { $0.start > $1.start }.prefix(6)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let b = model.banner { BannerView(text: b) }
                    section("Upcoming calls", upcoming, now, empty: "No confirmed calls yet.")
                    section("Pending proposals", pending, now, empty: "No proposals waiting.")
                    if !past.isEmpty { section("Earlier", Array(past), now, empty: "") }
                }.padding(16)
            }
            .background(GH.sunrise.ignoresSafeArea())
            .navigationTitle("Schedule")
        }
    }

    @ViewBuilder func section(_ title: String, _ list: [Proposal], _ now: Date, empty: String) -> some View {
        Text(title).font(.headline).foregroundStyle(GH.ink)
        if list.isEmpty { Text(empty).font(.subheadline).foregroundStyle(GH.inkSoft) }
        ForEach(list) { ProposalCard(proposal: $0, now: now) }
    }
}

/// One card per proposal ID. Shows both participants' local times, viewer-relative state, and only the
/// actions valid in that state. Book/Confirm only ever confirms the VIEWER's side.
struct ProposalCard: View {
    @Environment(AppModel.self) private var model
    let proposal: Proposal
    let now: Date

    var body: some View {
        let s = model.state
        let me = s.viewerID
        let state = proposal.viewerState(me)
        let others = proposal.participants.filter { $0 != me }.compactMap { s.person($0) }
        let otherName = others.first?.relationship ?? "them"
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(state.label(otherName: otherName), systemImage: state.symbol)
                    .font(.subheadline.weight(.bold)).foregroundStyle(tint(state))
                ForEach(proposal.participants, id: \.self) { id in
                    if let p = s.person(id) {
                        HStack {
                            Text(id == me ? "You" : p.relationship).font(.subheadline.weight(.semibold))
                            if proposal.confirmations[id] != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(GH.green).accessibilityLabel("confirmed") }
                            Spacer()
                            Text(TimeKit.describe(proposal.start, in: p.timeZone, reference: now, use24Hour: s.settings.use24Hour))
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
                if !proposal.explanation.isEmpty {
                    Text(proposal.explanation).font(.caption).foregroundStyle(GH.inkSoft)
                }
                actions(state, otherName)
            }.foregroundStyle(GH.ink)
        }
        .accessibilityElement(children: .contain)
    }

    func tint(_ s: ViewerBookingState) -> Color {
        switch s {
        case .confirmed, .completed: return GH.green
        case .declined, .expired, .canceled: return GH.red
        default: return GH.amber
        }
    }

    @ViewBuilder func actions(_ state: ViewerBookingState, _ otherName: String) -> some View {
        switch state {
        case .suggested:
            Button { Task { await model.confirm(proposal.id) } } label: { Label("Book this time", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
            Button("Not this one", role: .destructive) { Task { await model.decline(proposal.id) } }.font(.footnote)
        case .awaitingYou:
            HStack {
                Button { Task { await model.confirm(proposal.id) } } label: { Label("Confirm", systemImage: "checkmark").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                Button("Decline", role: .destructive) { Task { await model.decline(proposal.id) } }.buttonStyle(.bordered)
            }
        case .awaitingOther:
            Text("Your confirmation is saved. This is only booked once \(otherName) confirms too.").font(.footnote).foregroundStyle(GH.inkSoft)
            Button("Cancel", role: .destructive) { Task { await model.cancel(proposal.id) } }.font(.footnote)
        case .confirmed:
            HStack {
                Button { if let other = proposal.participants.first(where: { $0 != model.state.viewerID }) { model.openCall(personID: other, proposalID: proposal.id) } } label: { Label("Open call", systemImage: "phone.fill") }
                    .buttonStyle(.borderedProminent)
                Button("Reschedule") { Task { await model.reschedule(proposal.id) } }.buttonStyle(.bordered)
                Button("Cancel", role: .destructive) { Task { await model.cancel(proposal.id) } }.buttonStyle(.bordered)
            }.font(.footnote)
        case .expired:
            Text("This time passed or became stale. Fresh suggestions are on the Family tab.").font(.footnote).foregroundStyle(GH.inkSoft)
        case .declined, .canceled, .completed:
            EmptyView()
        }
    }
}
