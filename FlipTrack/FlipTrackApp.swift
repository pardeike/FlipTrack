import SwiftUI
import SwiftData

@main
struct FlipTrackApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var previousIdleTimerDisabled: Bool?
    @StateObject var configStore = ConfigStore()
    
    let sharedModelContainer: Result<ModelContainer, Error> = Result {
        let schema = Schema([Session.self, Game.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    init() { AppTelemetry.start() }

    var body: some Scene {
        WindowGroup {
            Group {
                switch sharedModelContainer {
                case .success(let container):
                    SessionsView()
                        .environmentObject(configStore)
                        .modelContainer(container)
                case .failure(let error):
                    ContentUnavailableView {
                        Label("Sessions could not be opened", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(error.localizedDescription)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                Telemetry.shared.action("device.memoryWarning")
            }
            .task {
                if case .failure(let error) = sharedModelContainer {
                    Telemetry.shared.log("store.error", ["message": error.localizedDescription])
                }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    if scenePhase == .active { AppTelemetry.sample() }
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                Telemetry.shared.log("app.phase", ["phase": String(describing: phase)])
                if phase != .active { Telemetry.shared.flush() }
                if phase == .active {
                    if previousIdleTimerDisabled == nil {
                        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
                    }
                    UIApplication.shared.isIdleTimerDisabled = true
                } else if let previous = previousIdleTimerDisabled {
                    UIApplication.shared.isIdleTimerDisabled = previous
                    previousIdleTimerDisabled = nil
                }
            }
        }
    }
}
