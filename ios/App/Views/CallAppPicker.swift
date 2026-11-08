import SwiftUI
import GoldenHourCore

/// Choose which app a family member is called on, plus their number or username for that app.
struct CallAppPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let member: ServerState.Member

    @State private var app: CallApp = .facetimeAudio
    @State private var handle = ""

    private var linked: ContactsLink.Linked? { model.contacts.linked[member.id] }
    private var fallbackHandle: String? { linked?.phone ?? linked?.email }
    private var canSave: Bool {
        app.handle == .none || !handle.trimmingCharacters(in: .whitespaces).isEmpty || fallbackHandle != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Kairos opens the app you pick. When you come back it asks whether \(member.name) picked up. It never sees the call itself.")
                        .font(Night.font(14)).foregroundStyle(GH.inkSoft)

                    VStack(spacing: 8) {
                        ForEach(CallApp.allCases) { option in appRow(option) }
                    }

                    if app.handle != .none {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(app.handlePrompt).font(Night.font(13, .bold)).foregroundStyle(GH.ink)
                            TextField("", text: $handle,
                                      prompt: Text(fallbackHandle ?? "").foregroundStyle(GH.inkSoft.opacity(0.6)))
                                .keyboardType(app.handle == .username ? .asciiCapable : .phonePad)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .foregroundStyle(GH.ink).tint(GH.apricot)
                                .padding(14)
                                .background(GH.night.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            if let fallbackHandle, handle.isEmpty, app.handle != .username {
                                Text("Leave empty to use \(fallbackHandle) from Contacts.")
                                    .font(Night.font(12)).foregroundStyle(GH.inkSoft)
                            }
                        }
                    }

                    Button {
                        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
                        model.setCallChoice(CallChoice(app: app, handle: trimmed.isEmpty ? nil : trimmed), for: member)
                        dismiss()
                        _ = model.call(member)
                    } label: {
                        Label("Call \(member.name) on \(app.name)", systemImage: app.symbol).frame(maxWidth: .infinity)
                    }
                    .primaryGlassButton()
                    .disabled(!canSave)
                }
                .padding(20)
            }
            .background(SunriseBackground())
            .navigationTitle("Call \(member.name) with")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if let saved = model.callChoice(for: member) {
                app = saved.app
                handle = saved.handle ?? ""
            }
        }
    }

    private func appRow(_ option: CallApp) -> some View {
        let installed = option.isInstalled
        let selected = option == app
        return Button {
            app = option
            if option.handle == .username, handle.contains("+") || handle.allSatisfy(\.isNumber) { handle = "" }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.symbol).frame(width: 28).foregroundStyle(selected ? GH.apricot : GH.inkSoft)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name).font(Night.font(16, .bold)).foregroundStyle(GH.ink)
                    Text(installed ? option.whatHappens : "Not installed on this iPhone")
                        .font(Night.font(12)).foregroundStyle(GH.inkSoft)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(GH.apricot) }
            }
            .padding(14)
            .background(selected ? GH.peach.opacity(0.6) : GH.night.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? GH.apricot.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!installed)
        .opacity(installed ? 1 : 0.45)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
