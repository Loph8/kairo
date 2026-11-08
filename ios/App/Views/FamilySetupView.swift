import SwiftUI
import GoldenHourCore

/// After sign-in: tell us about your day, then start a family or join one with an invite code.
struct FamilySetupView: View {
    @Environment(AppModel.self) private var model
    /// Set when adding another family from the Family tab: shows Cancel instead of Sign out, and closes when done.
    var onDone: (() -> Void)? = nil
    @State private var mode: Mode = .create
    @State private var name = ""
    @State private var familyName = ""
    @State private var code = ""
    @State private var city = ""
    @State private var phone = PhoneNumber.dialPrefix()
    @State private var wake = Self.date(7, 0)
    @State private var bed = Self.date(23, 0)
    @State private var hasBusy = true
    @State private var busyFrom = Self.date(9, 0)
    @State private var busyTo = Self.date(17, 0)
    private enum Mode: String, CaseIterable { case create = "Start a family", join = "Join with a code" }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(onDone == nil ? "Your family" : "Add a family").font(Night.font(34, .bold)).foregroundStyle(GH.ink)
                    Text(onDone == nil
                         ? "This helps us guess when you're free until we learn from real calls."
                         : "Start another family or join one with its code. You can switch between them on the Family tab.")
                        .font(Night.font(16)).foregroundStyle(GH.inkSoft).multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                Picker("", selection: $mode.animation(.smooth)) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        field("Your name", text: $name, prompt: "e.g. Eunice")
                        if mode == .create {
                            field("Family name", text: $familyName, prompt: "e.g. The Kims")
                        } else {
                            field("Invite code", text: $code, prompt: "ABC234")
                                .textInputAutocapitalization(.characters)
                                .font(Night.font(17))
                        }
                        field("City", text: $city, prompt: "e.g. Durham")
                        VStack(alignment: .leading, spacing: 4) {
                            field("Your phone number", text: $phone, prompt: "+1 919 555 0123")
                                .keyboardType(.phonePad)
                            Text(phoneHint).font(Night.font(12))
                                .foregroundStyle(phoneOK || phone.count < 5 ? GH.inkSoft : GH.apricot)
                        }
                        HStack {
                            Label(TimeZone.current.identifier.replacingOccurrences(of: "_", with: " "), systemImage: "globe")
                            Spacer()
                            Text(LocalTime.flag(for: TimeZone.current.identifier))
                        }
                        .font(Night.font(13)).foregroundStyle(GH.inkSoft)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your usual day").font(Night.font(17, .bold)).foregroundStyle(GH.ink)
                        DatePicker("I wake up", selection: $wake, displayedComponents: .hourAndMinute)
                        DatePicker("I go to bed", selection: $bed, displayedComponents: .hourAndMinute)
                        Toggle("Busy most weekdays", isOn: $hasBusy.animation())
                        if hasBusy {
                            DatePicker("From", selection: $busyFrom, displayedComponents: .hourAndMinute)
                            DatePicker("To", selection: $busyTo, displayedComponents: .hourAndMinute)
                        }
                    }
                    .tint(GH.apricot)
                }

                if onDone != nil, let text = model.banner {
                    BannerView(text: text) { model.banner = nil }
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if model.working { ProgressView() }
                        Text(mode == .create ? "Create family" : "Join family").bold()
                    }
                    .frame(maxWidth: .infinity)
                }
                .primaryGlassButton()
                .disabled(!canSubmit || model.working)

                if let onDone {
                    Button("Cancel", action: onDone)
                        .font(Night.font(13)).foregroundStyle(GH.inkSoft)
                } else {
                    Button("Sign out") { Task { await model.signOut() } }
                        .font(Night.font(13)).foregroundStyle(GH.inkSoft)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { if let saved = model.me?.phone { phone = saved } }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Night.font(12, .bold)).foregroundStyle(GH.inkSoft)
            TextField(prompt, text: text)
                .padding(12).glassSurface(cornerRadius: 14, interactive: true)
        }
    }

    private var canSubmit: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        switch mode {
        case _ where !phoneOK: return false
        case .create: return hasName && !familyName.trimmingCharacters(in: .whitespaces).isEmpty
        case .join: return hasName && code.trimmingCharacters(in: .whitespaces).count == 6
        }
    }

    private func submit() async {
        let profile = Profile(
            name: name.trimmingCharacters(in: .whitespaces),
            timeZoneID: TimeZone.current.identifier,
            city: city.trimmingCharacters(in: .whitespaces),
            wake: Self.hhmm(wake), bed: Self.hhmm(bed),
            busy: hasBusy ? [[Self.hhmm(busyFrom), Self.hhmm(busyTo)]] : [],
            phone: PhoneNumber.normalized(phone))
        let before = model.account?.familyId
        switch mode {
        case .create: await model.createFamily(name: familyName.trimmingCharacters(in: .whitespaces), profile: profile)
        case .join: await model.joinFamily(code: code.trimmingCharacters(in: .whitespaces).uppercased(), profile: profile)
        }
        if model.account?.familyId != before { onDone?() }
    }

    static func date(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }

    private var phoneOK: Bool { PhoneNumber.normalized(phone) != nil }
    private var phoneHint: String {
        phoneOK || phone.count < 5
            ? "Your family calls you on this number, one-to-one or in a group call. It's tied to the email you signed in with."
            : "Include the country code, like +1 for the US or +82 for Korea."
    }

    static func hhmm(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
