import WidgetKit
import SwiftUI
import GoldenHourCore

// MARK: - "In Sync" clock widget
//
// A 12-hour clock face (12 at the top, in YOUR local time) for one family member.
// The next 12 hours of their forecast are drawn on the ring:
//   • optimal (likely free)  → solid gold arc with a soft halo
//   • available (maybe free) → soft champagne arc, no glow
// Arcs are the same thickness as the ring. The background is deep space; when right now is an
// optimal window a warm golden nebula blooms behind the clock and a Call button pops up next
// to the contact's name.

// MARK: Typography

enum Night {
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

// MARK: Look (deep-space palette; a warm golden nebula blooms behind the clock while in sync)

struct SyncLook {
    var ringOpacity: Double
    var optimal: Color
    var glowOpacity: Double
    var title: Color

    static let champagne = Space.summersHeat
    static let night = SyncLook(ringOpacity: 0.28, optimal: Space.summersHeat, glowOpacity: 0.45, title: Space.whitestWhite)
    static let golden = SyncLook(ringOpacity: 0.35, optimal: Space.summersHeat, glowOpacity: 0.75, title: Space.summersHeat)

    static func of(_ phase: SyncPhase) -> SyncLook { phase.isInSync ? golden : night }
}

/// Palette: Amethyst, Viking Diva, Summer's Heat, Whitest White, Gettysburg Gray.
enum Space {
    static func c(_ hex: UInt32) -> Color { Color(uiColor: UIColor(hex: hex)) }
    static let amethyst = c(0x51416E)
    static let vikingDiva = c(0xC8BADD)
    static let summersHeat = c(0xF5E6A3)
    static let whitestWhite = c(0xF8F9F4)
    static let gettysburgGray = c(0xC5C1B8)
}

/// All text is secondary to the clock: small and at 75% opacity.
private let textOpacity = 0.75

// MARK: Clock face

struct SyncClockFace: View {
    let windows: [SyncWindow]
    let now: Date
    let timeZone: TimeZone
    let inSync: Bool
    /// Thickness of the ring; the gold arcs use exactly the same width.
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
            let d = side - ring - 6             // ring path diameter (stroke + a little glow room)
            let r = d / 2
            let numberRadius = r - ring - numberSize * 0.95
            let tickRadius = r - ring - numberSize * 0.3
            let handLength = r * 0.52

