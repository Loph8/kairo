import SwiftUI
import GoldenHourCore

/// Account, family, connections (calendars, contacts) and reset.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false
    @State private var confirmSignOut = false
    @State private var confirmLeave = false

    var body: some View {
        GlassPage(title: "Settings") {
            account
            calendar
            ContactInfoCard()
            ContactsCard()
            demo
            privacy
        }
        .confirmationDialog("Clear all history for this family?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { Task { await model.resetFamily() } }
        } message: {
            Text("Removes calls, calendar blocks, bookings and demo members. Real family members stay.")
        }
        .confirmationDialog("Leave \(model.account?.familyName ?? "this family")?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave family", role: .destructive) { Task { await model.leaveFamily() } }
        } message: {
            Text(leaveMessage)
        }
        .confirmationDialog("Sign out of Kairos?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await model.signOut() } }
        }
    }

    /// What leaving does, depending on whether anyone real stays behind.
    private var leaveMessage: String {
        let others = model.members.filter { !$0.simulated && $0.id != model.account?.memberId }.count
        if others == 0 {
            return "You're the last one here. The family, its history and its invite code will be deleted."
        }
        return "Your calls and busy times leave with you. The others stay. You can join again with the code."
    }

    private var account: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let me = model.me { MemberAvatar(member: me, size: 48) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.me?.name ?? "You").font(Night.font(17, .bold)).foregroundStyle(GH.ink)
                        Text(model.account?.email ?? "Signed in").font(Night.font(15)).foregroundStyle(GH.inkSoft)
                    }
                    Spacer()
                }
                Divider()
                row("Family", model.account?.familyName ?? "—", icon: "house.fill")
                if let code = model.account?.inviteCode {
                    HStack {
                        Label("Invite code", systemImage: "person.badge.plus").foregroundStyle(GH.ink)
                        Spacer()
                        Text(code).font(Night.font(17, .bold)).foregroundStyle(GH.ink)
                        ShareLink(item: "Join our family on Kairos with code \(code)") {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .tint(GH.apricot)
                    }
                }
                row("Members", "\(model.members.count)", icon: "person.3.fill")
                Button(role: .destructive) { confirmLeave = true } label: {
                    Label("Leave family", systemImage: "person.badge.minus").frame(maxWidth: .infinity)
                }
                .secondaryGlassButton()
                .disabled(model.working)
                Button(role: .destructive) { confirmSignOut = true } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity)
                }
                .secondaryGlassButton()
            }
        }
    }

    /// Google Calendar comes in through the iPhone's own Google account, which keeps it in sync both ways.
    @ViewBuilder
    private var googleCalendar: some View {
        if model.calendar.hasGoogle {
            Label("Google Calendar connected", systemImage: "g.circle.fill")
                .font(Night.font(14, .bold)).foregroundStyle(GH.green)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Add Google Calendar", systemImage: "g.circle").font(Night.font(14, .bold)).foregroundStyle(GH.ink)
                Text("iPhone Settings → Apps → Calendar → Calendar Accounts → Add Account → Google. Sign in and turn on Calendars. Kairos picks it up right away.")
                    .font(Night.font(12)).foregroundStyle(GH.inkSoft)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    Label("Open Settings", systemImage: "gear").frame(maxWidth: .infinity)
                }
                .secondaryGlassButton()
            }
            .padding(12)
            .background(GH.night.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var calendar: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Calendars", systemImage: "calendar").font(Night.font(17, .bold)).foregroundStyle(GH.ink)
                switch model.calendar.access {
                case .granted:
                    Label("Connected · \(model.calendar.eventCount) busy blocks in the last 4 weeks and next 4 days", systemImage: "checkmark.circle.fill")
                        .font(Night.font(15)).foregroundStyle(GH.green)
                    googleCalendar
                    if !model.calendar.accountNames.isEmpty {
                        Text("Reading: \(model.calendar.accountNames.joined(separator: ", "))")
                            .font(Night.font(12)).foregroundStyle(GH.inkSoft)
                    }
                    Text("Kairos learns your weekly rhythm from the last 4 weeks and avoids meetings in the next 4 days. Only busy times are shared, never titles or attendees.")
                        .font(Night.font(12)).foregroundStyle(GH.inkSoft)
                    if let t = model.calendar.lastSynced {
                        Text("Last synced \(t, style: .relative) ago").font(Night.font(11)).foregroundStyle(GH.inkSoft)
                    }
                    Button { Task { await model.pushCalendar() } } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                    }
                    .secondaryGlassButton()
                case .notAsked:
                    Text("Kairos avoids your meetings and can suggest moving one to free up a family call. It shares only busy times, never titles.")
                        .font(Night.font(15)).foregroundStyle(GH.inkSoft)
                    Button { Task { await model.connectCalendar() } } label: {
                        Label("Connect calendars", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                    }
                    .primaryGlassButton()
                case .denied, .restricted:
                    Text("Calendar access is off. Turn it on in iPhone Settings → Kairos → Calendars → Full Access.")
                        .font(Night.font(15)).foregroundStyle(GH.inkSoft)
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .secondaryGlassButton()
                }
            }
        }
    }

    private var demo: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Reset", systemImage: "arrow.counterclockwise").font(Night.font(17, .bold)).foregroundStyle(GH.ink)
                Button(role: .destructive) { confirmReset = true } label: {
                    Label("Clear history", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .secondaryGlassButton()
            }
            .disabled(model.working)
        }
    }

    private var privacy: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.shield.fill").font(Night.font(22, .bold)).foregroundStyle(GH.apricot)
            Text("We only know when you talk, never what you say.").font(Night.font(13, .bold)).foregroundStyle(GH.ink)
            Text("Stored: call and text times, whether someone picked up, busy times. Never: message text, call audio, event titles, contacts.")
                .font(Night.font(12)).multilineTextAlignment(.center).foregroundStyle(GH.inkSoft)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private func row(_ title: String, _ value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(GH.ink)
            Spacer()
            Text(value).foregroundStyle(GH.inkSoft)
        }
    }

}
