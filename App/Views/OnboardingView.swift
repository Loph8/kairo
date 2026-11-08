import SwiftUI
import KairoCore

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var name = ""
    @State private var tzID = TimeZone.current.identifier
    @State private var wake = Calendar.current.date(from: DateComponents(hour: 7, minute: 0))!
    @State private var bed = Calendar.current.date(from: DateComponents(hour: 22, minute: 30))!
    @State private var workBusy = true
    @State private var duration = 30

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $step) {
                page { welcome }.tag(0)
                page { basics }.tag(1)
                page { routine }.tag(2)
                page { family }.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
        .background(GH.sunrise.ignoresSafeArea())
    }

    func page<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) { c() }.padding(24).padding(.bottom, 40) }
    }

    var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "sun.horizon.fill").font(.system(size: 56)).foregroundStyle(GH.apricot)
            Text("Kairo").font(.largeTitle.weight(.bold))
            Text("Find a little time together.").font(.title3)
            Text("Kairo estimates good times from your preferences and activity inside Kairo. It uses call and reply timing, never what you say.")
                .foregroundStyle(GH.inkSoft)
            Text("We won't ask for contacts, microphone, notifications or Focus access until a feature needs it.")
                .font(.footnote).foregroundStyle(GH.inkSoft)
            Button("Get started") { withAnimation { step = 1 } }.buttonStyle(.borderedProminent).controlSize(.large)
        }.foregroundStyle(GH.ink)
    }

    var basics: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About you").font(.title2.weight(.bold))
            TextField("Your name", text: $name).textFieldStyle(.roundedBorder).textContentType(.name)
            Picker("Time zone", selection: $tzID) {
                ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
            }
            Text("Defaults to this device's time zone.").font(.caption).foregroundStyle(GH.inkSoft)
            Button("Next") { withAnimation { step = 2 } }.buttonStyle(.borderedProminent)
        }.foregroundStyle(GH.ink)
    }

    var routine: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your day").font(.title2.weight(.bold))
            DatePicker("Wake up", selection: $wake, displayedComponents: .hourAndMinute)
            DatePicker("Bedtime", selection: $bed, displayedComponents: .hourAndMinute)
            Text("Between bedtime and wake-up counts as quiet hours. We won't suggest calls then.").font(.caption).foregroundStyle(GH.inkSoft)
            Toggle("Busy on weekdays 9 AM–5 PM", isOn: $workBusy)
            Picker("Usual call length", selection: $duration) { ForEach([15, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) } }
                .pickerStyle(.segmented)
            Button("Next") { withAnimation { step = 3 } }.buttonStyle(.borderedProminent)
        }.foregroundStyle(GH.ink)
    }

    var family: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your family").font(.title2.weight(.bold))
            Text("Invitations need a backend and aren't wired up in this build. Try the demo family to see everything working.")
                .foregroundStyle(GH.inkSoft)
            Button { finish(demo: true) } label: { Label("Try demo family", systemImage: "flask").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Text("The demo uses clearly labeled synthetic history, not real data.").font(.caption).foregroundStyle(GH.inkSoft)
            Button("Start with just me") { finish(demo: false) }.buttonStyle(.bordered)
        }.foregroundStyle(GH.ink)
    }

    func minutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d); return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    func finish(demo: Bool) {
        let busy = workBusy ? [WeeklyWindow(weekdays: [2, 3, 4, 5, 6], startMinute: 540, endMinute: 1020, label: "Work")] : []
        let me = Person(id: "you", name: name.isEmpty ? "You" : name, relationship: "You",
                        city: tzID.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? tzID,
                        timeZoneID: tzID, prefs: .init(wakeMinute: minutes(wake), bedMinute: minutes(bed),
                                                       busyWindows: busy, preferredCallMinutes: duration))
        Task { await model.perform { try await model.repo.completeOnboarding(profile: me, useDemoFamily: demo) } }
    }
}
