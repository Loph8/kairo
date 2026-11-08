import SwiftUI
import GoldenHourCore

/// When each person usually picks up, as one 24-hour dial.
struct InsightsView: View {
    @Environment(AppModel.self) private var model

    private var selected: ServerState.Member? {
        model.member(model.insightsMemberID ?? "") ?? model.me ?? model.members.first
    }

    var body: some View {
        GlassPage(title: "Insights") {
            if let m = selected {
                if let state = model.serverState, !ProcessInfo.processInfo.arguments.contains("--hide-agent") { AgentCard(state: state) }   // flag: screenshot the dial
                MemberChips(selectedID: m.id)
                DayDialCard(member: m, isMe: m.id == model.myMemberID)
                privacy
            } else {
                ProgressView().padding(.top, 80)
            }
        }
    }

    private var privacy: some View {
        Label("Only times are used. Never what you say.", systemImage: "lock.fill")
            .font(Night.font(13)).foregroundStyle(GH.inkSoft).padding(.horizontal, 4)
    }
}

/// A typical day for one person: gold where they usually pick up, lavender for maybe, dark when unlikely.
private struct DayDialCard: View {
    let member: ServerState.Member
    let isMe: Bool

    /// 48 half-hours of a typical day in their time zone (weekday and weekend blended).
    private var day: [String] {
        let cells = Array(member.week).map(String.init)
        guard cells.count >= 96 else { return Array(cells.prefix(48)) + Array(repeating: "R", count: max(0, 48 - cells.count)) }
        let rank = ["R": 0, "Y": 1, "G": 2]
        return (0..<48).map { i in
            let score = (rank[cells[i]] ?? 0) * 5 + (rank[cells[48 + i]] ?? 0) * 2   // weekdays count more
            return score >= 10 ? "G" : score >= 5 ? "Y" : "R"
        }
    }

    /// Longest run of likely-free half-hours, as "7:00 PM – 10:00 PM".
    private var bestWindow: String? {
        var best: (start: Int, len: Int) = (0, 0)
        var run = 0
        for i in 0..<96 {
            if day[i % 48] == "G" { run += 1; if run > best.len && run <= 48 { best = ((i - run + 1) % 48, run) } } else { run = 0 }
        }
        guard best.len > 0 else { return nil }
        return "\(Self.clock(best.start)) – \(Self.clock((best.start + best.len) % 48))"
    }

    private static func clock(_ slot: Int) -> String {
        let h = slot / 2, m = slot % 2 == 0 ? "00" : "30"
        return "\(h % 12 == 0 ? 12 : h % 12):\(m) \(h < 12 ? "AM" : "PM")"
    }

    private var nowSlot: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: member.tz) ?? .current
        let c = cal.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 2 + ((c.minute ?? 0) >= 30 ? 1 : 0)
    }

    var body: some View {
        Card {
            VStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text(isMe ? "When you pick up" : "When \(member.name) picks up")
                        .font(Night.font(20, .bold)).foregroundStyle(GH.ink)
                    Text("\(member.city) time").font(Night.font(14)).foregroundStyle(GH.inkSoft)
                }
                DayDial(cells: day, nowSlot: nowSlot)
                    .frame(width: 250, height: 250)
                if let bestWindow {
                    VStack(spacing: 4) {
                        Text("BEST TIME TO CALL").font(Night.font(12, .bold)).tracking(1.4).foregroundStyle(GH.apricot)
                        Text(bestWindow).font(Night.font(26, .bold)).foregroundStyle(GH.ink)
                            .shadow(color: GH.apricot.opacity(0.5), radius: 10)
                    }
                }
                HStack(spacing: 16) { legend("G"); legend("Y"); legend("R") }
                    .font(Night.font(13)).foregroundStyle(GH.inkSoft)
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.smooth(duration: 0.5), value: member.id)
    }

    private func legend(_ l: String) -> some View {
        HStack(spacing: 5) { Circle().fill(Pickup.color(l)).frame(width: 9, height: 9); Text(Pickup.label(l)) }
    }
}

/// 24-hour dial: midnight at the top, noon at the bottom, a glowing dot for "now".
/// Track, colored arcs and the dot all share one radius, so they sit exactly on the same ring.
private struct DayDial: View {
    let cells: [String]
    let nowSlot: Int

