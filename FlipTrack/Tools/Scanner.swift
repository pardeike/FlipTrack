import AVFoundation
import SwiftUI

@MainActor
final class Scanner: ObservableObject {
    @Published private(set) var state: ScanState = .off
    var isMonitoring: Bool { state.isMonitoring }
    var isPaused: Bool { state.isPaused }
    var error: String? { state.error }
    @Published private(set) var status = "Tap record to scan."
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
    @Published private(set) var isResyncing = false
    @Published private(set) var progress = GameProgress()
    private var tracker = GameTracker()
    private var acceptFramesAfter = -Double.infinity

    func resync() {
        guard isMonitoring, !isPaused, !isResyncing else { return }
        acceptFramesAfter = ProcessInfo.processInfo.systemUptime
        tracker.beginRecovery(at: acceptFramesAfter)
        #if FLIPTRACK_DEVICE_TESTING
        camera.setFixtureRecovery(true)
        #endif
        detector.discardPendingReadings()
        isResyncing = true
        status = "Scanning…"
    }

    func cancelResync() {
        acceptFramesAfter = ProcessInfo.processInfo.systemUptime
        tracker.cancelRecovery(at: acceptFramesAfter)
        #if FLIPTRACK_DEVICE_TESTING
        camera.setFixtureRecovery(false)
        #endif
        detector.discardPendingReadings()
        isResyncing = false
        status = progress.needsResync ? "Tracking uncertain · Resync" : "Watching the display"
    }


    func start(configuration: Configuration, gameID: UUID, progress initialProgress: GameProgress,
               lastScores: [Int], allowRepeatedScores: Bool = false, rejectedSignatures: [String] = [],
               update: @escaping @MainActor (GameProgress, UUID) throws -> Void,
               save: @escaping @MainActor (DisplayResult, UUID) throws -> ScanGameContext) {
        guard !isMonitoring || isPaused else { return }
        resetPreviewTest()
        previewRunning = false
        previewError = nil
        generation = UUID()
        let token = generation
        var activeGameID = gameID
        let rejected = Set(rejectedSignatures)
        progress = initialProgress
        tracker = GameTracker(progress: initialProgress)
        isResyncing = false
        acceptFramesAfter = ProcessInfo.processInfo.systemUptime
        detector = EndGameDetector(lastScores: allowRepeatedScores || initialProgress.observedStart ? [] : lastScores,
                                   requiredReadings: configuration.requiredScanCount,
                                   historyLimit: configuration.historyLimit)
        detector.resumeCurrentGame()
        usesCenteredScanArea = configuration.useCenteredScanArea
        status = "Starting camera…"
        state = .starting
        Task { [self] in
            let permission = AVCaptureDevice.authorizationStatus(for: .video)
            let granted = permission == .notDetermined ? await requestPermission() : permission == .authorized
            guard generation == token, isMonitoring else { return }
            guard granted else { fail("Allow camera access for FlipTrack in Settings."); return }
            camera.start(configuration: configuration) { [weak self] event in
                guard let self, self.generation == token, self.isMonitoring, !self.isPaused else { return }
                switch event {
                case .started:
                    self.state = .scanning
                    self.setStatus("Watching the display")
                case .failed(let message): self.fail(message)
                case .frame(let observation, let time):
                    guard time > self.acceptFramesAfter else { return }
                    let text = observation.text
                    do {
                        let wasRecovering = self.isResyncing
                        if let updated = self.tracker.observe(observation.live, at: time) {
                            try update(updated, activeGameID)
                            if !self.progress.observedStart && updated.observedStart {
                                self.detector = EndGameDetector(requiredReadings: configuration.requiredScanCount, historyLimit: configuration.historyLimit)
                            }
                            self.progress = updated
                        }
                        self.isResyncing = self.tracker.recovering
                        if wasRecovering && !self.isResyncing {
                            self.detector.discardPendingReadings()
                            self.acceptFramesAfter = ProcessInfo.processInfo.systemUptime
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            self.setStatus("Tracking restored")
                            return
                        }
                        // BALL screens can update the turn, never finish the game.
                        let observed = observation.final
                        let ignored = observed.map { rejected.contains($0.signature) } ?? false
                        let result = ignored ? nil : observed
                        let readable = EndGameLayout.hasDisplayText(in: text)
                        // Non-terminal turn context is not sufficient for an automatic
                        // final. Explicit Resync can recover a missed terminal turn.
                        let canFinish = self.isResyncing || self.progress.turn == nil || self.progress.turn?.isLast == true
                        if let confirmed = self.detector.observe(canFinish ? result : nil, at: time, readable: readable,
                            newGame: GameDisplayLayout.isNewGame(in: text)) {
                            if let nextTurn = self.tracker.recoveryNextTurn {
                                var pending = self.progress
                                pending.nextGameTurn = nextTurn
                                try update(pending, activeGameID)
                            }
                            let next = try save(confirmed, activeGameID)
                            activeGameID = next.id
                            self.progress = next.progress
                            self.tracker = GameTracker(progress: next.progress)
                            self.isResyncing = false
                            self.acceptFramesAfter = ProcessInfo.processInfo.systemUptime
                            self.detector = EndGameDetector(lastScores: next.progress.observedStart ? [] : confirmed.scores,
                                requiredReadings: configuration.requiredScanCount, historyLimit: configuration.historyLimit)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            if next.finished { self.stop(); self.setStatus("Session complete"); return }
                            self.setStatus("Game saved")
                        } else if self.isResyncing {
                            self.setStatus("Scanning…")
                        } else if self.progress.nextGameTurn != nil {
                            self.setStatus("Final scores missing · Add scores or Resync")
                        } else if self.progress.needsResync {
                            self.setStatus("Tracking uncertain · Resync")
                        } else if ignored {
                            self.setStatus("Discarded reading ignored")
                        } else if !readable {
                            self.setStatus("Display not ready · Check alignment")
                        } else if let turn = self.progress.turn {
                            self.setStatus("Ball \(turn.ball)")
                        } else {
                            self.setStatus("Watching the display")
                        }
                    } catch { self.fail("Could not save: \(error.localizedDescription)") }
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
        cancelResync()
        generation = UUID()
        state = .paused(reason)
        camera.stop()
        detector.discardPendingReadings()
        status = reason.message
        startPreviewIfNeeded()
    }

    func stop() {
        cancelResync()
        generation = UUID()
        state = .off
        camera.stop()
        status = "Tap record to scan."
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
                    self.appendTestReadings(text.text, at: time)
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

struct ScanGameContext {
    let id: UUID
    let progress: GameProgress
    let finished: Bool
}
