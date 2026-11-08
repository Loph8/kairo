// swift-tools-version:5.9
import PackageDescription

// GoldenHourCore holds every piece of logic that can be verified without Xcode:
// time zones, availability scoring, scheduling, booking state machine,
// shared snapshot cache, demo seed and the local repository.
// The iOS app, widget and Live Activity targets link this package.
let package = Package(
    name: "GoldenHourCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "GoldenHourCore", targets: ["GoldenHourCore"])],
    targets: [
        .target(name: "GoldenHourCore"),
        .testTarget(name: "GoldenHourCoreTests", dependencies: ["GoldenHourCore"]),
    ]
)
