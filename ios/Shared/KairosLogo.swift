import SwiftUI

/// The Kairos mark: the widget's clock in a night sky, with the golden window lit at the top.
/// Used as the app icon (rendered at 1024, unclipped) and on the sign-in screen.
struct KairosLogo: View {
    var size: CGFloat = 96
    /// The app icon must be a full square; iOS rounds its corners itself.
    var rounded = true

    private let gold = Color(red: 0xF5 / 255, green: 0xE6 / 255, blue: 0xA3 / 255)
    private let lavender = Color(red: 0xC8 / 255, green: 0xBA / 255, blue: 0xDD / 255)
    private let white = Color(red: 0xF8 / 255, green: 0xF9 / 255, blue: 0xF4 / 255)
    private let stars: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (0.16, 0.18, 0.010), (0.82, 0.14, 0.008), (0.88, 0.70, 0.009), (0.12, 0.80, 0.007), (0.70, 0.88, 0.006),
    ]

    var body: some View {
        let s = size
        let dial = s * 0.62
        let line = s * 0.07
        ZStack {
            LinearGradient(colors: [Color(red: 0x45 / 255, green: 0x36 / 255, blue: 0x66 / 255),
                                    Color(red: 0x1E / 255, green: 0x17 / 255, blue: 0x30 / 255)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [gold.opacity(0.28), .clear], center: UnitPoint(x: 0.5, y: 0.32),
                           startRadius: 0, endRadius: s * 0.55)
            ForEach(stars.indices, id: \.self) { i in
                Circle().fill(white.opacity(0.8)).frame(width: s * stars[i].r * 2, height: s * stars[i].r * 2)
                    .position(x: s * stars[i].x, y: s * stars[i].y)
            }
            Circle().stroke(lavender.opacity(0.28), lineWidth: line).frame(width: dial, height: dial)
            // The golden window: about 10 o'clock to 2 o'clock, glowing.
            Circle().trim(from: 0, to: 0.34)
                .stroke(gold, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90 - 0.17 * 360))
                .frame(width: dial, height: dial)
                .shadow(color: gold.opacity(0.9), radius: s * 0.05)
                .shadow(color: gold.opacity(0.5), radius: s * 0.12)
            hand(length: dial * 0.30, width: s * 0.035, angle: -55)
            hand(length: dial * 0.40, width: s * 0.025, angle: 50)
            Circle().fill(gold).frame(width: s * 0.065, height: s * 0.065)
                .shadow(color: gold.opacity(0.8), radius: s * 0.03)
        }
        .frame(width: s, height: s)
        .clipShape(RoundedRectangle(cornerRadius: rounded ? s * 0.2237 : 0, style: .continuous))
        .accessibilityLabel("Kairos")
    }

    private func hand(length: CGFloat, width: CGFloat, angle: Double) -> some View {
        Capsule().fill(white)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
    }
}
