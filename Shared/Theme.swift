import SwiftUI
import KairoCore

/// Sunrise palette. Dynamic colors adapt to light/dark without an asset catalog.
enum GH {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
    static let ivory = dyn(0xFFF8EE, 0x1E1814)
    static let card = dyn(0xFFFFFF, 0x2B221C)
    static let peach = dyn(0xFFDCC2, 0x5A3A28)
    static let apricot = dyn(0xF2A365, 0xF0A869)
    static let amber = dyn(0xB7791F, 0xE8B44F)
    static let ink = dyn(0x3B2A20, 0xF6EBDD)
    static let inkSoft = dyn(0x7A6657, 0xC9B8A6)
    static let green = dyn(0x2F7D4F, 0x6CCB8F)
    static let red = dyn(0xB4403A, 0xF08A80)
    static let neutral = dyn(0x80736A, 0xB5A89C)

    static var sunrise: LinearGradient {
        LinearGradient(colors: [peach.opacity(0.9), ivory], startPoint: .top, endPoint: .bottom)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Availability is never conveyed by color alone: every level has a symbol AND a text label.
extension AvailabilityLevel {
    var symbol: String {
        switch self {
        case .likelyFree: return "checkmark.circle.fill"
        case .maybeFree: return "circle.lefthalf.filled"
        case .unlikely: return "minus.circle"
        case .busy: return "xmark.circle.fill"
        case .quietHours: return "moon.fill"
        case .learning: return "hourglass"
        }
    }
    var tint: Color {
        switch self {
        case .likelyFree: return GH.green
        case .maybeFree: return GH.amber
        case .unlikely, .learning: return GH.neutral
        case .busy, .quietHours: return GH.red
        }
    }
}

struct AvailabilityBadge: View {
    var level: AvailabilityLevel
    var compact = false
    var body: some View {
        Label { Text(level.label).lineLimit(1) } icon: { Image(systemName: level.symbol) }
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
            .foregroundStyle(level.tint)
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(level.label)
    }
}

struct Avatar: View {
    var initials: String
    var size: CGFloat = 28
    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(GH.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(GH.peach))
            .overlay(Circle().strokeBorder(GH.apricot.opacity(0.6), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

extension ViewerBookingState {
    func label(otherName: String) -> String {
        switch self {
        case .suggested: return "Suggested"
        case .awaitingYou: return "Awaiting your confirmation"
        case .awaitingOther: return "Waiting for \(otherName)"
        case .confirmed: return "Booked"
        case .declined: return "Declined"
        case .expired: return "Expired"
        case .canceled: return "Canceled"
        case .completed: return "Completed"
        }
    }
    var symbol: String {
        switch self {
        case .suggested: return "sparkles"
        case .awaitingYou: return "hand.tap"
        case .awaitingOther: return "hourglass"
        case .confirmed: return "checkmark.seal.fill"
        case .declined: return "xmark.circle"
        case .expired: return "clock.badge.exclamationmark"
        case .canceled: return "slash.circle"
        case .completed: return "checkmark.circle"
        }
    }
}

extension SyncStatus {
    var label: String {
        switch self {
        case .localOnly: return "Saved on this device · demo, not synced"
        case .offlinePending(let n): return "Offline · \(n) change\(n == 1 ? "" : "s") saved locally, not synced"
        case .synced: return "Synced"
        }
    }
}
