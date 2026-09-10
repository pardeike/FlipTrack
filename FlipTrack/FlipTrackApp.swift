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
            .onChange(of: scenePhase, initial: true) { _, phase in
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
