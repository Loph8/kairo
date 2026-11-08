import WidgetKit
import SwiftUI

struct GoldenHourWidget: Widget {
    let kind = "GoldenHourWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectMemberIntent.self, provider: GoldenProvider()) { entry in
            GoldenWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Kairos")
        .description("Who might be free, and when you can talk next. Estimates, not guarantees.")
        // Lock Screen only; the Home Screen and StandBy use the "In Sync" clock widget.
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct GoldenHourWidgetBundle: WidgetBundle {
    var body: some Widget {
        SyncClockWidget()
        GoldenHourWidget()
        GoldenHourLiveActivity()
    }
}
