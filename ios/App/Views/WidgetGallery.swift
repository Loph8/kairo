#if DEBUG
import SwiftUI
import WidgetKit
import CoreText

/// Debug only (launch with --widget-gallery): the "In Sync" widget at real Home Screen sizes,
/// so it can be checked in the Simulator without adding it to the Home Screen.
struct WidgetGallery: View {
    private let small = CGSize(width: 170, height: 170)
    private let medium = CGSize(width: 364, height: 170)
    private let large = CGSize(width: 364, height: 382)

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    tile(SyncPreview.inSync, .systemSmall, small)
                    tile(SyncPreview.waiting, .systemSmall, small)
                }
                tile(SyncPreview.inSync, .systemMedium, medium)
                tile(SyncPreview.almost, .systemMedium, medium)
                tile(SyncPreview.inSync, .systemLarge, large)
            }
            .padding(.vertical, 70)
        }
        .background(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.7)], startPoint: .top, endPoint: .bottom))
    }

    private func tile(_ entry: GoldenEntry, _ family: WidgetFamily, _ size: CGSize) -> some View {
        let phase = entry.focus.map { entry.syncPhase(for: $0) } ?? .unknown
        let glow = family == .systemMedium ? UnitPoint(x: 0.22, y: 0.52) : UnitPoint(x: 0.5, y: 0.52)
        return SyncClockEntryView(entry: entry, familyOverride: family)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(NightSkyBackground(phase: phase, glowCenter: glow))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
#endif
