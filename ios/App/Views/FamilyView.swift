import SwiftUI
import GoldenHourCore

private let slotSeconds: TimeInterval = 30 * 60

/// The home screen: the best time to call, then how likely each person is to pick up right now.
struct FamilyView: View {
    @Environment(AppModel.self) private var model
    @State private var addingFamily = false

    var body: some View {
        GlassPage(title: model.account?.familyName ?? "Family") {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                let now = model.serverNow(ctx.date)
                VStack(spacing: 18) {
                    if let s = model.serverState {
                        if let g = model.account?.groupCall, g.startedBy != model.account?.memberId {
                            GroupCallJoinCard(call: g, now: now)
                        }
                        BestTimeCard(state: s, now: now)
                        if model.others.isEmpty {
                            InviteCard()
                        } else {
                            SectionLabel(text: "Family")
                            GlassGroup(spacing: 12) {
                                VStack(spacing: 12) {
                                    ForEach(model.others) { m in
                                        MemberRow(member: m, state: s, now: now)
                                    }
                                }
                            }
                        }
                        if !s.moves.isEmpty { MovesCard(moves: s.moves) }
                        StatusCard()
                    } else {
                        ProgressView().padding(.top, 80)
                    }
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { FamilyMenu(addingFamily: $addingFamily) } }
            .sheet(isPresented: $addingFamily) {
                FamilySetupView(onDone: { addingFamily = false })
                    .background(SunriseBackground())
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

/// The hero: the best time to call, who's in it, and one Call button.
private struct BestTimeCard: View {
    @Environment(AppModel.self) private var model
    let state: ServerState
    let now: Date
    @State private var choosing: ServerState.Member?
    @State private var settingGroupLink = false

    private var when: Date? { model.bestCallTime(state, now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Best time to call", systemImage: "sun.horizon.fill")
                .font(Night.font(16, .bold)).foregroundStyle(GH.apricot)
            if let when {
                Text(when, format: .dateTime.weekday(.wide).hour().minute())
                    .font(Night.font(36, .bold)).foregroundStyle(GH.ink)
                    .shadow(color: GH.apricot.opacity(0.35), radius: 12)
                    .contentTransition(.numericText())
                HStack(spacing: 12) {
                    HStack(spacing: -10) {
                        ForEach(model.others) { m in
                            MemberAvatar(member: m, size: 34).overlay(Circle().strokeBorder(GH.night, lineWidth: 2))
                        }
                    }
                    Text(when > now ? "in \(Self.countdown(to: when, from: now))" : "Now")
                        .font(Night.font(16)).foregroundStyle(GH.inkSoft)
                }
            } else {
                Text("Finding the best time…").font(Night.font(26, .bold)).foregroundStyle(GH.ink)
            }
            callButton
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(   // the widget's "in sync" golden glow
            RadialGradient(colors: [GH.apricot.opacity(0.30), GH.apricot.opacity(0.08), .clear],
                           center: UnitPoint(x: 0.15, y: 0.0), startRadius: 0, endRadius: 360)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(GH.apricot.opacity(0.35), lineWidth: 1))
        .glassSurface(cornerRadius: 30, tint: GH.peach)
        .sheet(item: $choosing) { CallAppPicker(member: $0) }
        .sheet(isPresented: $settingGroupLink) { GroupCallSheet() }
    }

    @ViewBuilder
    private var callButton: some View {
        let label = Label("Call", systemImage: "phone.fill")
            .font(Night.font(18, .bold)).foregroundStyle(GH.night)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Capsule().fill(GH.apricot))
            .shadow(color: GH.apricot.opacity(0.45), radius: 14)
        if model.others.count == 1, let only = model.others.first {
            Button { place(only) } label: { label }.buttonStyle(.plain)
        } else {
            Menu {
                Section {
                    Button { callEveryone() } label: {
                        Label("Everyone · group call", systemImage: "person.3.fill")
                    }
                }
                Section("Just one person") {
                    ForEach(model.others) { m in
                        Button("\(m.name) · \(LocalTime.format(now, tz: m.tz))") { place(m) }
                    }
                }
                if model.account?.callLink != nil {
                    Button { settingGroupLink = true } label: { Label("Group call link", systemImage: "link") }
                }
            } label: { label }
            .disabled(model.others.isEmpty)
        }
    }

    private func callEveryone() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if !model.groupCall() { settingGroupLink = true }
    }

    private func place(_ m: ServerState.Member) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if !model.call(m) { choosing = m }
    }

    static func countdown(to d: Date, from now: Date) -> String {
        let mins = max(0, Int(d.timeIntervalSince(now) / 60))
        let days = mins / 1440, hrs = (mins % 1440) / 60, m = mins % 60
        if days > 0 { return "\(days) d, \(hrs) hr" }
        if hrs > 0 { return "\(hrs) hr, \(m) min" }
        return "\(m) min"
    }
}

/// One family member: how likely they are to pick up right now, big, then the next 12 hours as a soft line.
private struct MemberRow: View {
    @Environment(AppModel.self) private var model
    let member: ServerState.Member
    let state: ServerState
    let now: Date
    @State private var choosingApp = false

    private var slot: Int { max(0, Int(now.timeIntervalSince(state.forecastStart) / slotSeconds)) }
    private var level: String { member.levels.indices.contains(slot) ? member.levels[slot] : "R" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                FlagAvatar(member: member, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(member.name).font(Night.font(20, .bold)).foregroundStyle(GH.ink)
                    Text("\(member.city) · \(LocalTime.format(now, tz: member.tz))")
                        .font(Night.font(15)).foregroundStyle(GH.inkSoft)
                }
                Spacer()
                callButton
            }
            StatusGlow(level: level)
                .frame(height: 30)
        }
        .padding(18)
        .glassSurface(cornerRadius: 26, interactive: true)
        .contentShape(Rectangle())
        .onTapGesture { model.insightsMemberID = member.id; model.tab = .insights }
        .animation(.smooth, value: level)
        .sheet(isPresented: $choosingApp) { CallAppPicker(member: member) }
        #if DEBUG
        .task {   // screenshots only: --call-picker=<name> opens the picker without a tap
            if ProcessInfo.processInfo.arguments.contains("--call-picker=\(member.name)") { choosingApp = true }
        }
        #endif
    }

