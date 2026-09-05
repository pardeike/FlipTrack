// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlipTrackCore",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FlipTrackCore", path: "FlipTrack", exclude: [
            "Assets.xcassets", "FlipTrack.entitlements", "Info.plist", "FlipTrackApp.swift",
            "Views", "Modifiers", "Tools", "Models/ConfigStore.swift"
        ], sources: ["Detection", "Models/Game.swift", "Models/Session.swift", "Models/Configuration.swift"]),
        .testTarget(name: "FlipTrackCoreTests", dependencies: ["FlipTrackCore"], path: "Tests/FlipTrackCoreTests")
    ]
)
