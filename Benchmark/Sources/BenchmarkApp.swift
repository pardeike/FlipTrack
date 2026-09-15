import SwiftUI

@main
struct BenchmarkApp: App {
    @StateObject private var model = BenchmarkModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    Text(model.status).font(.headline)
                    if model.running {
                        ProgressView(value: model.progress)
                        Button("Stop", role: .destructive) { model.stop() }
                    } else {
                        Toggle("Camera load", isOn: $model.cameraLoad)
                        Button("Run 60-second check") { model.start(seconds: 60) }
                            .buttonStyle(.bordered)
                        Button("Run full recording") { model.start(seconds: nil) }
                            .buttonStyle(.borderedProminent)
                    }
                    if let result = model.result {
                        Text(result).font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Text("Results are saved in the app’s Documents folder. Keep this app open and the phone connected to power.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
                .navigationTitle("Recognition benchmark")
            }
            .preferredColorScheme(.dark)
            .task {
                if CommandLine.arguments.contains("--smoke"), !model.started {
                    model.start(seconds: 60)
                } else if CommandLine.arguments.contains("--full"), !model.started {
                    model.start(seconds: nil)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.stop() }
            }
        }
    }
}

@MainActor
final class BenchmarkModel: ObservableObject {
    @Published var status = "Ready"
    @Published var running = false
    @Published var progress = 0.0
    @Published var result: String?
    @Published var cameraLoad = true
    private var runner: BenchmarkRunner?
    private(set) var started = false

    func start(seconds: Double?) {
        guard !running else { return }
        started = true
        running = true
        progress = 0
        result = nil
        status = "Preparing recording…"
        let runner = BenchmarkRunner()
        self.runner = runner
        let useCamera = cameraLoad
        UIApplication.shared.isIdleTimerDisabled = true
        Task.detached(priority: .userInitiated) { [self] in
            let summary = await runner.run(seconds: seconds, cameraLoad: useCamera) { fraction in
                Task { @MainActor [self] in
                    self.progress = fraction
                    self.status = "Replaying with \(useCamera ? "camera active" : "camera off")"
                }
            }
            await MainActor.run { [self] in
                UIApplication.shared.isIdleTimerDisabled = false
                self.running = false
                self.status = summary.completed ? "Complete" : "Stopped or failed"
                self.result = summary.display
                self.runner = nil
            }
        }
    }

    func stop() { runner?.cancel() }
}
