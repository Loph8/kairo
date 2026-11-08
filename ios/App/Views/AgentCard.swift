import SwiftUI
import GoldenHourCore

private let slotSeconds: TimeInterval = 30 * 60
private let slotsShown = 48   // the next 24 hours

/// Shows the AI at work: everyone's next 24 hours lined up, a scan sweeping across them,
/// and the hour it picked glowing where everyone's gold overlaps.
struct AgentCard: View {
    @Environment(AppModel.self) private var model
    let state: ServerState
    @State private var revealed = 0

    private var nowSlot: Int { max(0, Int(state.now.timeIntervalSince(state.forecastStart) / slotSeconds)) }

    private func lane(_ m: ServerState.Member) -> [String] {
        let rest = Array(m.levels.dropFirst(nowSlot).prefix(slotsShown))
        return rest + Array(repeating: "R", count: max(0, slotsShown - rest.count))
    }

    /// Same time the Family screen shows, so the two never disagree.
    private var picked: Date? { model.bestCallTime(state, now: state.now) }

    /// The agent's pick, as a slot in the lanes. Falls back to the slot most people are likely free.
    private var bestSlot: Int {
        if let start = picked {
            let i = Int(start.timeIntervalSince(state.forecastStart) / slotSeconds) - nowSlot
            if (0..<slotsShown).contains(i) { return i }
        }
        let score: (Int) -> Int = { i in
            state.members.reduce(0) { sum, m in
                let l = lane(m)[i]
                return sum + (l == "G" ? 2 : l == "Y" ? 1 : 0)
            }
        }
        return (0..<slotsShown).max { score($0) < score($1) } ?? 0
    }

    private var bestTime: Date {
        picked ?? state.forecastStart.addingTimeInterval(Double(nowSlot + bestSlot) * slotSeconds)
    }

    private var bestLabel: String { LocalTime.format(bestTime, tz: TimeZone.current.identifier, withDay: true) }

    private var steps: [String] {
        let signals = state.members.map(\.signals).reduce(0, +)
        let zones = Set(state.members.map(\.tz)).count
        return [
            "Learned from \(signals) calls and taps",
            "Lined up \(zones) time zones",
            "Scored \(slotsShown) half-hours for \(state.members.count) people",
            "Picked \(bestLabel), when everyone can pick up",
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            lanes
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, text in
                    if i < revealed { stepRow(text, last: i == steps.count - 1).transition(.move(edge: .leading).combined(with: .opacity)) }
                }
            }
        }
        .padding(18)
        .glassSurface(cornerRadius: 24)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(GH.apricot.opacity(0.35), lineWidth: 1))
        .task {
            revealed = 0
            for i in 1...steps.count {
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.spring(duration: 0.5)) { revealed = i }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(GH.apricot)
                .shadow(color: GH.apricot.opacity(0.8), radius: 8)
                .symbolEffect(.pulse, options: .repeating)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kairos AI").font(Night.font(19, .bold)).foregroundStyle(GH.ink)
                Text("Finding the hour everyone can pick up").font(Night.font(13)).foregroundStyle(GH.inkSoft)
            }
            Spacer()
            LiveBadge()
        }
    }

    private var lanes: some View {
        let members = state.members
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                VStack(spacing: 8) {
                    ForEach(members) { m in MemberAvatar(member: m, size: 24).frame(height: 18) }
                }
                ZStack {
                    VStack(spacing: 8) {
                        ForEach(members) { m in LaneView(levels: lane(m)).frame(height: 18) }
                    }
                    GeometryReader { geo in
                        let w = geo.size.width / CGFloat(slotsShown)
                        BestColumn(width: w * 2)
                            .position(x: w * (CGFloat(bestSlot) + 1), y: geo.size.height / 2)
                            .frame(height: geo.size.height + 12)
                        ScanBeam(height: geo.size.height + 12)
                    }
                }
            }
            HStack {
                Text("Now")
                Spacer()
                Text("+12h")
                Spacer()
                Text("+24h")
            }
            .font(Night.font(11)).foregroundStyle(GH.inkSoft)
            .padding(.leading, 34)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Everyone's next 24 hours. Kairos picked \(bestLabel).")
    }

    private func stepRow(_ text: String, last: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: last ? "star.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: last ? 18 : 15))
                .foregroundStyle(last ? GH.apricot : GH.amber)
                .shadow(color: last ? GH.apricot.opacity(0.7) : .clear, radius: 6)
            Text(text)
                .font(Night.font(last ? 15 : 14, last ? .bold : .regular))
                .foregroundStyle(last ? GH.apricot : GH.ink)
        }
    }
}

