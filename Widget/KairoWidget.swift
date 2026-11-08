import WidgetKit
import SwiftUI

struct KairoWidget: Widget {
    let kind = "KairoWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectMemberIntent.self, provider: GoldenProvider()) { entry in
            GoldenWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Kairo")
        .description("Who might be free, and when you can talk next. Estimates, not guarantees.")
        // systemSmall/Medium/Large also appear in StandBy; accessories on the Lock Screen.
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct KairoWidgetBundle: WidgetBundle {
    var body: some Widget {
        KairoWidget()
        KairoLiveActivity()
    }
}
