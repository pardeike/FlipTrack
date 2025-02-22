import Foundation

class ConfigStore: ObservableObject {
    @Published var config: Configuration {
        didSet {
            if let data = try? JSONEncoder().encode(config) {
                UserDefaults.standard.set(data, forKey: "Configuration")
            }
        }
    }
    
    init() {
        let data = UserDefaults.standard.data(forKey: "Configuration") ?? Data()
        config = (try? JSONDecoder().decode(Configuration.self, from: data)) ?? Configuration()
    }
}
