import AVFoundation
import SwiftUI

@MainActor
final class Scanner: ObservableObject {
    @Published private(set) var isMonitoring = false
    @Published private(set) var status = "Point the rear camera at the whole score display."
    @Published private(set) var error: String?
    let camera = Camera()
    private var detector = EndGameDetector()
    private var generation = UUID()
    private var previousIdleTimerDisabled: Bool?

    func start(configuration: Configuration, lastScores: [Int], save: @escaping @MainActor (DisplayResult) throws -> Void) {
        guard !isMonitoring else { return }
        generation = UUID()
        let token = generation
        error = nil
        status = "Starting camera…"
        isMonitoring = true
        detector = EndGameDetector(lastScores: lastScores, requiredReadings: configuration.requiredScanCount, historyLimit: configuration.historyLimit)
        previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        Task { [self] in
            let permission = AVCaptureDevice.authorizationStatus(for: .video)
            let granted: Bool
            if permission == .notDetermined {
                granted = await requestPermission()
            } else {
                granted = permission == .authorized
            }
            guard generation == token, isMonitoring else { return }
            guard granted else {
                fail("Allow camera access for FlipTrack in Settings.")
                return
            }
            camera.start(configuration: configuration) { [weak self] event in
                guard let self, self.generation == token, self.isMonitoring else { return }
                switch event {
                case .started:
                    self.status = "Watching for final scores"
                case .failed(let message):
                    self.fail(message)
                case .frame(let text, let time):
                    let result = EndGameLayout.result(in: text)
                    let readable = EndGameLayout.hasDisplayText(in: text)
                    if let confirmed = self.detector.observe(result, at: time, readable: readable) {
                        do {
                            try save(confirmed)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            self.status = "Game saved. Waiting for the next game."
                        } catch {
                            self.fail("Scores were not saved: \(error.localizedDescription)")
                        }
                    } else if !self.detector.armed || (result != nil && result == self.detector.lastRegistered) {
                        self.status = "Game saved. Waiting for the next game."
                    } else if result != nil {
                        self.status = "Checking final scores…"
                    } else {
                        self.status = "Watching for final scores"
                    }
                }
            }
        }
    }

    private func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func stop() {
        generation = UUID()
        isMonitoring = false
        camera.stop()
        if let previousIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            self.previousIdleTimerDisabled = nil
        }
        status = "Monitoring paused"
    }

    private func fail(_ message: String) {
        stop()
        error = message
    }
}