/// One person's next 24 hours. Empty slots fade back; free ones light up with a glowing gradient.
private struct LaneView: View {
    let levels: [String]
    var body: some View {
        Canvas { ctx, size in
            let w = size.width / CGFloat(levels.count)
            func rect(_ i: Int) -> CGRect { CGRect(x: CGFloat(i) * w + 0.75, y: 0, width: max(1, w - 1.5), height: size.height) }
            func cell(_ i: Int) -> Path { Path(roundedRect: rect(i), cornerRadius: 3) }
            let top = CGPoint(x: 0, y: 0), bottom = CGPoint(x: 0, y: size.height)
            for (i, l) in levels.enumerated() where l == "R" {
                ctx.fill(cell(i), with: .color(GH.ink.opacity(0.07)))
            }
            ctx.drawLayer { maybe in
                maybe.addFilter(.shadow(color: GH.amber.opacity(0.5), radius: 3))
                for (i, l) in levels.enumerated() where l == "Y" {
                    maybe.fill(cell(i), with: .linearGradient(Gradient(colors: [GH.amber, GH.amber.opacity(0.4)]),
                                                              startPoint: top, endPoint: bottom))
                }
            }
            ctx.drawLayer { gold in
                gold.addFilter(.shadow(color: GH.apricot, radius: 6))
                for (i, l) in levels.enumerated() where l == "G" {
                    gold.fill(cell(i), with: .linearGradient(Gradient(colors: [GH.ink, GH.apricot, GH.apricot.opacity(0.75)]),
                                                             startPoint: top, endPoint: bottom))
                }
            }
        }
    }
}

/// The glowing column where the agent's pick sits.
private struct BestColumn: View {
    let width: CGFloat
    @State private var glow = false
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(GH.apricot, lineWidth: 2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(GH.apricot.opacity(0.18)))
            .frame(width: max(width, 10))
            .shadow(color: GH.apricot.opacity(glow ? 0.9 : 0.4), radius: glow ? 12 : 5)
            .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever()) { glow = true } }
    }
}

/// A soft light that keeps sweeping across the lanes, so the card feels like it's thinking.
private struct ScanBeam: View {
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if !reduceMotion {
            TimelineView(.animation) { tl in
                GeometryReader { geo in
                    let period = 3.2
                    let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                    LinearGradient(colors: [.clear, GH.apricot.opacity(0.35), GH.ink.opacity(0.6), GH.apricot.opacity(0.35), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 26, height: height)
                        .blur(radius: 2)
                        .position(x: geo.size.width * t, y: geo.size.height / 2)
                        .blendMode(.plusLighter)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// "Optimizing" with a breathing dot, like a live status.
private struct LiveBadge: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(GH.apricot).frame(width: 7, height: 7)
                .shadow(color: GH.apricot, radius: on ? 6 : 1)
                .opacity(on ? 1 : 0.4)
            Text("Optimizing").font(Night.font(12, .bold)).foregroundStyle(GH.apricot)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(GH.apricot.opacity(0.12)))
        .overlay(Capsule().strokeBorder(GH.apricot.opacity(0.35), lineWidth: 1))
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { on = true } }
    }
}