    private func level(_ i: Int) -> String { cells.indices.contains(i) ? cells[i] : "R" }

    /// Consecutive half-hours with the same level, drawn as one arc so there are no seams.
    private var runs: [(start: Int, end: Int, level: String)] {
        var out: [(Int, Int, String)] = []
        for i in 0..<48 {
            if let last = out.last, last.2 == level(i) { out[out.count - 1].1 = i + 1 } else { out.append((i, i + 1, level(i))) }
        }
        return out.map { (start: $0.0, end: $0.1, level: $0.2) }
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let ring = size * 0.13
            let radius = size / 2 - ring / 2 - 10          // 10pt left for the glow
            let center = CGPoint(x: size / 2, y: size / 2)
            ZStack {
                Canvas { ctx, _ in
                    func arc(_ a: Int, _ b: Int) -> Path {
                        var p = Path()
                        p.addArc(center: center, radius: radius,
                                 startAngle: .degrees(Double(a) / 48 * 360 - 90),
                                 endAngle: .degrees(Double(b) / 48 * 360 - 90), clockwise: false)
                        return p
                    }
                    let stroke = StrokeStyle(lineWidth: ring, lineCap: .butt)
                    let across = Gradient(colors: [GH.ink, GH.apricot, GH.apricot.opacity(0.8)])
                    // Unlikely: a quiet amethyst, so the whole ring has color.
                    for r in runs where r.level == "R" {
                        ctx.stroke(arc(r.start, r.end), with: .color(GH.peach.opacity(0.75)), style: stroke)
                    }
                    for r in runs where r.level == "Y" {
                        ctx.stroke(arc(r.start, r.end), with: .color(GH.amber.opacity(0.85)), style: stroke)
                    }
                    // Likely free: glowing gold, brightest at the outer edge.
                    ctx.drawLayer { gold in
                        gold.addFilter(.shadow(color: GH.apricot.opacity(0.75), radius: 8))
                        for r in runs where r.level == "G" {
                            gold.stroke(arc(r.start, r.end),
                                        with: .radialGradient(across, center: center,
                                                              startRadius: radius + ring / 2, endRadius: radius - ring / 2),
                                        style: stroke)
                        }
                    }
                }
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    let a = Double(h) / 24 * 2 * .pi - .pi / 2
                    let r = radius - ring / 2 - 14
                    Text(h == 0 ? "12a" : h == 12 ? "12p" : h < 12 ? "\(h)a" : "\(h - 12)p")
                        .font(Night.font(12, .bold)).foregroundStyle(GH.inkSoft)
                        .position(x: center.x + r * cos(a), y: center.y + r * sin(a))
                }
                let a = (Double(nowSlot) + 0.5) / 48 * 2 * .pi - .pi / 2
                Circle().fill(GH.ink)
                    .overlay(Circle().strokeBorder(GH.night.opacity(0.6), lineWidth: 2))
                    .frame(width: ring * 0.8, height: ring * 0.8)
                    .shadow(color: .white.opacity(0.8), radius: 6)
                    .position(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
                VStack(spacing: 2) {
                    Text("now").font(Night.font(12)).foregroundStyle(GH.inkSoft)
                    Text(Pickup.label(level(nowSlot)))
                        .font(Night.font(18, .bold))
                        .foregroundStyle(Pickup.color(level(nowSlot)))
                }
                .position(center)
            }
            .frame(width: size, height: size)
        }
        .accessibilityElement()
        .accessibilityLabel("Likely free about \(cells.filter { $0 == "G" }.count / 2) hours a day")
    }
}

/// Avatars across the top to switch between family members.
private struct MemberChips: View {
    @Environment(AppModel.self) private var model
    let selectedID: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(model.members) { m in
                        let on = m.id == selectedID
                        Button {
                            withAnimation(.smooth) { model.insightsMemberID = m.id }
                        } label: {
                            HStack(spacing: 8) {
                                MemberAvatar(member: m, size: 26)
                                Text(m.id == model.myMemberID ? "You" : m.name).font(Night.font(15, on ? .bold : .regular))
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(GH.ink)
                            .glassSurface(cornerRadius: 22, tint: on ? GH.apricot : nil, interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
