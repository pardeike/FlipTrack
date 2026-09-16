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
    private var currentContext: (@MainActor () -> SessionSnapshot)?
    private var boundContext: SessionSnapshot?
    private var scanConfiguration = Configuration()
    private var evidence = ScoreEvidence()

    /// Called before every frame and after editing. No persisted session value
    /// is owned by the recognizer; only unconfirmed temporal votes are cached.
    @discardableResult func refreshContext() -> Bool {
        guard let currentContext else { return false }
        let latest = currentContext()
        guard latest != boundContext else { return false }
        Telemetry.shared.log("scanner.contextChanged", latest)
        boundContext = latest
        progress = latest.progress
        tracker = GameTracker(progress: latest.progress)
        detector = EndGameDetector(lastScores: latest.allowRepeated || latest.progress.observedStart ? [] : latest.lastScores,
                                   requiredReadings: scanConfiguration.requiredScanCount, historyLimit: scanConfiguration.historyLimit)
        detector.resumeCurrentGame()
        isResyncing = false
        evidence = ScoreEvidence(finalHistoryLimit: detector.historyLimit)
        acceptFramesAfter = ProcessInfo.processInfo.systemUptime
        if latest.finished { stop(); setStatus("Session complete") }
        else if latest.id == nil || !latest.pending.isEmpty { pause(.editing) }
        return true
    }

    func resync() {
        guard isMonitoring, !isPaused, !isResyncing else { return }
        refreshContext()
        guard isMonitoring, !isPaused else { return }
        Telemetry.shared.action("resync")
        evidence.clear()
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
        if isResyncing { Telemetry.shared.action("cancelResync") }
        evidence.clear()
        acceptFramesAfter = ProcessInfo.processInfo.systemUptime
        tracker.cancelRecovery(at: acceptFramesAfter)
        #if FLIPTRACK_DEVICE_TESTING
        camera.setFixtureRecovery(false)
        #endif
        detector.discardPendingReadings()
        isResyncing = false
        status = progress.needsResync ? "Use Resync" : "Watching the display"
    }


    func start(configuration: Configuration, current: @escaping @MainActor () -> SessionSnapshot,
               update: @escaping @MainActor (GameProgress, UUID) throws -> Void,
               save: @escaping @MainActor (DisplayResult, UUID) throws -> Void) {
        guard !isMonitoring || isPaused else { return }
        resetPreviewTest()
        previewRunning = false
        previewError = nil
        generation = UUID()
        let token = generation
        currentContext = current
        scanConfiguration = configuration
        boundContext = nil
        refreshContext()
        guard let initial = boundContext, initial.id != nil, !initial.finished, initial.pending.isEmpty else { return }
        Telemetry.shared.log("scanner.start", initial)
        Telemetry.shared.log("scanner.configuration", configuration)
        usesCenteredScanArea = configuration.useCenteredScanArea
        status = "Starting camera…"
        state = .starting
        Task { [self] in
            #if FLIPTRACK_DEVICE_TESTING && targetEnvironment(simulator)
            let granted = true
            #else
            let permission = AVCaptureDevice.authorizationStatus(for: .video)
            let granted = permission == .notDetermined ? await requestPermission() : permission == .authorized
            #endif
            guard generation == token, isMonitoring else { return }
            guard granted else { fail("Allow camera access for FlipTrack in Settings."); return }
            camera.start(configuration: configuration) { [weak self] event in
                guard let self, self.generation == token, self.isMonitoring, !self.isPaused else { return }
                switch event {
                case .started:
                    Telemetry.shared.log("camera.started", ["mode": "scanning"])
                    self.state = .scanning
                    self.setStatus("Watching the display")
                case .failed(let message): self.fail(message)
                case .frame(let observation, let time):
                    let reading = FrameReading(observation, at: time)
                    Telemetry.shared.log("frame", reading)
                    if self.refreshContext() {
                        Telemetry.shared.log("frame.ignored", ["id": observation.frameID.uuidString, "reason": "session corrected"])
                        return
                    }
                    guard time > self.acceptFramesAfter, self.isMonitoring, !self.isPaused,
                          let before = self.boundContext, let activeGameID = before.id else {
                        Telemetry.shared.log("frame.ignored", ["id": observation.frameID.uuidString, "reason": "stale or paused"])
                        return
                    }
                    self.evidence.append(observation, at: time)
                    let text = observation.text
                    do {
                        let wasRecovering = self.isResyncing
                        if let updated = self.tracker.observe(observation.live, at: time) {
                            let confirmed = self.evidence.accepted(before: before, after: before, proposedProgress: updated)
                            Telemetry.shared.log("score.progressConfirmed", confirmed.0, images: confirmed.1)
                            try update(updated, activeGameID)
                            let after = current()
                            let accepted = self.evidence.accepted(before: before, after: after)
                            Telemetry.shared.log("score.progressAccepted", accepted.0)
                            self.boundContext = after
                            if !self.progress.observedStart && updated.observedStart {
                                self.detector = EndGameDetector(requiredReadings: configuration.requiredScanCount, historyLimit: configuration.historyLimit)
                            }
                            self.progress = updated
                        }
                        self.isResyncing = self.tracker.recovering
                        if wasRecovering && !self.isResyncing {
                            self.evidence.clear()
                            self.detector.discardPendingReadings()
                            self.acceptFramesAfter = ProcessInfo.processInfo.systemUptime
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            self.setStatus("Tracking restored")
                            return
                        }
                        // BALL screens can update the turn, never finish the game.
                        let observed = observation.final
                        let ignored = observed.map { current().rejected.contains($0.signature) } ?? false
                        let result = ignored ? nil : observed
                        let readable = EndGameLayout.hasDisplayText(in: text)
                        // Non-terminal turn context is not sufficient for an automatic
                        // final. Explicit Resync can recover a missed terminal turn.
                        let canFinish = (!current().awaitingNextStart || self.isResyncing || current().allowRepeated) && self.progress.canAcceptFinal(recovering: self.isResyncing) && self.tracker.recoveryNextTurn == nil
                        if let confirmed = self.detector.observe(canFinish ? result : nil, at: time, readable: readable,
                            newGame: GameDisplayLayout.isNewGame(in: text)) {
                            let beforeSave = current()
                            let confirmation = self.evidence.accepted(before: beforeSave, after: beforeSave, final: confirmed)
                            Telemetry.shared.log("score.finalConfirmed", confirmation.0, images: confirmation.1)
                            try save(confirmed, activeGameID)
                            let next = current()
                            let accepted = self.evidence.accepted(before: beforeSave, after: next, final: confirmed)
                            Telemetry.shared.log("score.finalAccepted", accepted.0)
                            self.boundContext = next
                            self.evidence.clear()
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
                            self.setStatus("Add final scores")
                        } else if self.progress.needsResync {
                            self.setStatus("Use Resync")
                        } else if ignored {
                            self.setStatus("Discarded reading ignored")
                        } else if current().awaitingNextStart {
                            self.setStatus("Waiting for next game")
                        } else if !readable {
                            self.setStatus("Check alignment")
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
        if status != value {
            Telemetry.shared.log("scanner.status", ["before": status, "after": value])
            status = value
        }
    }

    private func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func pause(_ reason: ScanState.PauseReason = .user) {
        guard isMonitoring, !isPaused else { return }
        Telemetry.shared.log("scanner.pause", ["reason": reason.message])
        cancelResync()
        generation = UUID()
        state = .paused(reason)
        camera.stop()
        detector.discardPendingReadings()
        status = reason.message
        startPreviewIfNeeded()
    }

    func stop() {
        Telemetry.shared.action("scanner.stop")
        currentContext = nil
        boundContext = nil
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
        Telemetry.shared.log("camera.preview", ["visible": visible])
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
        Telemetry.shared.log("camera.recognitionTest", ["enabled": enabled])
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
            #if FLIPTRACK_DEVICE_TESTING && targetEnvironment(simulator)
            let granted = true
            #else
            let permission = AVCaptureDevice.authorizationStatus(for: .video)
            let granted = permission == .notDetermined ? await requestPermission() : permission == .authorized
            #endif
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
                    Telemetry.shared.log("preview.frame", FrameReading(text, at: time))
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
        Telemetry.shared.log("scanner.error", ["message": message])
        stop()
        state = .failed(message)
    }
}
