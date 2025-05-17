import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var configStore: ConfigStore
    
    var body: some View {
        Form {
            Section(header: Text("Scan Settings")) {
                Stepper("Required Scan Count: \(configStore.config.requiredScanCount)",
                        value: $configStore.config.requiredScanCount,
                        in: 1...10)

                Stepper("History Limit: \(configStore.config.historyLimit)",
                        value: $configStore.config.historyLimit,
                        in: 1...20)
                
                HStack {
                    Text("Exposure: \(String(format: "%+.1f", configStore.config.fstopsDown))")
                    Slider(value: $configStore.config.fstopsDown,
                           in: -3...3,
                           step: 0.5)
                }
            }
            
            Section(header: Text("Quality Settings")) {
                Toggle("High Quality", isOn: $configStore.config.qualityMode)
                Toggle("Apply Filter", isOn: $configStore.config.filterImage)
                if configStore.config.filterImage {
                    HStack {
                        Text("Filter Strength: \(String(format: "%.1f", configStore.config.filterStrength))")
                        Slider(value: $configStore.config.filterStrength, in: 0...1)
                    }
                    HStack {
                        Text("Contrast: \(String(format: "%.1f", configStore.config.contrast))")
                        Slider(value: $configStore.config.contrast, in: 0.5...3)
                    }
                    HStack {
                        Text("Sharpness: \(String(format: "%.1f", configStore.config.sharpness))")
                        Slider(value: $configStore.config.sharpness, in: 0...2)
                    }
                }
            }
        }
        .padding()
    }
}
