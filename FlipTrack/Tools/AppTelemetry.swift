import UIKit

@MainActor
enum AppTelemetry {
    static func start() {
        Telemetry.shared.start(root: URL.documentsDirectory.appendingPathComponent("Telemetry", isDirectory: true))
        UIDevice.current.isBatteryMonitoringEnabled = true
        let bundle = Bundle.main
        Telemetry.shared.log("app.launch", [
            "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "bundle": bundle.bundleIdentifier ?? "unknown",
            "device": UIDevice.current.model,
            "os": UIDevice.current.systemVersion
        ])
        sample()
    }

    static func sample() {
        let info = ProcessInfo.processInfo
        let thermal: String
        switch info.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        let free = try? URL.documentsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
        Telemetry.shared.log("device.sample", Sample(thermal: thermal, lowPower: info.isLowPowerModeEnabled,
            batteryLevel: UIDevice.current.batteryLevel, batteryState: UIDevice.current.batteryState.rawValue,
            freeBytes: free))
    }

    private struct Sample: Encodable {
        let thermal: String
        let lowPower: Bool
        let batteryLevel: Float
        let batteryState: Int
        let freeBytes: Int?
    }
}
