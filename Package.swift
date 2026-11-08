// swift-tools-version:5.9
import PackageDescription

// KairoCore holds every piece of logic that can be verified without Xcode:
// time zones, availability scoring, scheduling, booking state machine,
// shared snapshot cache, demo seed and the local repository.
// The iOS app, widget and Live Activity targets link this package.
let package = Package(
    name: "KairoCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "KairoCore", targets: ["KairoCore"])],
    targets: [
        .target(name: "KairoCore"),
        .testTarget(name: "KairoCoreTests", dependencies: ["KairoCore"]),
    ]
)
