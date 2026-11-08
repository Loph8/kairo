import SwiftUI
import KairoCore

/// Call flow. If the user configured a FaceTime audio destination we hand off to FaceTime; otherwise this
/// is a clearly labeled in-app SIMULATION. No audio or real call happens here.
struct CallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let personID: String
    @State private var seconds = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let p = model.state.person(personID)
        VStack(spacing: 20) {
            Spacer()
            Avatar(initials: p?.initials ?? "?", size: 96)
            Text(p?.name ?? "Unknown").font(.title.weight(.bold))
            if let url = model.callURL() {
                Text("Opens FaceTime audio to the destination you configured. Kairo can't see the outcome or length of that call.")
                    .font(.footnote).foregroundStyle(GH.inkSoft).multilineTextAlignment(.center)
                Button {
                    model.leftForFaceTime = true
                    openURL(url)
                } label: { Label("Open FaceTime audio", systemImage: "phone.fill").frame(maxWidth: 260) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else {
                Label("Demo call screen · simulation", systemImage: "flask").font(.footnote.weight(.semibold)).foregroundStyle(GH.amber)
                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60)).font(.system(.largeTitle, design: .rounded)).monospacedDigit()
                Text("No audio is transmitted and nobody is being called. Configure a FaceTime destination in Settings to call for real.")
                    .font(.footnote).foregroundStyle(GH.inkSoft).multilineTextAlignment(.center)
            }
            Spacer()
            Button(role: .destructive) { dismiss() } label: {
                Label(model.callURL() == nil ? "End demo call" : "Close", systemImage: "phone.down.fill").frame(maxWidth: 260)
            }.buttonStyle(.bordered).controlSize(.large)
        }
        .padding(24).foregroundStyle(GH.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GH.sunrise.ignoresSafeArea())
        .onReceive(timer) { _ in if model.callURL() == nil { seconds += 1 } }
        .presentationDetents([.large])
    }
}
