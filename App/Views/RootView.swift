import SwiftUI
import KairoCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if !model.loaded {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.ivory)
            } else if !model.state.settings.onboardingComplete {
                OnboardingView()
            } else {
                TabView(selection: $model.tab) {
                    NavigationStack(path: $model.path) { DashboardView() }
                        .tabItem { Label("Family", systemImage: "sun.horizon.fill") }.tag(AppTab.family)
                    NavigationStack { ScheduleView() }
                        .tabItem { Label("Schedule", systemImage: "calendar") }.tag(AppTab.schedule)
                    NavigationStack { SettingsView() }
                        .tabItem { Label("Settings", systemImage: "gearshape") }.tag(AppTab.settings)
                }
            }
        }
        .background(Palette.ivory.ignoresSafeArea())
        .sheet(item: Binding(get: { model.callPersonID.map(CallTarget.init) }, set: { if $0 == nil { model.callEnded() } })) { t in
            CallView(personID: t.id)
        }
        .confirmationDialog("Did you connect?", isPresented: Binding(
            get: { model.feedbackProposalID != nil }, set: { if !$0 { Task { await model.submitFeedback(.skip) } } }),
            titleVisibility: .visible) {
            Button("Yes") { Task { await model.submitFeedback(.yes) } }
            Button("No") { Task { await model.submitFeedback(.no) } }
            Button("Skip", role: .cancel) { Task { await model.submitFeedback(.skip) } }
        } message: {
            Text("This is your own answer. Kairo can't see whether a call connected, and uses it only as a weak signal.")
        }
    }
}

struct CallTarget: Identifiable { var id: String }

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.card))
            .shadow(color: Palette.ink.opacity(0.06), radius: 8, y: 2)
    }
}

struct BannerView: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "info.circle").font(.footnote).foregroundStyle(Palette.ink)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Palette.peach.opacity(0.6)))
    }
}
