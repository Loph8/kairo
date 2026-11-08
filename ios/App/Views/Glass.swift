import SwiftUI

// Kairos's visual system: warm sunrise light behind Apple's Liquid Glass.
// On iOS 26 surfaces use the real `glassEffect`; on iOS 17-18 they fall back to ultra-thin material
// with a hairline highlight so the layout and feel stay the same.

/// The same night sky as the "In Sync" widget, with a faint golden-hour glow on the horizon.
struct SunriseBackground: View {
    var body: some View {
        ZStack {
            NightSkyBackground(phase: .unknown)
            RadialGradient(colors: [GH.apricot.opacity(0.16), .clear], center: UnitPoint(x: 0.5, y: 0.0),
                           startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

extension View {
    /// A Liquid Glass surface (iOS 26) or a frosted one (earlier), clipped to a rounded rectangle.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 26, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tint?.opacity(0.35)).interactive(interactive), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .background(shape.fill((tint ?? .clear).opacity(0.18)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        }
    }

    /// The main call-to-action look: tinted glass on iOS 26, a filled capsule before.
    @ViewBuilder
    func primaryGlassButton() -> some View {
        modifier(PrimaryGlassButton())
    }

    @ViewBuilder
    func secondaryGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass).controlSize(.large)
        } else {
            self.buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule)
        }
    }
}

/// Groups nearby glass shapes so they blend and morph together on iOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// A glass card with padding. Most content in the app sits in one of these.
struct Card<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(tint: tint)
    }
}

struct BannerView: View {
    let text: String
    var onClose: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(GH.apricot)
            Text(text).font(Night.font(13)).foregroundStyle(GH.ink).frame(maxWidth: .infinity, alignment: .leading)
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark").font(Night.font(12, .bold)) }
                    .foregroundStyle(GH.inkSoft).accessibilityLabel("Dismiss")
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 18, tint: GH.peach)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Small uppercase heading above a group of cards.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(Night.font(12, .bold)).tracking(1.2)
            .foregroundStyle(GH.inkSoft).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
    }
}

/// G / Y / R as words and colors people understand.
enum Pickup {
    static func color(_ level: String) -> Color {
        switch level { case "G": return GH.apricot; case "Y": return GH.amber; default: return GH.peach }
    }
    static func label(_ level: String) -> String {
        switch level { case "G": return "Likely free"; case "Y": return "Maybe"; default: return "Unlikely" }
    }
    static func symbol(_ level: String) -> String {
        switch level { case "G": return "checkmark.circle.fill"; case "Y": return "questionmark.circle.fill"; default: return "moon.zzz.fill" }
    }
}

/// Formats a time in someone else's time zone, e.g. "10:00 AM".
enum LocalTime {
    static func format(_ d: Date, tz: String, withDay: Bool = false) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: tz)
        f.dateFormat = withDay ? "EEE h:mm a" : "h:mm a"
        return f.string(from: d)
    }

    static func flag(for tz: String) -> String {
        let map: [String: String] = [
            "Asia/Seoul": "🇰🇷", "Africa/Addis_Ababa": "🇪🇹", "America/New_York": "🇺🇸", "America/Chicago": "🇺🇸",
            "America/Denver": "🇺🇸", "America/Los_Angeles": "🇺🇸", "Europe/London": "🇬🇧", "Europe/Paris": "🇫🇷",
            "Europe/Berlin": "🇩🇪", "Asia/Tokyo": "🇯🇵", "Asia/Shanghai": "🇨🇳", "Asia/Kolkata": "🇮🇳",
            "Australia/Sydney": "🇦🇺", "America/Toronto": "🇨🇦", "America/Sao_Paulo": "🇧🇷", "America/Mexico_City": "🇲🇽",
        ]
        return map[tz] ?? "🌍"
    }
}

/// Gold button with night-colored text; when disabled the label switches to soft gray so it stays readable.
private struct PrimaryGlassButton: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        let label = enabled ? GH.night : GH.inkSoft.opacity(0.7)
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent).tint(GH.apricot).foregroundStyle(label).controlSize(.large)
        } else {
            content.buttonStyle(.borderedProminent).tint(GH.apricot).foregroundStyle(label).controlSize(.large).buttonBorderShape(.capsule)
        }
    }
}
