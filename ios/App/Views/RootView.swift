import SwiftUI
import GoldenHourCore
import UserNotifications

/// Sign in → make or join a family → the three tabs. Every screen sits on the same sunrise glass.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            SunriseBackground()
            switch model.phase {
            case .loading:
                ProgressView().controlSize(.large).tint(GH.apricot)
            case .signedOut:
                SignInView().transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .needsFamily:
                FamilySetupView().transition(.move(edge: .trailing).combined(with: .opacity))
            case .ready:
                tabs.transition(.opacity)
                    .task {   // ask only once they're in a family, so the request makes sense
                        guard !ProcessInfo.processInfo.arguments.contains("--screenshots") else { return }
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                    }
            }
        }
        .animation(.smooth(duration: 0.45), value: model.phase)
        .overlay(alignment: .top) {
            if let text = model.banner, model.phase != .ready {
                BannerView(text: text) { model.banner = nil }.padding(.horizontal)
            }
        }
        .confirmationDialog(pickedUpTitle, isPresented: Binding(
            get: { model.askPickedUp != nil }, set: { if !$0 { model.askPickedUp = nil } }), titleVisibility: .visible) {
            if let m = model.askPickedUp {
                Button("Yes, we talked") { Task { await model.reportCall(m.id, answered: true) } }
                Button("No answer") { Task { await model.reportCall(m.id, answered: false) } }
            }
        } message: {
            Text("Kairos only notes the time and whether they picked up. Never what you said.")
        }
    }

    private var pickedUpTitle: String { "Did \(model.askPickedUp?.name ?? "they") pick up?" }

    private var tabs: some View {
        @Bindable var model = model
        return TabView(selection: $model.tab) {
            // .tabItem rather than Tab(...) so this also runs on iOS 17.
            FamilyView().tabItem { Label("Family", systemImage: "sun.horizon.fill") }.tag(AppTab.family)
            InsightsView().tabItem { Label("Insights", systemImage: "waveform.path.ecg") }.tag(AppTab.insights)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(AppTab.settings)
        }
        .tint(GH.apricot)
    }
}

/// A scrolling page on the sunrise background with an optional banner on top.
struct GlassPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let text = model.banner {
                        BannerView(text: text) { withAnimation { model.banner = nil } }
                    }
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .animation(.smooth, value: model.banner)
            }
            .scrollContentBackground(.hidden)
            .background(SunriseBackground())
            .navigationTitle(title)
            .refreshable { await model.reload() }
        }
    }
}
