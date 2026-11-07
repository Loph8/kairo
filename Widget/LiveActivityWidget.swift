import ActivityKit
import WidgetKit
import SwiftUI
import GoldenHourCore

struct GoldenHourLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoldenHourActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .activityBackgroundTint(Color(UIColor(hex: 0xFFE8D2)))
                .activitySystemActionForegroundColor(GH.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.personName, systemImage: "phone.fill").font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) { CountdownText(state: context.state, font: .title3) }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.scheduledLabel).font(.subheadline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(bookingText(context.state)).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if context.state.booking != .canceled {
                            Link(destination: DeepLink.call(context.attributes.personID).url) {
                                Label("Open call", systemImage: "phone.arrow.up.right")
                            }.font(.caption.weight(.semibold))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "sun.horizon.fill").foregroundStyle(GH.apricot)
            } compactTrailing: {
                CountdownText(state: context.state, font: .caption2).frame(maxWidth: 48)
            } minimal: {
                Image(systemName: context.state.booking == .canceled ? "slash.circle" : "phone.fill").foregroundStyle(GH.apricot)
            }
            .widgetURL(DeepLink.proposal(context.attributes.proposalID).url)
        }
    }
}

func bookingText(_ s: GoldenHourActivityAttributes.ContentState) -> String {
    switch s.booking {
    case .confirmed: return "Booked · \(s.otherLocalTimeLabel)"
    case .rescheduled: return "Rescheduled · \(s.otherLocalTimeLabel)"
    case .canceled: return "Canceled"
    }
}

/// System-rendered timer: keeps counting without the app or widget executing code.
struct CountdownText: View {
    let state: GoldenHourActivityAttributes.ContentState
    var font: Font
    var body: some View {
        if state.booking == .canceled {
            Text("Canceled").font(font)
        } else if state.callStart > .now {
            Text(timerInterval: Date.now...state.callStart, countsDown: true).font(font.monospacedDigit())
                .multilineTextAlignment(.trailing)
        } else {
            Text("Now").font(font.weight(.bold))
        }
    }
}

struct LockScreenActivityView: View {
    let context: ActivityViewContext<GoldenHourActivityAttributes>
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.horizon.fill").font(.title2).foregroundStyle(GH.apricot)
            VStack(alignment: .leading, spacing: 2) {
                Text("Call with \(context.attributes.personName)").font(.headline).foregroundStyle(Color(UIColor(hex: 0x3B2A20)))
                Text(context.attributes.scheduledLabel).font(.subheadline)
                Text(bookingText(context.state)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                CountdownText(state: context.state, font: .title2.weight(.bold))
                if context.state.booking != .canceled {
                    Link(destination: DeepLink.call(context.attributes.personID).url) {
                        Label("Open call", systemImage: "phone.fill").font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}
