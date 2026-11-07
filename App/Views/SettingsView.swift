import SwiftUI
import GoldenHourCore
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmDelete = false
    @State private var confirmClear = false
    @State private var destination = ""

    var body: some View {
        let s = model.state.settings
        Form {
            Section("What Golden Hour collects") {
                Text("On this device: call outcomes (answered, missed, declined), call length, reply timing, first/last activity, and your Busy and Book taps. Metadata only.")
                Text("Never collected for availability: message text, audio, contacts, Phone or Messages history.")
            }
            Section("What is shared") {
                Text("Family members see a coarse state (Likely free, Maybe free, Busy, Quiet hours, Learning) with a coarse evidence level, valid for a short period. Raw events never leave your device in this architecture. Numeric scores are not shared.")
                Text("The messaging/calling provider you use may process its own transport metadata. That is separate from the availability model.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Learning") {
                Toggle("Pause learning", isOn: Binding(get: { s.learningPaused }, set: { v in Task { await model.perform { try await model.repo.setLearningPaused(v) } } }))
                Button("Delete learned availability", role: .destructive) { confirmDelete = true }
                Button("Clear demo data", role: .destructive) { confirmClear = true }
            }
            Section("Quiet hours & preferences") {
                if let me = model.viewer { QuietHoursEditor(person: me) }
            }
            Section("Display") {
                Toggle("24-hour time", isOn: Binding(get: { s.use24Hour }, set: { v in Task { await model.perform { try await model.repo.updateSettings { $0.use24Hour = v } } } }))
            }
            Section("Calling") {
                TextField("FaceTime audio phone or email (optional)", text: $destination)
                    .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    .onSubmit { save() }
                Text("Only used if you enter it. Without one, Call opens an in-app demo call screen. Golden Hour can't see whether a FaceTime call connected.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Text(s.notificationsEnabled ? "Enabled for call reminders." : "Off. We ask the first time a booking needs a reminder.")
                Button("Review in iOS Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
            }
            Section("Focus (optional)") {
                Toggle("Use Focus status as a hint", isOn: .constant(false)).disabled(true)
                Text("Not implemented in this build. It would need explicit Focus Status authorization and only reveals whether a Focus is on, never its name or reason.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section { NavigationLink("Demo controls") { DemoControlsView() } } footer: {
                Text("For presenters. Kept separate from the product UI.")
            }
        }
        .scrollContentBackground(.hidden).background(GH.sunrise.ignoresSafeArea())
        .navigationTitle("Privacy & Settings")
        .onAppear { destination = s.callDestination ?? "" }
        .onDisappear { save() }
        .confirmationDialog("Delete all learned availability on this device?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await model.perform { try await model.repo.deleteLearnedAvailability() } } }
        } message: { Text("Estimates return to \"Learning\". This can't be undone.") }
        .confirmationDialog("Clear the demo family and synthetic history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear demo data", role: .destructive) { Task { await model.perform { try await model.repo.clearDemoData() } } }
        }
    }

    func save() {
        let v = destination.trimmingCharacters(in: .whitespaces)
        Task { await model.perform { try await model.repo.updateSettings { $0.callDestination = v.isEmpty ? nil : v } } }
    }
}

struct QuietHoursEditor: View {
    @Environment(AppModel.self) private var model
    let person: Person
    var body: some View {
        DatePicker("Wake up", selection: binding(\.wakeMinute), displayedComponents: .hourAndMinute)
        DatePicker("Bedtime", selection: binding(\.bedMinute), displayedComponents: .hourAndMinute)
        Stepper("Call length: \(person.prefs.preferredCallMinutes) min", value: Binding(
            get: { person.prefs.preferredCallMinutes },
            set: { v in var p = person.prefs; p.preferredCallMinutes = v; save(p) }), in: 15...120, step: 15)
    }
    func binding(_ kp: WritableKeyPath<LocalPreferences, Int>) -> Binding<Date> {
        Binding(get: {
            let m = person.prefs[keyPath: kp]
            return Calendar.current.date(from: DateComponents(hour: m / 60, minute: m % 60)) ?? .now
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            var p = person.prefs; p[keyPath: kp] = (c.hour ?? 0) * 60 + (c.minute ?? 0); save(p)
        })
    }
    func save(_ p: LocalPreferences) { Task { await model.perform { try await model.repo.updatePreferences(personID: person.id, p) } } }
}