    private var callButton: some View {
        Button {
            if !model.call(member) { choosingApp = true }
        } label: {
            Image(systemName: model.callChoice(for: member)?.app.symbol ?? "phone.fill")
                .font(Night.font(18, .bold)).frame(width: 44, height: 36)
        }
        .secondaryGlassButton()
        .controlSize(.small)
        .contextMenu {
            Button("Call with…", systemImage: "arrow.triangle.swap") { choosingApp = true }
        }
        .accessibilityLabel("Call \(member.name)\(model.callChoice(for: member).map { " on \($0.app.name)" } ?? "")")
        .accessibilityHint("Touch and hold to choose the app")
    }
}

/// "Likely free" / "Maybe" / "Unlikely", large and glowing in its color.
struct StatusGlow: View {
    let level: String
    var size: CGFloat = 26
    var body: some View {
        let c = Pickup.color(level)
        Label(Pickup.label(level), systemImage: Pickup.symbol(level))
            .font(Night.font(size, .bold))
            .foregroundStyle(level == "R" ? GH.inkSoft : c)
            .shadow(color: c.opacity(level == "R" ? 0 : 0.45), radius: 6)
            .contentTransition(.symbolEffect(.replace))
    }
}

/// Avatar with the person's country as a round flag badge on its corner.
struct FlagAvatar: View {
    let member: ServerState.Member
    var size: CGFloat = 52
    var body: some View {
        let badge = size * 0.42
        MemberAvatar(member: member, size: size)
            .overlay(alignment: .bottomTrailing) {
                Text(LocalTime.flag(for: member.tz))
                    .font(.system(size: badge * 1.35))
                    .frame(width: badge, height: badge)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(GH.night, lineWidth: 2))
                    .offset(x: 4, y: 4)
                    .accessibilityHidden(true)
            }
    }
}

