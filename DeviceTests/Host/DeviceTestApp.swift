import SwiftUI
import SwiftData

@main
struct DeviceTestApp: App {
    @StateObject private var config = ConfigStore()
    let container: ModelContainer
    let session: Session
    @State private var replaySummary = ""

    init() {
        AppTelemetry.start()
        container = try! ModelContainer(for: Session.self, Game.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        session = Session(date: .now)
        let context = container.mainContext
        context.insert(session)
        try! session.record(DisplayResult(left: 1000000,right:2000000), in:context)
        try! session.record(DisplayResult(left: 3000000,right:4000000), in:context)
        let scenario = ProcessInfo.processInfo.environment["FLIPTRACK_TEST_SCENARIO"] ?? "turn"
        let turn = MachineTurn(slot: scenario.hasPrefix("final") ? 2 : 1, ball: scenario.hasPrefix("final") ? 3 : scenario == "recorded" ? 1 : 2)
        try! session.updateProgress(GameProgress(turn:turn,observedStart:true), for:session.currentGameID,in:context)
        config.config = Configuration()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { SessionView(session:session) }
                .modelContainer(container)
                .environmentObject(config)
                .overlay(alignment:.top) {
                    if !replaySummary.isEmpty {
                        Text(replaySummary).font(.caption2).accessibilityIdentifier("fixtureReplayComplete")
                    }
                }
                .task {
                    UIApplication.shared.isIdleTimerDisabled = true
                    guard ProcessInfo.processInfo.environment["FLIPTRACK_TEST_SCENARIO"] == "recorded" else { return }
                    let url = URL.documentsDirectory.appendingPathComponent("reader-performance.json")
                    try? FileManager.default.removeItem(at:url)
                    while !Task.isCancelled {
                        if let data = try? Data(contentsOf:url), let report = try? JSONSerialization.jsonObject(with:data) as? [String:Any] {
                            replaySummary = "Camera \(report["cameraFrames"] ?? 0) · Samples \(report["samples"] ?? 0) · p95 \(report["p95MS"] ?? 0) ms"
                            return
                        }
                        try? await Task.sleep(for:.milliseconds(500))
                    }
                }
        }
    }
}
