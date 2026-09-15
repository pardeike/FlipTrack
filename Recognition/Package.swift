// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FlipTrackRecognition",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "PinballTracking", targets: ["PinballTracking"]),
        .library(name: "PinballVision", targets: ["PinballVision"]),
        .executable(name: "VideoDetect", targets: ["VideoDetect"]),
    ],
    targets: [
        .target(name: "PinballTracking"),
        .target(name: "PinballVision", dependencies: ["PinballTracking"]),
        .executableTarget(name: "VideoDetect", dependencies: ["PinballVision", "PinballTracking"]),
        .testTarget(name: "PinballTrackingTests", dependencies: ["PinballTracking"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PinballVisionTests", dependencies: ["PinballVision"]),
    ]
)
