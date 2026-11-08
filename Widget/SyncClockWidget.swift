import WidgetKit
import SwiftUI
import GoldenHourCore

// MARK: - "In Sync" clock widget
//
// A 12-hour clock face (12 at the top, in YOUR local time) for one family member.
// The next 12 hours of their forecast are drawn on the ring:
//   • optimal (likely free)  → glowing gold arc
//   • available (maybe free) → plain yellow arc, no glow
// Arcs are the same thickness as the purple ring. When right now is an optimal window
// the whole widget glows gold and a Call button pops up next to the contact's name.

// MARK: Palette (fixed night sky, independent of light/dark mode)

enum Night {
    private static func c(_ hex: UInt32) -> Color { Color(uiColor: UIColor(hex: hex)) }
    static let skyTop = c(0x0B0926)
    static let skyBottom = c(0x1A1550)
    static let violet = c(0x5B4BD6)
    static let ring = c(0x8E86E0)
    static let lavender = c(0xB4ADF2)
    static let text = c(0xECEAFF)
    static let gold = c(0xFFC93C)
    static let goldBright = c(0xFFE38A)
    static let yellow = c(0xF2D06B)

    // MARK: Typography
    // Sulphur Point (Google Fonts, SIL Open Font License; see Widget/Fonts/OFL.txt).
    // The .ttf files live in Widget/Fonts and are registered via UIAppFonts in project.yml.
    // It only comes in Light / Regular / Bold, so medium maps to Regular and semibold to Bold.
    private static let faces: [Font.Weight: String] = [
        .light: "SulphurPoint-Light",
        .regular: "SulphurPoint-Regular",
        .medium: "SulphurPoint-Regular",
        .semibold: "SulphurPoint-Bold",
        .bold: "SulphurPoint-Bold",
    ]
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(faces[weight] ?? faces[.regular]!, size: size)
    }
}

// MARK: Model

struct SyncWindow: Hashable {
    var start: Date
    var end: Date
    /// true = likely free (optimal), false = maybe free (available)
    var optimal: Bool
}

enum SyncPhase {
    case inSync(until: Date)
    case available(until: Date, nextOptimal: Date?)
    case almost(Date)
    case waiting(Date)
    case none
    case unknown

    var isInSync: Bool { if case .inSync = self { return true } else { return false } }
    var isAvailable: Bool { if case .available = self { return true } else { return false } }
}

extension GoldenEntry {
    static let clockHorizon: TimeInterval = 12 * 3600

    /// Free windows for `p` from now through the next 12 hours (one full trip around the clock).
    /// Time while YOU are marked busy is left off, since you can't call then anyway.
    func syncWindows(for p: WidgetPerson) -> [SyncWindow] {
        guard let s = snapshot else { return [] }
        let lower = max(now, s.busyUntil ?? now)
        let upper = now.addingTimeInterval(Self.clockHorizon)
        var out: [SyncWindow] = []
        for (i, level) in p.forecast.enumerated() {
            let optimal: Bool
            switch level {
            case .likelyFree: optimal = true
            case .maybeFree: optimal = false
            default: continue
            }
            let a = max(s.forecastStart.addingTimeInterval(Double(i) * 1800), lower)
            let b = min(s.forecastStart.addingTimeInterval(Double(i + 1) * 1800), upper)
            guard b > a else { continue }
            if let last = out.last, last.optimal == optimal, abs(last.end.timeIntervalSince(a)) < 1 {
                out[out.count - 1].end = b
            } else {
                out.append(SyncWindow(start: a, end: b, optimal: optimal))
            }
        }
        return out
    }

    func syncPhase(for p: WidgetPerson) -> SyncPhase {
        guard p.forecast.contains(where: { $0 != .learning }) else { return .unknown }
        let windows = syncWindows(for: p)
        let nextOptimal = windows.first { $0.optimal && $0.start > now }?.start
        if let current = windows.first(where: { $0.start <= now && now < $0.end }) {
            return current.optimal ? .inSync(until: current.end)
                                   : .available(until: current.end, nextOptimal: nextOptimal)
        }
        guard let next = nextOptimal ?? windows.first(where: { $0.start > now })?.start else { return .none }
        return next.timeIntervalSince(now) <= 30 * 60 ? .almost(next) : .waiting(next)
    }
}

