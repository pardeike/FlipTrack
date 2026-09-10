import AVFoundation
import SwiftUI

@MainActor
final class Scanner: ObservableObject {
    @Published private(set) var state: ScanState = .off
    var isMonitoring: Bool { state.isMonitoring }
    var isPaused: Bool { state.isPaused }
    var error: String? { state.error }
    @Published private(set) var status = "Aim at the whole score display."
    @Published private(set) var usesCenteredScanArea = false
    @Published private(set) var previewError: String?
    @Published private(set) var previewRunning = false
    @Published private(set) var testingPreview = false
    struct TestReading: Identifiable {
        let id = UUID()
        let text: String
    }
    @Published private(set) var testReadings: [TestReading] = []
    private var recentlySeenTestText: [String: TimeInterval] = [:]
    private var previewConfiguration: Configuration?
    let camera = Camera()
    private var detector = EndGameDetector()
    private var generation = UUID()

    func start(configuration: Configuration, lastScores: [Int], allowRepeatedScores: Bool = false, rejectedSignatures: [String] = [], save: @escaping @MainActor (DisplayResult) throws -> Void) {
        guard !isMonitoring || isPaused else { return }
        resetPreviewTest()
        previewRunning = false
        previewError = nil
        generation = UUID()
        let token = generation
        let rejected = Set(rejectedSignatures)
        detector = EndGameDetector(lastScores: allowRepeatedScores ? [] : lastScores,
                                   requiredReadings: configuration.requiredScanCount,
                                   historyLimit: configuration.historyLimit)
        detector.resumeCurrentGame()
        usesCenteredScanArea = configuration.useCenteredScanArea
        status = "Starting camera…"
        state = .starting
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
                    self.state = .scanning
                    self.setStatus("Watching for final scores")
                case .failed(let message):
                    self.fail(message)
                case .frame(let text, let time):
                    let observed = EndGameLayout.result(in: text)
                    let ignored = observed.map { rejected.contains($0.signature) } ?? false
                    let result = ignored ? nil : observed
                    let readable = EndGameLayout.hasDisplayText(in: text)
                    if let confirmed = self.detector.observe(result, at: time, readable: readable, newGame: GameDisplayLayout.isNewGame(in: text)) {
                        do {
                            try save(confirmed)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            self.setStatus("Game saved. Waiting for the next game.")
                        } catch {
                            self.fail("Scores were not saved: \(error.localizedDescription)")
                        }
                    } else if ignored {
                        self.setStatus("Discarded reading ignored · Waiting for different scores.")
                    } else if self.detector.detectedStart {
                        self.setStatus("New game detected")
                    } else if !readable {
                        self.setStatus("Display not readable · Check alignment.")
                    } else if !self.detector.armed || (result != nil && result == self.detector.lastRegistered) {
                        self.setStatus("Game saved. Waiting for the next game.")
                    } else if result?.isZero == true || GameDisplayLayout.isNewGame(in: text) {
                        self.setStatus("Watching the start screen")
                    } else if result != nil {
                        self.setStatus("Checking final scores…")
                    } else {
                        self.setStatus("Watching for final scores")
                    }

                }
            }
        }
    }

    private func setStatus(_ value: String) {
        if status != value { status = value }
    }

    private func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func pause(_ reason: ScanState.PauseReason = .user) {
        guard isMonitoring, !isPaused else { return }
        generation = UUID()
        state = .paused(reason)
        camera.stop()
        detector.discardPendingReadings()
        status = reason.message
        startPreviewIfNeeded()
    }

    func stop() {
        generation = UUID()
        state = .off
        camera.stop()
        status = "Tap record to scan the current game."
        startPreviewIfNeeded()
    }

    /// Preview owns camera access only while recording is stopped or paused.
    /// Optional test recognition is isolated from recording and persistence.
    func setPreview(_ visible: Bool, configuration: Configuration) {
        previewConfiguration = visible ? configuration : nil
        if visible {
            startPreviewIfNeeded()
        } else {
            resetPreviewTest()
            previewRunning = false
            previewError = nil
            if !isMonitoring || isPaused {
                generation = UUID()
                camera.stop()
            }
        }
    }

    func setPreviewTest(_ enabled: Bool) {
        guard previewConfiguration != nil, !isMonitoring else { return }
        resetPreviewTest()
        testingPreview = enabled
        startPreviewIfNeeded()
    }

    private func resetPreviewTest() {
        testingPreview = false
        testReadings = []
        recentlySeenTestText = [:]
    }

    private func startPreviewIfNeeded() {
        guard let configuration = previewConfiguration, !isMonitoring || isPaused else { return }
        generation = UUID()
        let token = generation
        previewRunning = false
        previewError = nil
        usesCenteredScanArea = configuration.useCenteredScanArea
        Task { [self] in
            let permission = AVCaptureDevice.authorizationStatus(for: .video)
            let granted = permission == .notDetermined ? await requestPermission() : permission == .authorized
            guard generation == token, previewConfiguration != nil else { return }
            guard granted else {
                previewError = "Allow camera access for FlipTrack in Settings."
                return
            }
            camera.start(configuration: configuration, recognizesScores: testingPreview) { [weak self] event in
                guard let self, self.generation == token else { return }
                switch event {
                case .started: self.previewRunning = true
                case .failed(let message):
                    self.previewRunning = false
                    self.previewError = message
                case .frame(let text, let time):
                    guard self.testingPreview, !self.isMonitoring else { return }
                    self.appendTestReadings(text, at: time)
                }
            }
        }
    }

    private func appendTestReadings(_ observations: [DisplayText], at time: TimeInterval) {
        recentlySeenTestText = recentlySeenTestText.filter { time - $0.value < 5 }
        var additions: [TestReading] = []
        for observation in observations {
            let text = observation.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !text.isEmpty else { continue }
            let key = text.uppercased().trimmingCharacters(in: .punctuationCharacters)
            guard !key.isEmpty else { continue }
            if recentlySeenTestText[key] == nil { additions.append(TestReading(text: text)) }
            // Repeated visible text remains quiet until absent for five seconds.
            recentlySeenTestText[key] = time
        }
        guard !additions.isEmpty else { return }
        testReadings = Array((testReadings + additions).suffix(300))
    }

    func restorePausedSession() {
        guard state == .off else { return }
        state = .paused(.restored)
        status = ScanState.PauseReason.restored.message
    }

    private func fail(_ message: String) {
        stop()
        state = .failed(message)
    }
}