            ZStack {
                // Saturn ring: sits behind the clock, so it only shows outside the dial
                saturnRing(d)
                    .mask {
                        ZStack {
                            Rectangle().frame(width: d * 2, height: d * 2)
                            Circle().frame(width: d + ring + 3, height: d + ring + 3).blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }

                Circle()
                    .stroke(Space.vikingDiva.opacity(look.ringOpacity), lineWidth: ring)
                    .frame(width: d, height: d)

                // Available (maybe free): soft champagne, no glow
                ForEach(arcs.filter { !$0.optimal }, id: \.self) { a in
                    Circle().trim(from: a.from, to: a.to)
                        .stroke(SyncLook.champagne.opacity(0.45), style: StrokeStyle(lineWidth: ring, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: d, height: d)
                }
                // Optimal (likely free): solid gold with a soft halo, brighter while in sync
                ForEach(arcs.filter(\.optimal), id: \.self) { a in
                    Circle().trim(from: a.from, to: a.to)
                        .stroke(look.optimal, style: StrokeStyle(lineWidth: ring, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: d, height: d)
                        .shadow(color: look.optimal.opacity(look.glowOpacity), radius: ring * (inSync ? 0.75 : 0.45))
                }

                // Hour ticks (skipped where the 12 / 3 / 6 / 9 numerals sit)
                ForEach(0..<12, id: \.self) { h in
                    if h % 3 != 0 {
                        Capsule()
                            .fill(Space.gettysburgGray.opacity(0.55))
                            .frame(width: max(1, ring * 0.17), height: ring * 0.45)
                            .offset(y: -tickRadius)
                            .rotationEffect(.degrees(Double(h) * 30))
                    }
                }

                // Numerals: 12 at the top, like a real clock
                ForEach([12, 3, 6, 9], id: \.self) { n in
                    let angle = Double(n % 12) / 12 * 2 * .pi
                    Text("\(n)")
                        .font(Night.font(numberSize, .regular))
                        .foregroundStyle(Space.whitestWhite.opacity(0.6))
                        .offset(x: sin(angle) * numberRadius, y: -cos(angle) * numberRadius)
                }

                // Hour hand pointing at "now"
                Capsule()
                    .fill(Space.whitestWhite.opacity(0.95))
                    .frame(width: max(1.8, ring * 0.35), height: handLength)
                    .offset(y: -handLength / 2)
                    .rotationEffect(.degrees(fraction(now) * 360))
                Circle()
                    .fill(Space.whitestWhite)
                    .frame(width: ring * 0.9, height: ring * 0.9)
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// A barely-there, tilted planetary ring around the dial: thin, very low opacity,
    /// only a little wider than the clock.
    private func saturnRing(_ d: CGFloat) -> some View {
        Ellipse()
            .stroke(Space.whitestWhite.opacity(0.2), style: StrokeStyle(lineWidth: max(0.5, ring * 0.09), lineCap: .round))
            .frame(width: d * 1.22, height: d * 0.26)
            .rotationEffect(.degrees(-16))
    }
}

// MARK: Pieces

/// Summer's Heat pill with Amethyst text.
struct SyncCallButton: View {
    let person: WidgetPerson
    var compact = false
    var body: some View {
        Link(destination: DeepLink.call(person.id).url) {
            Text("Call")
                .font(Night.font(compact ? 9.5 : 12, .bold))
                .foregroundStyle(Space.amethyst)
                .padding(.horizontal, compact ? 9 : 12)
                .padding(.vertical, compact ? 3 : 4.5)
                .background(Capsule().fill(Space.summersHeat))
                .shadow(color: Space.summersHeat.opacity(0.35), radius: 4, y: 1)
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
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(person.relationship)
                    .font(Night.font(compact ? 12 : 15, .bold))
                    .foregroundStyle(Space.whitestWhite.opacity(0.75))
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("\(entry.time(person)) · \(person.city)")
                    .font(Night.font(compact ? 8.5 : 10.5, .regular))
                    .monospacedDigit()
                    .foregroundStyle(Space.gettysburgGray.opacity(0.75))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 2)
            if phase.isInSync { SyncCallButton(person: person, compact: compact) }
        }
    }
}

/// The status under the clock. The best time to call is the big line; everything else stays small.
struct SyncStatusText: View {
    let entry: GoldenEntry
    let phase: SyncPhase
    var compact = false
    var alignment: HorizontalAlignment = .center

    private var look: SyncLook { .of(phase) }
    private var bigSize: CGFloat { compact ? 17 : 26 }
    private var subSize: CGFloat { compact ? 8 : 11 }

    var body: some View {
        VStack(alignment: alignment, spacing: compact ? 0 : 2) {
            switch phase {
            case .inSync:
                label("Best time")
                big(Text("Now"))
                sub(Text("Good time to call"))
            case .available(let until, let nextOptimal):
                label("Best time")
                if let n = nextOptimal {
                    big(Text(clock(entry.realTarget(n))))
                    sub(Text("in ") + Text(entry.realTarget(n), style: .relative))
                } else {
                    big(Text("Now"))
                    sub(Text("until \(clock(until))"))
                }
            case .almost(let d), .waiting(let d):
                label("Best time")
                big(Text(clock(entry.realTarget(d))))
                sub(Text("in ") + Text(entry.realTarget(d), style: .relative))
            case .none:
                label("Best time")
                big(Text("Later"))
                sub(Text("Nothing in the next 12h"))
            case .unknown:
                big(Text("Learning"))
                sub(Text("Open Kairos to refresh"))
            }
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .lineLimit(1).minimumScaleFactor(0.6)
        .opacity(textOpacity)
    }

    private func clock(_ d: Date) -> String {
        TimeKit.formatTime(d, entry.snapshot?.viewerTimeZone ?? .current, use24Hour: entry.snapshot?.use24Hour ?? false)
    }
    private func label(_ s: String) -> some View {
        Text(s.uppercased()).font(Night.font(compact ? 7.5 : 9.5, .bold)).tracking(1)
            .foregroundStyle(SyncLook.champagne.opacity(0.85))
    }
    private func big(_ t: Text) -> some View {
        t.font(Night.font(bigSize, .bold)).monospacedDigit()
            .foregroundStyle(look.title)
            .shadow(color: SyncLook.champagne.opacity(0.55), radius: compact ? 4 : 8)
    }
    private func sub(_ t: Text) -> some View {
        t.font(Night.font(subSize, .regular)).foregroundStyle(Space.gettysburgGray)
    }
}

/// "Kairos" at the top of every widget.
struct KairosMark: View {
    var compact = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkle").font(.system(size: compact ? 7 : 9, weight: .bold))
            Text("KAIROS").font(Night.font(compact ? 8 : 10, .bold)).tracking(2)
        }
        .foregroundStyle(SyncLook.champagne)
        .shadow(color: SyncLook.champagne.opacity(0.5), radius: 4)
    }
}

struct NightSkyBackground: View {
    let phase: SyncPhase
    /// Where the clock sits, so the in-sync glow blooms behind it.
    var glowCenter = UnitPoint(x: 0.5, y: 0.52)

    /// Deterministic star field: (x, y, radius, opacity), all relative.
    private static let stars: [(CGFloat, CGFloat, CGFloat, Double)] = {
        var seed: UInt64 = 11
        func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
        return (0..<38).map { _ in
            let s = rnd()
            return (rnd(), rnd(), s < 0.15 ? 1.3 : (s < 0.5 ? 0.8 : 0.5), 0.25 + Double(rnd()) * 0.6)
        }
    }()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, big = max(w, h)
            ZStack {
                if phase.isInSync {
                    LinearGradient(colors: [Space.c(0x2A2140), Space.c(0x433660), Space.amethyst],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    nebula(Space.vikingDiva, 0.35, at: UnitPoint(x: 0.15, y: 0.95), radius: big * 0.7)
                    RadialGradient(colors: [Space.summersHeat.opacity(0.55), Space.summersHeat.opacity(0.22), .clear],
                                   center: glowCenter, startRadius: 0, endRadius: big * 0.58)
                } else {
                    LinearGradient(colors: [Space.c(0x241C33), Space.c(0x382C4F), Space.amethyst],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    nebula(Space.vikingDiva, 0.30, at: UnitPoint(x: 0.2, y: 0.88), radius: big * 0.7)
                    nebula(Space.vikingDiva, 0.16, at: UnitPoint(x: 0.88, y: 0.12), radius: big * 0.5)
                }
                ForEach(0..<Self.stars.count, id: \.self) { i in
                    let s = Self.stars[i]
                    Circle().fill(Space.whitestWhite.opacity(s.3))
                        .frame(width: s.2 * 2, height: s.2 * 2)
                        .position(x: w * s.0, y: h * s.1)
                }
                Image(systemName: "sparkle")
                    .font(.system(size: 7))
                    .foregroundStyle(Space.whitestWhite.opacity(0.7))
                    .position(x: w * 0.14, y: h * 0.74)
                ContainerRelativeShape().strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
            }
        }
    }

    private func nebula(_ color: Color, _ opacity: Double, at center: UnitPoint, radius: CGFloat) -> some View {
        RadialGradient(colors: [color.opacity(opacity), .clear], center: center, startRadius: 0, endRadius: radius)
    }
}

// MARK: Layouts

struct SyncClockEntryView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: GoldenEntry
    /// Debug gallery in the app only: WidgetKit sets the family inside a real widget.
    var familyOverride: WidgetFamily?
    private var family: WidgetFamily { familyOverride ?? environmentFamily }

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
                    Image(systemName: "clock").font(.title2).foregroundStyle(SyncLook.champagne)
                    Text("Open Kairos to set up your family")
                        .font(Night.font(12, .bold)).multilineTextAlignment(.center)
                        .foregroundStyle(Space.whitestWhite).opacity(textOpacity)
                }
                .widgetURL(DeepLink.dashboard.url)
            }
        }
        .containerBackground(for: .widget) {
            // Medium puts the clock on the left, so the glow follows it there.
            NightSkyBackground(phase: phase,
                               glowCenter: family == .systemMedium ? UnitPoint(x: 0.22, y: 0.52) : UnitPoint(x: 0.5, y: 0.52))
        }
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
                face(9, 11)
                VStack(alignment: .leading, spacing: 4) {
                    KairosMark()
                    SyncHeader(entry: entry, person: p, phase: phase)
                    Spacer(minLength: 0)
                    SyncStatusText(entry: entry, phase: phase, alignment: .leading)
                }
            }
        case .systemLarge:
            VStack(spacing: 6) {
                KairosMark().frame(maxWidth: .infinity, alignment: .leading)
                SyncHeader(entry: entry, person: p, phase: phase)
                face(14, 17).frame(maxHeight: .infinity)
                SyncStatusText(entry: entry, phase: phase)
            }
        default: // systemSmall
            VStack(spacing: 2) {
                KairosMark(compact: true).frame(maxWidth: .infinity, alignment: .leading)
                SyncHeader(entry: entry, person: p, phase: phase, compact: true)
                face(6.5, 8.5).frame(maxHeight: .infinity)
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
        .configurationDisplayName("Kairos")
        .description("A clock showing when you and someone you love are both likely free. Estimates, not guarantees.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Previews

enum SyncPreview {
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
