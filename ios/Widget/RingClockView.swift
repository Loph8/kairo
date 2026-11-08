import SwiftUI
import WidgetKit
import GoldenHourCore

/// The large widget's core: one 24-hour ring. Each half hour is shaded by how many of the
/// family are likely free then; the brightest stretch is when everyone overlaps.
struct RingClockView: View {
    let dial: OverlapDial
    /// Viewer-local hour of "now" as a fraction (e.g. 20.25 = 8:15 PM).
    let nowHour: Double

    /// Shade for 0, 1/4, 2/4, 3/4 and all of the family free.
    static let opacityLevels: [Double] = [0.1, 0.3, 0.5, 0.75, 1]
    static let ringWidthRatio = 0.13    // ring thickness as a share of the dial size
    static let startAngle = -90.0       // midnight at the top

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let ringWidth = size * Self.ringWidthRatio
            let radius = size / 2 - ringWidth / 2
            ZStack {
                Circle().fill(GH.card)
                ForEach(0..<OverlapDial.cellsPerDay, id: \.self) { cell in
                    segment(cell, radius: radius, width: ringWidth)
                }
                ForEach(0..<24, id: \.self) { hour in
                    hourLabel(hour, radius: radius, size: size)
                }
                hand(radius: radius - ringWidth / 2 - 6)
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Pieces

    private func segment(_ cell: Int, radius: Double, width: Double) -> some View {
        let count = dial.counts[cell]
        let everyone = dial.total > 0 && count == dial.total
        return RingSegment(cell: cell, radius: radius)
            .stroke(GH.apricot.opacity(opacity(for: count)), style: StrokeStyle(lineWidth: width, lineCap: .butt))
            .shadow(color: everyone ? GH.amber.opacity(0.55) : .clear, radius: everyone ? 6 : 0)
    }

    private func hourLabel(_ hour: Int, radius: Double, size: Double) -> some View {
        let major = hour % 6 == 0
        let point = Self.point(hour: Double(hour), radius: radius, center: size / 2)
        return Text("\(hour)")
            .font(.system(size: major ? 11 : 8, weight: major ? .bold : .medium, design: .rounded))
            .foregroundStyle(major ? GH.ink : GH.inkSoft)
            .position(point)
    }

    private func hand(radius: Double) -> some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            let tip = Self.point(hour: nowHour, radius: radius, center: center)
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: center, y: center))
                    p.addLine(to: tip)
                }
                .stroke(GH.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle().fill(GH.ink).frame(width: 7, height: 7).position(x: center, y: center)
                Circle().fill(GH.apricot).frame(width: 9, height: 9).position(tip)
            }
        }
    }

    // MARK: - Math

    private func opacity(for count: Int) -> Double { Self.opacity(count: count, total: dial.total) }

    static func opacity(count: Int, total: Int) -> Double {
        guard total > 0, count > 0 else { return opacityLevels[0] }
        let share = Double(count) / Double(total)
        let step = Int((share * Double(opacityLevels.count - 1)).rounded())
        return opacityLevels[max(1, step)]
    }

    static func point(hour: Double, radius: Double, center: Double) -> CGPoint {
        let angle = (startAngle + hour / 24 * 360) * .pi / 180
        return CGPoint(x: center + radius * cos(angle), y: center + radius * sin(angle))
    }

    private var accessibilitySummary: String {
        let best = dial.counts.max() ?? 0
        return best == 0 ? "No overlap in the next day" : "Up to \(best) of \(dial.total) free at once"
    }
}

/// One half-hour arc of the ring.
struct RingSegment: Shape {
    let cell: Int
    let radius: Double

    func path(in rect: CGRect) -> Path {
        let step = 360.0 / Double(OverlapDial.cellsPerDay)
        let start = RingClockView.startAngle + Double(cell) * step
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                 startAngle: .degrees(start), endAngle: .degrees(start + step), clockwise: false)
        return p
    }
}

/// Small key under the ring: one swatch per head count.
struct RingKey: View {
    let total: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...max(1, total), id: \.self) { n in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(GH.apricot.opacity(RingClockView.opacity(count: n, total: total)))
                        .frame(width: 14, height: 8)
                    Text(n == total ? "\(n) free" : "\(n)").font(.caption2).foregroundStyle(GH.inkSoft)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
