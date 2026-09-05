import SwiftUI

struct CameraButton: View {
    let monitoring: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(monitoring ? "Stop monitoring" : "Start monitoring", systemImage: monitoring ? "stop.fill" : "camera.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(monitoring ? .gray : .accentColor)
    }
}
