import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var configStore: ConfigStore
    
    var body: some View {
        Form {
            Section(header: Text("Scan Settings")) {
                Stepper("Required Scan Count: \(configStore.config.requiredScanCount)",
                        value: $configStore.config.requiredScanCount,
                        in: 1...10)
                
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
            }
        }
        .padding()
    }
}
