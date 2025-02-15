import SwiftUI
import AVFoundation
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("openai-api-key") private var apiKey: String = ""
    
    @State var cameraReady = false
    @State var key = ""
    @State var scores = []

    var body: some View {
        VStack {
            Spacer()
            if cameraReady {
                if apiKey.starts(with: "sk-") {
                    CameraPreview()
                        .aspectRatio(2.0, contentMode: .fit)
                    Button("Take Photo") {
                        Task {
                            camera.takePhoto { image in
                                Task {
                                    let scores = await Analyzer.extractScore(image, 320, 0.2)
                                    if scores.count == 2 { self.scores = scores }
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    HStack {
                        Spacer()
                        if scores.count == 2 {
                            Text("\(scores[0])").padding(.trailing)
                            Text("\(scores[1])").padding(.leading)
                        } else if scores.count == 1 {
                            Text("analyzing")
                        } else {
                            Text("ready")
                        }
                        Spacer()
                    }
                    .padding(.top)
                } else {
                    Button("Paste API Key") {
                        apiKey = UIPasteboard.general.string ?? ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Spacer()
        }
        .onAppear {
            if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    cameraReady = granted
                }
            } else {
                cameraReady = true
            }
        }
    }
}

#Preview {
    MainView()
        .modelContainer(for: Item.self, inMemory: true)
}
