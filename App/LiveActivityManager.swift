import ActivityKit
import UserNotifications
import Foundation
import KairoCore

/// Activation policy
/// - ActivityKit cannot start an activity from the widget extension or the background. It is
///   requested only while the app is foregrounded (or via push-to-start, deferred here).
/// - An activity may stay active at most ~8 hours, so we only start within `activationWindow`
///   of the call. Calls booked further out get a scheduled local notification instead.
/// - ActivityKit *push updates* (activity push tokens via APNs) are separate from VoIP pushes
///   (PushKit/CallKit for incoming calls). This manager uses neither; updates are local.
@MainActor
final class LiveActivityManager {
    static let activationWindow: TimeInterval = 60 * 60

    func sync(state: AppState, now: Date, clockOffset: TimeInterval) async -> String? {
        guard let me = state.viewerID.nonEmpty else { return nil }
        let live = Activity<KairoActivityAttributes>.activities
        let upcoming = state.proposals.filter { $0.status == .confirmed && $0.participants.contains(me) && $0.end > now }
            .sorted { $0.start < $1.start }.first

        // End activities whose booking was canceled/rescheduled/finished.
        for a in live where a.attributes.proposalID != upcoming?.id {
            let canceled = state.proposals.first { $0.id == a.attributes.proposalID }?.status == .canceled
            var s = a.content.state
            if canceled { s.booking = .canceled }
            await a.end(ActivityContent(state: s, staleDate: nil), dismissalPolicy: canceled ? .after(.now + 600) : .immediate)
        }
        guard let p = upcoming, let otherID = p.participants.first(where: { $0 != me }),
              let other = state.person(otherID), let mePerson = state.person(me) else { return nil }

        let realStart = p.start.addingTimeInterval(-clockOffset)
        let untilStart = p.start.timeIntervalSince(now)
        let fmt24 = state.settings.use24Hour
        let attrs = KairoActivityAttributes(
            proposalID: p.id, personID: other.id, personName: other.relationship,
            scheduledLabel: TimeKit.describe(p.start, in: mePerson.timeZone, reference: now, use24Hour: fmt24))
        let content = ActivityContent(
            state: KairoActivityAttributes.ContentState(
                callStart: realStart, booking: .confirmed,
                otherLocalTimeLabel: "\(TimeKit.describe(p.start, in: other.timeZone, reference: now, use24Hour: fmt24)) for \(other.relationship)"),
            staleDate: realStart.addingTimeInterval(15 * 60))

        if let existing = live.first(where: { $0.attributes.proposalID == p.id }) {
            await existing.update(content); return nil
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activities are turned off for Kairo. Enable them in Settings to see the countdown on your Lock Screen."
        }
        guard untilStart <= Self.activationWindow else {
            return "Booked. The Lock Screen countdown starts within an hour of the call (Live Activities can't last for days). A reminder is scheduled if notifications are on."
        }
        do {
            _ = try Activity.request(attributes: attrs, content: content, pushType: nil)
            return nil
        } catch {
            return "Couldn't start the Live Activity (\(error.localizedDescription)). The booking is unaffected."
        }
    }
}

enum NotificationScheduler {
    /// Asks for notification permission only when a booking first needs a reminder.
    @MainActor
    static func requestIfNeeded(model: AppModel) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            try? await model.repo.updateSettings { $0.notificationsEnabled = true }
        }
        await scheduleReminders(model: model)
    }

    @MainActor
    static func scheduleReminders(model: AppModel) async {
        let center = UNUserNotificationCenter.current()
        guard (await center.notificationSettings()).authorizationStatus == .authorized else { return }
        let st = await model.repo.loadState()
        let now = Date()
        for p in st.proposals where p.status == .confirmed && p.participants.contains(st.viewerID) {
            let fire = p.start.addingTimeInterval(-st.clockOffset - 10 * 60)   // real clock; demo offset removed
            guard fire > now else { continue }
            let c = UNMutableNotificationContent()
            c.title = "Call coming up"
            c.body = "Your Kairo call starts in 10 minutes."
            c.userInfo = ["url": DeepLink.proposal(p.id).url.absoluteString]
            let req = UNNotificationRequest(identifier: "call-\(p.id)", content: c,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSince(now), repeats: false))
            try? await center.add(req)   // same identifier replaces: idempotent
        }
    }
}
