import SwiftUI
import SwiftData

@main
struct FlipTrackApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Item.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [modelConfiguration])
    }()

    var body: some Scene {
        WindowGroup { EventView() /*MainView()*/ }
            .modelContainer(sharedModelContainer)
    }
}
