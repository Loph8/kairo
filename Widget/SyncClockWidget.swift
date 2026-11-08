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
    // Avenir Next ships with iOS, so nothing to bundle. To use a custom font instead
    // (e.g. Oasis, Celio, Brillo): add its licensed .otf/.ttf to the Widget target, list it under
    // UIAppFonts in the widget's Info.plist (project.yml), and change `faces` to its PostScript names.
    private static let faces: [Font.Weight: String] = [
        .regular: "AvenirNext-Regular",
        .medium: "AvenirNext-Medium",
        .semibold: "AvenirNext-DemiBold",
        .bold: "AvenirNext-Bold",
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

// MARK: Clock face

struct SyncClockFace: View {
    let windows: [SyncWindow]
    let now: Date
    let timeZone: TimeZone
    let inSync: Bool
    /// Thickness of the purple ring; the yellow arcs use exactly the same width.
    let ring: CGFloat
    var numberSize: CGFloat = 10

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
            let numberRadius = r - ring * 1.6 - numberSize * 0.35
            let handLength = r * 0.55

            ZStack {
                // Purple ring
                Circle()
                    .stroke(Night.ring.opacity(inSync ? 0.85 : 0.6), lineWidth: ring)
                    .frame(width: d, height: d)

                // Available windows: just yellow
                ForEach(arcs.filter { !$0.optimal }, id: \.self) { a in
                    Circle().trim(from: a.from, to: a.to)
                        .stroke(Night.yellow.opacity(0.9), style: StrokeStyle(lineWidth: ring, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: d, height: d)
                }
                // Optimal windows: glowing gold (glows harder while in sync)
                ForEach(arcs.filter(\.optimal), id: \.self) { a in
                    Circle().trim(from: a.from, to: a.to)
                        .stroke(inSync ? Night.goldBright : Night.gold, style: StrokeStyle(lineWidth: ring, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: d, height: d)
                        .shadow(color: Night.gold.opacity(0.95), radius: inSync ? ring * 0.9 : ring * 0.5)
                        .shadow(color: Night.gold.opacity(inSync ? 0.8 : 0.45), radius: inSync ? ring * 2.4 : ring * 1.3)
                }

                // Hour ticks (skipped where the 12 / 3 / 6 / 9 numerals sit)
                ForEach(0..<12, id: \.self) { h in
                    if h % 3 != 0 {
                        Capsule()
                            .fill(Night.lavender.opacity(0.55))
                            .frame(width: max(1.2, ring * 0.22), height: tickLength * 0.6)
                            .offset(y: -(r - ring - tickLength * 0.5))
                            .rotationEffect(.degrees(Double(h) * 30))
                    }
                }

                // Numerals: 12 at the top, like a real clock
                ForEach([12, 3, 6, 9], id: \.self) { n in
                    let angle = Double(n % 12) / 12 * 2 * .pi
                    Text("\(n)")
                        .font(Night.font(numberSize, .semibold))
                        .foregroundStyle(Night.lavender)
                        .offset(x: sin(angle) * numberRadius, y: -cos(angle) * numberRadius)
                }

                // Hour hand pointing at "now"
                Capsule()
                    .fill(inSync ? Night.goldBright : Night.lavender)
                    .frame(width: max(2, ring * 0.38), height: handLength)
                    .offset(y: -handLength / 2)
                    .rotationEffect(.degrees(fraction(now) * 360))
                    .shadow(color: inSync ? Night.gold.opacity(0.8) : .clear, radius: 3)
                Circle()
                    .fill(inSync ? Night.goldBright : Night.lavender)
                    .frame(width: ring * 1.1, height: ring * 1.1)
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
            .font(Night.font(compact ? 10 : 14, .bold))
            .foregroundStyle(Night.skyTop)
            .padding(.horizontal, compact ? 7 : 12)
            .padding(.vertical, compact ? 3 : 6)
            .background(Capsule().fill(LinearGradient(colors: [Night.goldBright, Night.gold],
                                                      startPoint: .top, endPoint: .bottom)))
            .shadow(color: Night.gold.opacity(0.9), radius: compact ? 4 : 7)
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
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(person.relationship)
                    .font(Night.font(compact ? 14 : 20, .semibold))
                    .foregroundStyle(phase.isInSync ? Night.goldBright : Night.text)
                    .shadow(color: phase.isInSync ? Night.gold.opacity(0.7) : .clear, radius: 4)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("\(entry.time(person)) · \(person.city)")
                    .font(Night.font(compact ? 9 : 12, .medium))
                    .monospacedDigit()
                    .foregroundStyle(Night.lavender)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
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

    private var titleSize: CGFloat { compact ? 13 : 20 }
    private var subSize: CGFloat { compact ? 10 : 14 }

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            switch phase {
            case .inSync:
                title("You're in sync!", color: Night.goldBright)
                    .shadow(color: Night.gold.opacity(0.95), radius: 4)
                    .shadow(color: Night.gold.opacity(0.7), radius: 10)
                sub(Text("Good time to call"))
            case .available(let until, let nextOptimal):
                title("Free-ish right now", color: Night.yellow)
                if let n = nextOptimal {
                    sub(Text("Best time in ") + Text(entry.realTarget(n), style: .relative))
                } else {
                    sub(Text("Until \(TimeKit.formatTime(until, entry.snapshot?.viewerTimeZone ?? .current, use24Hour: entry.snapshot?.use24Hour ?? false))"))
                }
            case .almost(let d):
                title("Almost in sync", color: Night.text)
                sub(Text("Next window in ") + Text(entry.realTarget(d), style: .relative))
            case .waiting(let d):
                Text("Next sync in")
                    .font(Night.font(subSize, .medium))
                    .foregroundStyle(Night.lavender)
                Text(entry.realTarget(d), style: .relative)
                    .font(Night.font(compact ? 16 : 28, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Night.text)
            case .none:
                title("Not quite yet", color: Night.text)
                sub(Text("No sync in the next 12h"))
            case .unknown:
                title("Still learning", color: Night.text)
                sub(Text("Open Golden Hour to refresh"))
            }
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
        .lineLimit(1).minimumScaleFactor(0.6)
    }

    private func title(_ s: String, color: Color) -> some View {
        Text(s).font(Night.font(titleSize, .semibold)).foregroundStyle(color)
    }
    private func sub(_ t: Text) -> some View {
        t.font(Night.font(subSize, .medium)).foregroundStyle(Night.lavender)
    }
}

/// Starry background. In sync → the whole widget glows gold; available now → a softer warm tint.
struct NightSkyBackground: View {
    let phase: SyncPhase
    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.08, 0.12, 1.4), (0.22, 0.30, 0.9), (0.90, 0.22, 1.2), (0.70, 0.08, 0.8),
        (0.12, 0.70, 1.0), (0.94, 0.62, 1.3), (0.55, 0.92, 0.9), (0.35, 0.55, 0.7), (0.80, 0.85, 1.1),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [Night.skyTop, Night.skyBottom], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Night.violet.opacity(0.45), .clear], center: .bottomLeading,
                               startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * 0.8)
                ForEach(0..<Self.stars.count, id: \.self) { i in
                    let s = Self.stars[i]
                    Circle().fill(.white.opacity(0.7))
                        .frame(width: s.2 * 2, height: s.2 * 2)
                        .position(x: geo.size.width * s.0, y: geo.size.height * s.1)
                }
                if phase.isInSync {
                    RadialGradient(colors: [Night.gold.opacity(0.42), Night.gold.opacity(0.12), .clear], center: .center,
                                   startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * 0.75)
                    ContainerRelativeShape().strokeBorder(Night.gold, lineWidth: 10).blur(8)
                    ContainerRelativeShape().strokeBorder(Night.goldBright.opacity(0.95), lineWidth: 2)
                } else if phase.isAvailable {
                    RadialGradient(colors: [Night.yellow.opacity(0.14), .clear], center: .center,
                                   startRadius: 0, endRadius: max(geo.size.width, geo.size.height) * 0.6)
                    ContainerRelativeShape().strokeBorder(Night.yellow.opacity(0.45), lineWidth: 1)
                } else {
                    ContainerRelativeShape().strokeBorder(Night.lavender.opacity(0.3), lineWidth: 1)
                }
            }
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
                        .font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                        .foregroundStyle(Night.text)
                }
                .widgetURL(DeepLink.dashboard.url)
            }
        }
        .containerBackground(for: .widget) { NightSkyBackground(phase: phase) }
    }

    @ViewBuilder
    private func content(_ p: WidgetPerson, _ s: WidgetSnapshot, _ phase: SyncPhase) -> some View {
        let face = { (ring: CGFloat, numbers: CGFloat) in
            SyncClockFace(windows: entry.syncWindows(for: p), now: entry.now, timeZone: s.viewerTimeZone,
                          inSync: phase.isInSync, ring: ring, numberSize: numbers)
        }
        switch family {
        case .systemMedium:
            HStack(spacing: 14) {
                face(7, 10)
                VStack(alignment: .leading, spacing: 6) {
                    SyncHeader(entry: entry, person: p, phase: phase)
                    Spacer(minLength: 0)
                    SyncStatusText(entry: entry, phase: phase, alignment: .leading)
                }
            }
        case .systemLarge:
            VStack(spacing: 10) {
                SyncHeader(entry: entry, person: p, phase: phase)
                face(11, 15).padding(.horizontal, 12)
                SyncStatusText(entry: entry, phase: phase)
            }
        default: // systemSmall
            VStack(spacing: 4) {
                SyncHeader(entry: entry, person: p, phase: phase, compact: true)
                face(5, 8)
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
