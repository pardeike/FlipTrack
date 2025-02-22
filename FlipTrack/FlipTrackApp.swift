import SwiftUI
import SwiftData

@main
struct FlipTrackApp: App {
    @StateObject var configStore = ConfigStore()
    
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([Session.self, Game.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    var body: some Scene {
        WindowGroup {
            SessionsView()
                .environmentObject(configStore)
                .modelContainer(sharedModelContainer)
        }
    }
}