// MARK: Look (night sky normally, golden sky while in sync)

struct SyncLook {
    var ring: Color, ringOpacity: Double
    var optimal: Color, optimalGlow: Color
    var available: Color
    var detail: Color            // ticks, numerals, hand
    var text: Color, textSoft: Color

    private static func c(_ hex: UInt32) -> Color { Color(uiColor: UIColor(hex: hex)) }
    static let indigo = c(0x2A1F6B)
    static let cream = c(0xFFFBEA)

    static let night = SyncLook(ring: Night.ring, ringOpacity: 0.6,
                                optimal: Night.gold, optimalGlow: Night.gold,
                                available: Night.yellow, detail: Night.lavender,
                                text: Night.text, textSoft: Night.lavender)
    /// Yellow background: the ring and text flip to deep indigo so they still read; the
    /// optimal arcs turn glowing cream-white and "available" arcs a deeper amber.
    static let golden = SyncLook(ring: indigo, ringOpacity: 0.3,
                                 optimal: cream, optimalGlow: .white,
                                 available: c(0xD98A0B), detail: indigo,
                                 text: indigo, textSoft: indigo)

    static func of(_ phase: SyncPhase) -> SyncLook { phase.isInSync ? golden : night }
}

/// All text is secondary to the clock: small and at 75% opacity.
private let textOpacity = 0.75

// MARK: Clock face

struct SyncClockFace: View {
    let windows: [SyncWindow]
    let now: Date
    let timeZone: TimeZone
    let inSync: Bool
    /// Thickness of the ring; the yellow arcs use exactly the same width.
    let ring: CGFloat
    var numberSize: CGFloat = 10

    private var look: SyncLook { inSync ? .golden : .night }
    private struct Arc: Hashable { var from: Double; var to: Double; var optimal: Bool }

