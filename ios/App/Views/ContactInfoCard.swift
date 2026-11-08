import SwiftUI
import GoldenHourCore

/// Settings → "Your number & apps": the number your family calls you on, and the call apps you use.
/// Saved once on the server and shared with every family you're in, so nobody has to type your number.
struct ContactInfoCard: View {
    @Environment(AppModel.self) private var model

    /// Apps someone can be reached on besides their phone number. Keys match the server's CONTACT_APPS.
    private static let apps: [CallApp] = [.whatsapp, .kakaotalk, .wechat, .line, .telegram, .messenger, .instagram]

    @State private var phone = ""
    @State private var handles: [String: String] = [:]
    @State private var saved = false

    private var normalized: String? { PhoneNumber.normalized(phone) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label("Your number & apps", systemImage: "phone.badge.checkmark")
                    .font(Night.font(16, .bold)).foregroundStyle(GH.ink)
                Text("Your family calls you on this number, one-to-one or in a group call. Add the apps you use and they can reach you there too.")
                    .font(Night.font(13)).foregroundStyle(GH.inkSoft)

                row(title: "Phone number", symbol: "phone.fill", text: $phone, prompt: "+1 919 555 0123", keyboard: .phonePad)
                if !phone.isEmpty, normalized == nil {
                    Text("Include the country code, like +1 for the US or +82 for Korea.")
                        .font(Night.font(12)).foregroundStyle(GH.apricot)
                }

                ForEach(Self.apps) { app in
                    row(title: app.name, symbol: app.symbol, text: binding(app),
                        prompt: app.handle == .username ? "username" : "number, or leave empty to use your phone",
                        keyboard: app.handle == .username ? .asciiCapable : .phonePad)
                }

                Button {
                    Task { await save() }
                } label: {
                    Label(saved ? "Saved" : "Save", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .primaryGlassButton()
                .disabled(normalized == nil || model.working)
            }
        }
        .onAppear(perform: load)
        .onChange(of: model.me?.phone) { load() }
    }

    private func row(title: String, symbol: String, text: Binding<String>, prompt: String, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(GH.apricot)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Night.font(12, .bold)).foregroundStyle(GH.inkSoft)
                TextField("", text: text, prompt: Text(prompt).foregroundStyle(GH.inkSoft.opacity(0.5)))
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .foregroundStyle(GH.ink).tint(GH.apricot)
                    .onChange(of: text.wrappedValue) { saved = false }
            }
        }
        .padding(10)
        .background(GH.night.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func binding(_ app: CallApp) -> Binding<String> {
        Binding(get: { handles[app.rawValue] ?? "" }, set: { handles[app.rawValue] = $0 })
    }

    private func load() {
        phone = model.me?.phone ?? PhoneNumber.dialPrefix()
        handles = model.me?.apps ?? [:]
    }

    private func save() async {
        guard let number = normalized else { return }
        let apps = handles.compactMapValues { v -> String? in
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        await model.setContact(phone: number, apps: apps)
        saved = model.banner == nil
    }
}
