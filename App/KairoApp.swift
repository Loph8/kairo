import SwiftUI
import WidgetKit

@main
struct KairoApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(GH.apricot)
                .task { await model.reload() }
                .onOpenURL { model.handle($0) }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await model.reload()   // picks up widget-made changes and starts a pending Live Activity
                        // Returning from a call flow: ask for self-reported feedback.
                        if model.leftForFaceTime { model.leftForFaceTime = false; model.callEnded() }
                    }
                }
        }
    }
}