    /// 0…1 around the dial, 0 = 12 o'clock.
    private func fraction(_ d: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute, .second], from: d)
        let h = Double((c.hour ?? 0) % 12) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        return h / 12
    }

    private var arcs: [Arc] {
        windows.flatMap { w -> [Arc] in
            let from = fraction(w.start)
            let length = min(w.end.timeIntervalSince(w.start) / (12 * 3600), 1)
            let to = from + length
            if to <= 1 { return [Arc(from: from, to: to, optimal: w.optimal)] }
            return [Arc(from: from, to: 1, optimal: w.optimal), Arc(from: 0, to: to - 1, optimal: w.optimal)]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let d = side - ring - 4             // ring path diameter (stroke + a little glow room)
            let r = d / 2
            let tickLength = ring * 0.9
            let numberRadius = r - ring * 1.5 - numberSize * 0.4
            let handLength = r * 0.55

            ZStack {
                Circle()
                    .stroke(look.ring.opacity(look.ringOpacity), lineWidth: ring)
                    .frame(width: d, height: d)

                // Available windows: just yellow
                ForEach(arcs.filter { !$0.optimal }, id: \.self) { a in
                    Circle().trim(from: a.from, to: a.to)
                        .stroke(look.available, style: StrokeStyle(lineWidth: ring, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: d, height: d)
                }
                // Optimal windows: glowing (glows harder while in sync)
                ForEach(arcs.filter(\.optimal), id: \.self) { a in
                    Circle().trim(from: a.from, to: a.to)
                        .stroke(look.optimal, style: StrokeStyle(lineWidth: ring, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: d, height: d)
                        .shadow(color: look.optimalGlow.opacity(0.95), radius: inSync ? ring * 0.9 : ring * 0.5)
                        .shadow(color: look.optimalGlow.opacity(inSync ? 0.85 : 0.45), radius: inSync ? ring * 2.2 : ring * 1.3)
                }

                // Hour ticks (skipped where the 12 / 3 / 6 / 9 numerals sit)
                ForEach(0..<12, id: \.self) { h in
                    if h % 3 != 0 {
                        Capsule()
                            .fill(look.detail.opacity(0.5))
                            .frame(width: max(1.2, ring * 0.2), height: tickLength * 0.6)
                            .offset(y: -(r - ring - tickLength * 0.5))
                            .rotationEffect(.degrees(Double(h) * 30))
                    }
                }

                // Numerals: 12 at the top, like a real clock
                ForEach([12, 3, 6, 9], id: \.self) { n in
                    let angle = Double(n % 12) / 12 * 2 * .pi
                    Text("\(n)")
                        .font(Night.font(numberSize, .regular))
                        .foregroundStyle(look.detail.opacity(0.8))
                        .offset(x: sin(angle) * numberRadius, y: -cos(angle) * numberRadius)
                }

                // Hour hand pointing at "now"
                Capsule()
                    .fill(look.detail)
                    .frame(width: max(2, ring * 0.32), height: handLength)
                    .offset(y: -handLength / 2)
                    .rotationEffect(.degrees(fraction(now) * 360))
                Circle()
                    .fill(look.detail)
                    .frame(width: ring * 0.9, height: ring * 0.9)
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: Pieces

struct SyncCallButton: View {
    let person: WidgetPerson
    var compact = false
    var body: some View {
        Link(destination: DeepLink.call(person.id).url) {
            Text("Call")
                .font(Night.font(compact ? 9 : 12, .bold))
                .foregroundStyle(SyncLook.cream)
                .padding(.horizontal, compact ? 7 : 11)
                .padding(.vertical, compact ? 2.5 : 4)
                .background(Capsule().fill(SyncLook.indigo))
                .shadow(color: SyncLook.indigo.opacity(0.35), radius: 3, y: 1)
        }
        .accessibilityLabel("Call \(person.relationship)")
    }
}

struct SyncHeader: View {
    let entry: GoldenEntry
    let person: WidgetPerson
    let phase: SyncPhase
    var compact = false
    var body: some View {
        let look = SyncLook.of(phase)
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(person.relationship)
                    .font(Night.font(compact ? 11 : 15, .semibold))
                    .foregroundStyle(look.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("\(entry.time(person)) · \(person.city)")
                    .font(Night.font(compact ? 8 : 10, .medium))
                    .monospacedDigit()
                    .foregroundStyle(look.textSoft)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .opacity(textOpacity)
            Spacer(minLength: 2)
            if phase.isInSync { SyncCallButton(person: person, compact: compact) }
        }
    }
}

struct SyncStatusText: View {
    let entry: GoldenEntry
    let phase: SyncPhase
    var compact = false
    var alignment: HorizontalAlignment = .center

    private var look: SyncLook { .of(phase) }
    private var titleSize: CGFloat { compact ? 10 : 14 }
    private var subSize: CGFloat { compact ? 8 : 11 }

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            switch phase {
            case .inSync:
                title("You're in sync!")
                sub(Text("Good time to call"))
            case .available(let until, let nextOptimal):
                title("Free-ish right now", color: Night.yellow)
                if let n = nextOptimal {
                    sub(Text("Best time in ") + Text(entry.realTarget(n), style: .relative))
                } else {
                    sub(Text("Until \(TimeKit.formatTime(until, entry.snapshot?.viewerTimeZone ?? .current, use24Hour: entry.snapshot?.use24Hour ?? false))"))
                }
            case .almost(let d):
                title("Almost in sync")
                sub(Text("Next window in ") + Text(entry.realTarget(d), style: .relative))
            case .waiting(let d):
                sub(Text("Next sync in"))
                Text(entry.realTarget(d), style: .relative)
                    .font(Night.font(compact ? 11 : 16, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(look.text)
            case .none:
                title("Not quite yet")
                sub(Text("No sync in the next 12h"))
            case .unknown:
                title("Still learning")
                sub(Text("Open Golden Hour to refresh"))
            }
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .lineLimit(1).minimumScaleFactor(0.6)
        .opacity(textOpacity)
    }

    private func title(_ s: String, color: Color? = nil) -> some View {
        Text(s).font(Night.font(titleSize, .semibold)).foregroundStyle(color ?? look.text)
    }
    private func sub(_ t: Text) -> some View {
        t.font(Night.font(subSize, .medium)).foregroundStyle(look.textSoft)
    }
}

/// Night sky normally. In sync → the whole background turns glowing yellow-gold.
struct NightSkyBackground: View {
    let phase: SyncPhase
    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.08, 0.12, 1.4), (0.22, 0.30, 0.9), (0.90, 0.22, 1.2), (0.70, 0.08, 0.8),
        (0.12, 0.70, 1.0), (0.94, 0.62, 1.3), (0.55, 0.92, 0.9), (0.35, 0.55, 0.7), (0.80, 0.85, 1.1),
    ]
    private static func c(_ hex: UInt32) -> Color { Color(uiColor: UIColor(hex: hex)) }

    var body: some View {
        GeometryReader { geo in
            let big = max(geo.size.width, geo.size.height)
            ZStack {
                if phase.isInSync {
                    LinearGradient(colors: [Self.c(0xFFE680), Self.c(0xFFC93C), Self.c(0xF5A623)],
                                   startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Self.c(0xFFFBE0).opacity(0.85), Self.c(0xFFF3B0).opacity(0.3), .clear],
                                   center: .center, startRadius: 0, endRadius: big * 0.6)
                    stars(in: geo.size, opacity: 0.85)
                    ContainerRelativeShape().strokeBorder(.white.opacity(0.9), lineWidth: 10).blur(9)
                    ContainerRelativeShape().strokeBorder(Self.c(0xFFF6CC), lineWidth: 1.5)
                } else {
                    LinearGradient(colors: [Night.skyTop, Night.skyBottom], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Night.violet.opacity(0.45), .clear], center: .bottomLeading,
                                   startRadius: 0, endRadius: big * 0.8)
                    stars(in: geo.size, opacity: 0.7)
                    if phase.isAvailable {
                        RadialGradient(colors: [Night.yellow.opacity(0.14), .clear], center: .center,
                                       startRadius: 0, endRadius: big * 0.6)
                        ContainerRelativeShape().strokeBorder(Night.yellow.opacity(0.45), lineWidth: 1)
                    } else {
                        ContainerRelativeShape().strokeBorder(Night.lavender.opacity(0.3), lineWidth: 1)
                    }
                }
            }
        }
    }

    private func stars(in size: CGSize, opacity: Double) -> some View {
        ForEach(0..<Self.stars.count, id: \.self) { i in
            let s = Self.stars[i]
            Circle().fill(.white.opacity(opacity))
                .frame(width: s.2 * 2, height: s.2 * 2)
                .position(x: size.width * s.0, y: size.height * s.1)
        }
    }
}

// MARK: Layouts

struct SyncClockEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GoldenEntry

    var body: some View {
        let person = entry.focus
        let phase = person.map { entry.syncPhase(for: $0) } ?? .unknown
        Group {
            if let p = person, let s = entry.snapshot {
                content(p, s, phase)
                    .widgetURL(DeepLink.member(p.id).url)
                    .accessibilityElement(children: .combine)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "clock").font(.title2).foregroundStyle(Night.gold)
                    Text("Open Golden Hour to set up your family")
                        .font(Night.font(12, .semibold)).multilineTextAlignment(.center)
                        .foregroundStyle(Night.text).opacity(textOpacity)
                }
                .widgetURL(DeepLink.dashboard.url)
            }
        }
        .containerBackground(for: .widget) { NightSkyBackground(phase: phase) }
    }

    /// The clock is the hero: it takes all the space the (small) text doesn't.
    @ViewBuilder
    private func content(_ p: WidgetPerson, _ s: WidgetSnapshot, _ phase: SyncPhase) -> some View {
        let face = { (ring: CGFloat, numbers: CGFloat) in
            SyncClockFace(windows: entry.syncWindows(for: p), now: entry.now, timeZone: s.viewerTimeZone,
                          inSync: phase.isInSync, ring: ring, numberSize: numbers)
        }
        switch family {
        case .systemMedium:
            HStack(spacing: 12) {
                face(10, 11)
                VStack(alignment: .leading, spacing: 4) {
                    SyncHeader(entry: entry, person: p, phase: phase)
                    Spacer(minLength: 0)
                    SyncStatusText(entry: entry, phase: phase, alignment: .leading)
                }
            }
        case .systemLarge:
            VStack(spacing: 6) {
                SyncHeader(entry: entry, person: p, phase: phase)
                face(16, 17).frame(maxHeight: .infinity)
                SyncStatusText(entry: entry, phase: phase)
            }
        default: // systemSmall
            VStack(spacing: 2) {
                SyncHeader(entry: entry, person: p, phase: phase, compact: true)
                face(7, 9).frame(maxHeight: .infinity)
                SyncStatusText(entry: entry, phase: phase, compact: true)
            }
        }
    }
}

