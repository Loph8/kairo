import SwiftUI
import GoldenHourCore

/// Night-sky palette, shared with the "In Sync" widget (Amethyst, Viking Diva, Summer's Heat,
/// Whitest White, Gettysburg Gray). The app always runs dark so it matches the widget.
enum GH {
    static func c(_ hex: UInt32) -> Color { Color(UIColor(hex: hex)) }
    static let ivory = c(0x241C33)     // deepest sky
    static let card = c(0x382C4F)
    static let peach = c(0x51416E)     // Amethyst: avatar fill, quiet surfaces
    static let apricot = c(0xF5E6A3)   // Summer's Heat gold: accent, "in sync"
    static let amber = c(0xC8BADD)     // Viking Diva lavender: "maybe"
    static let ink = c(0xF8F9F4)       // Whitest White
    static let inkSoft = c(0xC5C1B8)   // Gettysburg Gray
    static let green = c(0xF5E6A3)     // likely free = gold, like the widget's clock arcs
    static let red = c(0xE89AAE)       // soft rose: busy, errors
    static let neutral = c(0x8E82A8)
    static let night = c(0x2A2140)     // text on gold buttons

    static var sunrise: LinearGradient {
        LinearGradient(colors: [c(0x382C4F), c(0x241C33)], startPoint: .top, endPoint: .bottom)
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

/// Each family member gets their own color, like a small glowing planet.
enum MemberPalette {
    static let colors: [Color] = [
        GH.c(0xF5E6A3),   // gold
        GH.c(0xC8BADD),   // lavender
        GH.c(0xE89AAE),   // rose
        GH.c(0xA9CBE8),   // moon blue
        GH.c(0xF3C3A1),   // peach
        GH.c(0xB5DCC6),   // mint
    ]
    static func color(_ index: Int) -> Color { colors[((index % colors.count) + colors.count) % colors.count] }
}

struct Avatar: View {
    var initials: String
    var size: CGFloat = 28
    /// The member's own color. Without one, the quiet amethyst circle (widgets).
    var tint: Color? = nil
    var body: some View {
        Text(initials.isEmpty ? "?" : initials)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(tint == nil ? GH.ink : GH.night)
            .frame(width: size, height: size)
            .background {
                if let tint {
                    Circle().fill(tint)
                        .overlay(Circle().fill(RadialGradient(colors: [.white.opacity(0.55), .clear, GH.night.opacity(0.35)],
                                                              center: UnitPoint(x: 0.3, y: 0.25),
                                                              startRadius: 0, endRadius: size * 0.85)))
                        .shadow(color: tint.opacity(0.5), radius: size * 0.16)
                } else {
                    Circle().fill(GH.peach)
                        .overlay(Circle().strokeBorder(GH.apricot.opacity(0.6), lineWidth: 1))
                }
            }
            .accessibilityHidden(true)
    }
}

extension ViewerBookingState {
    func label(otherName: String) -> String {
        switch self {
        case .suggested: return "Suggested"
        case .awaitingYou: return "Awaiting your confirmation"
        case .awaitingOther: return "Waiting for \(otherName)"
        case .confirmed: return "We'll be there"
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
