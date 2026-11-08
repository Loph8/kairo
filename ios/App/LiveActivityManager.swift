import ActivityKit
import Foundation
import UserNotifications
import GoldenHourCore

/// Shows the next booked family call on the Lock Screen and in the Dynamic Island,
/// starting an hour before the call and ending 15 minutes after it starts.
@MainActor
final class LiveActivityManager {
    static let activationWindow: TimeInterval = 3600
    static let lingerAfterStart: TimeInterval = 15 * 60

    /// Returns a message for the banner when the user needs to do something, else nil.
    func sync(state: ServerState, viewerID: String, clockOffset: TimeInterval) async -> String? {
        let now = Date().addingTimeInterval(clockOffset)
        let next = state.bookings
            .filter { $0.status == "booked" && $0.acceptedBy.contains(viewerID) && $0.start.addingTimeInterval(Self.lingerAfterStart) > now }
            .min { $0.start < $1.start }

        let current = Activity<GoldenHourActivityAttributes>.activities
        guard let next else {
            for a in current { await a.end(nil, dismissalPolicy: .immediate) }
            return nil
        }
        let id = Self.id(next)
        for a in current where a.attributes.proposalID != id { await a.end(nil, dismissalPolicy: .immediate) }
        guard next.start.timeIntervalSince(now) <= Self.activationWindow else { return nil }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return "Live Activities are off for Kairos. Turn them on in Settings to see the countdown in the Dynamic Island."
        }

        let others = state.members.filter { $0.id != viewerID && next.acceptedBy.contains($0.id) }
        let realStart = next.start.addingTimeInterval(-clockOffset)
        let content = GoldenHourActivityAttributes.ContentState(
            callStart: realStart, booking: .confirmed,
            otherLocalTimeLabel: others.first.map { "\(Self.time(next.start, tz: $0.tz)) for \($0.name)" } ?? "")
        let staleAt = realStart.addingTimeInterval(Self.lingerAfterStart)

        if let existing = current.first(where: { $0.attributes.proposalID == id }) {
            await existing.update(ActivityContent(state: content, staleDate: staleAt))
            return nil
        }
        let me = state.members.first { $0.id == viewerID }
        let attrs = GoldenHourActivityAttributes(
            proposalID: id, personID: others.first?.id ?? "",
            personName: others.count > 1 ? "Family" : (others.first?.name ?? "Family"),
            scheduledLabel: me.map { Self.time(next.start, tz: $0.tz) } ?? "")
        do {
            _ = try Activity.request(attributes: attrs, content: ActivityContent(state: content, staleDate: staleAt), pushType: nil)
            return nil
        } catch {
            return "Couldn't start the Lock Screen countdown. It will try again when you reopen the app."
        }
    }

    func endAll() async {
        for a in Activity<GoldenHourActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
    }

    nonisolated static func id(_ b: ServerState.Booking) -> String { FamilyProposalID.make(b.start) }

    static func time(_ d: Date, tz: String) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: tz)
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
}

/// A reminder 10 minutes before the call, for when the phone is locked and the Live Activity is not in view.
enum Reminders {
    static let lead: TimeInterval = 10 * 60
    static let prefix = "call-"

    static func schedule(for booking: ServerState.Booking?, state: ServerState, viewerID: String, clockOffset: TimeInterval) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        guard let booking else { center.removePendingNotificationRequests(withIdentifiers: pending); return }
        let id = prefix + LiveActivityManager.id(booking)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0 != id })
        guard !pending.contains(id) else { return }

        let fire = booking.start.addingTimeInterval(-clockOffset - lead)
        guard fire > Date(), !ProcessInfo.processInfo.arguments.contains("--screenshots") else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let names = state.members.filter { $0.id != viewerID && booking.acceptedBy.contains($0.id) }.map(\.name)
        let content = UNMutableNotificationContent()
        content.title = "Kairos in 10 minutes"
        content.body = names.isEmpty ? "Your family call starts soon." : "Call with \(ListFormatter.localizedString(byJoining: names)) starts soon."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["url": DeepLink.dashboard.url.absoluteString]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSinceNow, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
