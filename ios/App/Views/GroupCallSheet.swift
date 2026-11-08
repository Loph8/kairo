import SwiftUI
import GoldenHourCore

/// Sets the family's shared group-call link. One person makes a FaceTime (or Zoom, Meet…) link once,
/// and from then on everyone's "Everyone" button opens that same call, so the whole family joins together.
struct GroupCallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Open the call right after saving (when the sheet was opened from the Call button).
    var callAfterSaving = true

    @State private var link = ""

    private var trimmed: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var looksLikeLink: Bool { trimmed.hasPrefix("https://") && URL(string: trimmed) != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("A group call needs one shared link. Make it once, and everyone in \(model.account?.familyName ?? "your family") can join the same call from Kairos.")
                        .font(Night.font(14)).foregroundStyle(GH.inkSoft)

                    steps

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Group call link").font(Night.font(13, .bold)).foregroundStyle(GH.ink)
                        HStack(spacing: 8) {
                            TextField("", text: $link,
                                      prompt: Text("https://facetime.apple.com/join#…").foregroundStyle(GH.inkSoft.opacity(0.6)))
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .foregroundStyle(GH.ink).tint(GH.apricot)
                            PasteButton(payloadType: String.self) { strings in
                                if let first = strings.first { link = first }
                            }
                            .labelStyle(.iconOnly)
                            .buttonBorderShape(.capsule)
                        }
                        .padding(14)
                        .background(GH.night.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        Text("FaceTime, Google Meet, Zoom, WhatsApp, Teams, Whereby or Jitsi links work.")
                            .font(Night.font(12)).foregroundStyle(GH.inkSoft)
                    }

                    if let text = model.banner {
                        BannerView(text: text) { model.banner = nil }
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Label(callAfterSaving ? "Save and call everyone" : "Save link", systemImage: "person.3.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryGlassButton()
                    .disabled(!looksLikeLink || model.working)

                    if model.account?.callLink != nil {
                        Button(role: .destructive) {
                            Task { await model.setCallLink(nil); if model.banner == nil { dismiss() } }
                        } label: {
                            Text("Remove link").frame(maxWidth: .infinity)
                        }
                        .font(Night.font(13))
                        .disabled(model.working)
                    }
                }
                .padding(20)
            }
            .background(SunriseBackground())
            .navigationTitle("Group call")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .onAppear { link = model.account?.callLink ?? "" }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 10) {
            step(1, "Open FaceTime and tap **Create Link**.")
            step(2, "Tap **Copy**, then come back here.")
            step(3, "Tap the paste button below and save.")
            Button {
                if let url = URL(string: "facetime://") { UIApplication.shared.open(url) }
            } label: {
                Label("Open FaceTime", systemImage: "video.fill").font(Night.font(14, .bold))
            }
            .tint(GH.apricot)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 20, tint: GH.peach)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(Night.font(13, .bold)).foregroundStyle(GH.night)
                .frame(width: 22, height: 22).background(Circle().fill(GH.apricot))
            Text(text).font(Night.font(14)).foregroundStyle(GH.ink)
        }
    }

    private func save() async {
        await model.setCallLink(trimmed)
        guard model.banner == nil, model.account?.callLink != nil else { return }
        dismiss()
        if callAfterSaving { _ = model.groupCall() }
    }
}
