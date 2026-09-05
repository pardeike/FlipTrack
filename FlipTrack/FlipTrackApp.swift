import SwiftUI
import SwiftData

@main
struct FlipTrackApp: App {
    @StateObject var configStore = ConfigStore()
    
    let sharedModelContainer: Result<ModelContainer, Error> = Result {
        let schema = Schema([Session.self, Game.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    var body: some Scene {
        WindowGroup {
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
    }
}
