import AppIntents

/// Shows Kairos's actions in the Shortcuts app and Spotlight, so a personal automation
/// ("When I get a message from Mom") can run "Family texted me" without opening the app.
struct GoldenHourShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogTextIntent(), phrases: ["Log a family text in \(.applicationName)"],
                    shortTitle: "Family texted me", systemImageName: "message.fill")
        AppShortcut(intent: LogCallIntent(), phrases: ["Log a family call in \(.applicationName)"],
                    shortTitle: "Log a call", systemImageName: "phone.fill")
        AppShortcut(intent: BusyIntent(), phrases: ["I'm busy in \(.applicationName)"],
                    shortTitle: "I'm busy", systemImageName: "moon.zzz.fill")
        AppShortcut(intent: ClearBusyIntent(), phrases: ["I'm free in \(.applicationName)"],
                    shortTitle: "I'm free", systemImageName: "sun.max.fill")
    }
}