/// Shown when you're the only one in the family yet.
private struct InviteCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Bring your family in", systemImage: "person.2.fill").font(Night.font(17, .bold)).foregroundStyle(GH.ink)
                Text("Share this code. They download Kairos, sign in, and tap Join.")
                    .font(Night.font(15)).foregroundStyle(GH.inkSoft)
                if let code = model.account?.inviteCode {
                    HStack {
                        Text(code).font(Night.font(34, .bold)).tracking(6).foregroundStyle(GH.ink)
                        Spacer()
                        ShareLink(item: "Join our family on Kairos with code \(code)") {
                            Image(systemName: "square.and.arrow.up").font(Night.font(20, .bold))
                        }
                    }
                }
            }
        }
    }
}

/// Calendar events the AI suggests moving to open a better time for everyone.
private struct MovesCard: View {
    @Environment(AppModel.self) private var model
    let moves: [ServerState.Move]
    var body: some View {
        Card(tint: GH.peach) {
            VStack(alignment: .leading, spacing: 12) {
                Label("A better time is possible", systemImage: "calendar.badge.clock").font(Night.font(17, .bold)).foregroundStyle(GH.ink)
                ForEach(moves.prefix(2), id: \.blockId) { mv in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Move your \(mv.from, format: .dateTime.hour().minute()) event to \(mv.to, format: .dateTime.hour().minute()) and everyone is free at \(mv.frees, format: .dateTime.weekday().hour().minute()).")
                            .font(Night.font(15)).foregroundStyle(GH.ink)
                        Button("Move it and book") { Task { await model.approveMove(mv) } }
                            .secondaryGlassButton().controlSize(.small)
                    }
                }
            }
        }
    }
}

/// Quick labels that teach the AI directly, same as the widget buttons.
private struct StatusCard: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("How's right now?").font(Night.font(17, .bold)).foregroundStyle(GH.ink)
                HStack(spacing: 10) {
                    Button { Task { await model.markFree() } } label: {
                        Label("I'm free", systemImage: "sun.max.fill").frame(maxWidth: .infinity)
                    }
                    .secondaryGlassButton()
                    Button { Task { await model.markBusy() } } label: {
                        Label("I'm busy", systemImage: "pause.circle.fill").frame(maxWidth: .infinity)
                    }
                    .secondaryGlassButton()
                }
                .disabled(model.working)
            }
        }
    }
}

/// Top-right menu on the Family tab: switch between your families, or add another one.
private struct FamilyMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var addingFamily: Bool

    var body: some View {
        let families = model.account?.allFamilies ?? []
        Menu {
            if families.count > 1 {
                Section("Your families") {
                    ForEach(families) { f in
                        Button { Task { await model.switchFamily(f.familyId) } } label: {
                            if f.familyId == model.account?.familyId {
                                Label(f.familyName, systemImage: "checkmark")
                            } else {
                                Text(f.familyName)
                            }
                        }
                    }
                }
            }
            Button { addingFamily = true } label: {
                Label("Join or start another family", systemImage: "plus")
            }
        } label: {
            Label("Families", systemImage: families.count > 1 ? "house.and.flag.fill" : "plus.circle")
        }
        .disabled(model.working)
        .accessibilityLabel("Switch or add a family")
    }
}

/// "Mom started a group call · Join": shown to everyone else for 45 minutes after someone opens the family call.
private struct GroupCallJoinCard: View {
    @Environment(AppModel.self) private var model
    let call: GroupCall
    let now: Date

    var body: some View {
        let who = model.member(call.startedBy)?.name ?? "Someone"
        let mins = max(0, Int(now.timeIntervalSince(call.at) / 60))
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill").font(.system(size: 20)).foregroundStyle(GH.night)
                .frame(width: 44, height: 44).background(Circle().fill(GH.green))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(who) started a group call").font(Night.font(16, .bold)).foregroundStyle(GH.ink)
                Text(mins == 0 ? "Just now" : "\(mins) min ago").font(Night.font(13)).foregroundStyle(GH.inkSoft)
            }
            Spacer(minLength: 8)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                _ = model.groupCall()
            } label: {
                Text("Join").font(Night.font(16, .bold)).foregroundStyle(GH.night)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(GH.green))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .glassSurface(cornerRadius: 24, tint: GH.green)
        .accessibilityElement(children: .combine)
    }
}