struct SyncClockWidget: Widget {
    let kind = "GoldenHourSyncClock"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectMemberIntent.self, provider: GoldenProvider()) { entry in
            SyncClockEntryView(entry: entry)
        }
        .configurationDisplayName("In Sync")
        .description("A clock showing when you and someone you love are both likely free. Estimates, not guarantees.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Previews

private enum SyncPreview {
    /// Shapes the focus person's forecast so each preview lands in a specific phase.
    /// Pattern is per 30-minute slot starting at the slot that contains "now".
    static func entry(_ pattern: [AvailabilityLevel]) -> GoldenEntry {
        var snap = PreviewData.snapshot(.suggested)
        let now = Date().addingTimeInterval(snap.clockOffset)
        let start = Int(floor(now.timeIntervalSince(snap.forecastStart) / 1800))
        if let i = snap.people.firstIndex(where: { $0.id == snap.focusPersonID }) ?? snap.people.indices.first {
            var f = Array(repeating: AvailabilityLevel.unlikely, count: max(snap.people[i].forecast.count, start + 48))
            for (k, lvl) in pattern.enumerated() where start + k >= 0 && start + k < f.count { f[start + k] = lvl }
            snap.people[i].forecast = f
            snap.focusPersonID = snap.people[i].id
        }
        snap.busyUntil = nil
        return GoldenEntry(date: .now, snapshot: snap, status: .ok, selectedID: nil)
    }
    static let u = AvailabilityLevel.unlikely, m = AvailabilityLevel.maybeFree, l = AvailabilityLevel.likelyFree
    static let inSync = entry([l, l, l, m, u, u, u, u, u, u, m, m, l, l, l, u])
    static let available = entry([m, m, l, l, u, u, u, u, u, u, u, u, m, m])
    static let almost = entry([u, l, l, l, m, u, u, u, u, u, u, u, l, l])
    static let waiting = entry([u, u, u, u, u, u, u, m, l, l, l, u, u, u, u, u, m, m])
}

#Preview("In Sync · small", as: .systemSmall) { SyncClockWidget() } timeline: { SyncPreview.inSync }
#Preview("Available · small", as: .systemSmall) { SyncClockWidget() } timeline: { SyncPreview.available }
#Preview("Almost · small", as: .systemSmall) { SyncClockWidget() } timeline: { SyncPreview.almost }
#Preview("Waiting · small", as: .systemSmall) { SyncClockWidget() } timeline: { SyncPreview.waiting }
#Preview("In Sync · medium", as: .systemMedium) { SyncClockWidget() } timeline: { SyncPreview.inSync }
#Preview("In Sync · large", as: .systemLarge) { SyncClockWidget() } timeline: { SyncPreview.inSync }
#Preview("Waiting · large", as: .systemLarge) { SyncClockWidget() } timeline: { SyncPreview.waiting }
