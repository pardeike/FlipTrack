import SwiftUI

struct CameraButton: View {
    let monitoring: Bool
    var paused = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(.secondary, lineWidth: 2)
                    .frame(width: 34, height: 34)
                if monitoring {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(paused ? .orange : .red)
                        .frame(width: 16, height: 16)
                } else {
                    Circle().fill(.red).frame(width: 24, height: 24)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(monitoring ? "Stop scanning" : "Start scanning")
        .accessibilityValue(monitoring ? (paused ? "Paused" : "Scanning") : "Off")
        .accessibilityIdentifier("toggleScanning")
    }
}
