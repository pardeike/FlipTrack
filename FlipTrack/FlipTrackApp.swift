import SwiftUI
import SwiftData

let camera = Camera()

@main
struct FlipTrackApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([Session.self, Game.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    var body: some Scene {
        WindowGroup { SessionsView() }
            .modelContainer(sharedModelContainer)
    }
}
