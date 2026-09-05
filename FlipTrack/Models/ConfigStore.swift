import Foundation

@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: Configuration {
        didSet {
            if let data = try? JSONEncoder().encode(config) {
                UserDefaults.standard.set(data, forKey: "Configuration")
            }
        }
    }
    
    init() {
        let data = UserDefaults.standard.data(forKey: "Configuration") ?? Data()
        var loaded = (try? JSONDecoder().decode(Configuration.self, from: data)) ?? Configuration()
        loaded.requiredScanCount = max(4, min(10, loaded.requiredScanCount))
        loaded.historyLimit = max(loaded.requiredScanCount, min(20, loaded.historyLimit))
        config = loaded
    }
}
