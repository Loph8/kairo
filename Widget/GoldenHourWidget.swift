import WidgetKit
import SwiftUI

struct GoldenHourWidget: Widget {
    let kind = "GoldenHourWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectMemberIntent.self, provider: GoldenProvider()) { entry in
            GoldenWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Golden Hour")
        .description("Who might be free, and when you can talk next. Estimates, not guarantees.")
        // systemSmall/Medium/Large also appear in StandBy; accessories on the Lock Screen.
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct GoldenHourWidgetBundle: WidgetBundle {
    var body: some Widget {
        GoldenHourWidget()
        SyncClockWidget()
        GoldenHourLiveActivity()
    }
}
