import SwiftUI
import CoreText


@main
struct GoldenHourApp: App {
    /// How often the open app refreshes from the server (and pushes the result to the widgets).
    static let liveRefreshSeconds: Double = 120
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() { Self.registerNightFonts() }

    /// Sulphur Point ships inside the widget extension (where UIAppFonts registers it); the app borrows those files.
    private static func registerNightFonts() {
        let appex = Bundle.main.builtInPlugInsURL?.appendingPathComponent("GoldenHourWidget.appex")
        for name in ["SulphurPoint-Light", "SulphurPoint-Regular", "SulphurPoint-Bold"] {
            if let url = appex?.appendingPathComponent("\(name).ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        // Page titles ("Kim family", "Insights") use the widget's font too.
        let ink = UIColor(hex: 0xF8F9F4)
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        if let big = UIFont(name: "SulphurPoint-Bold", size: 34) { nav.largeTitleTextAttributes = [.font: big, .foregroundColor: ink] }
        if let small = UIFont(name: "SulphurPoint-Bold", size: 17) { nav.titleTextAttributes = [.font: small, .foregroundColor: ink] }
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--widget-gallery") { WidgetGallery() } else { RootView() }
                #else
                RootView()
                #endif
            }
                .environment(model)
                .preferredColorScheme(.dark)
                .font(Night.font(16))
                .tint(GH.apricot)
                .task {
                    #if targetEnvironment(simulator)
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("--demo") { AppBackend.setLocalDemo(true) }
                    if args.contains("--tab=insights") { model.tab = .insights }
                    if args.contains("--tab=settings") { model.tab = .settings }
                    if args.contains("--render-icon") {   // writes Documents/AppIcon.png for Assets.xcassets
                        let r = ImageRenderer(content: KairosLogo(size: 1024, rounded: false))
                        r.scale = 1
                        let url = URL.documentsDirectory.appending(path: "AppIcon.png")
                        if let png = r.uiImage?.pngData() { try? png.write(to: url) }
                    }
                    #endif
                    await model.reload()
                }
                .onOpenURL { model.handle($0) }
                .task(id: scenePhase) {
                    // While the app is open, refresh every few minutes. Each refresh also reloads the widgets,
                    // so the widget shows the same suggestion and times as the app.
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(Self.liveRefreshSeconds))
                        guard !Task.isCancelled else { return }
                        await model.reload()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { model.enteredBackground() }
                    guard phase == .active else { return }
                    model.returnedToApp()   // back from FaceTime: ask whether they picked up
                    Task { await model.reload() }   // picks up widget taps and family changes
                }
        }
    }
}
