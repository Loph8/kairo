import ActivityKit
import Foundation

/// Live Activity model. Compiled into BOTH the app (starts/updates) and the widget extension (renders).
struct GoldenHourActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Booking: String, Codable { case confirmed, rescheduled, canceled }
        var callStart: Date          // REAL clock instant (demo offset already removed)
        var booking: Booking
        var otherLocalTimeLabel: String   // e.g. "Tomorrow, 9:30 AM for Mom"
    }
    var proposalID: String
    var personID: String
    var personName: String
    var scheduledLabel: String       // viewer-local, e.g. "Today, 8:00 PM"
}
