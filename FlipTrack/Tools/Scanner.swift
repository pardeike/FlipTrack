import AVFoundation
import SwiftUI

@MainActor
final class Scanner: ObservableObject {
    @Published private(set) var isMonitoring = false
    @Published private(set) var isPaused = false
    @Published private(set) var status = "Aim at the whole score display."
    @Published private(set) var error: String?
    @Published private(set) var gameState = AutomaticGameState()
    let camera = Camera()
    private var detector = EndGameDetector()
    private var turnDetector = TurnEndDetector()
    private var playerDetector = PlayerPromptDetector()
    private var generation = UUID()
    private var previousIdleTimerDisabled: Bool?

    func start(configuration: Configuration, lastScores: [Int], firstPlayerIndex: Int, save: @escaping @MainActor (DisplayResult) throws -> Void) {
        guard !isMonitoring || isPaused else { return }
        generation = UUID()
        let token = generation
        error = nil
        if !isPaused {
            turnDetector = TurnEndDetector()
            gameState = AutomaticGameState(firstPlayerIndex: firstPlayerIndex, lastScores: lastScores)
            detector = EndGameDetector(lastScores: lastScores, requiredReadings: configuration.requiredScanCount, historyLimit: configuration.historyLimit)
        }
        isPaused = false
        playerDetector = PlayerPromptDetector()
        status = "Starting camera…"
        isMonitoring = true
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
                    if let confirmed = self.detector.observe(result, at: time, readable: readable, newGame: GameDisplayLayout.isNewGame(in: text)) {
                        do {
                            try save(confirmed)
                            self.gameState.gameFinished(confirmed)
                            self.turnDetector = TurnEndDetector()
                            self.playerDetector = PlayerPromptDetector()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            self.status = "Game saved. Waiting for the next game."
                        } catch {
                            self.fail("Scores were not saved: \(error.localizedDescription)")
                        }
                    } else if self.detector.detectedStart {
                        self.gameState.gameStarted()
                        self.turnDetector = TurnEndDetector()
                        self.playerDetector = PlayerPromptDetector()
                        self.status = "New game detected"
                    } else if !self.detector.armed || (result != nil && result == self.detector.lastRegistered) {
                        self.status = "Game saved. Waiting for the next game."
                    } else if result?.isZero == true || GameDisplayLayout.isNewGame(in: text) {
                        self.status = "Watching the start screen"
                    } else if result != nil {
                        self.status = "Checking final scores…"
                    } else {
                        self.status = "Watching for final scores"
                    }
                    let bonus = GameDisplayLayout.isTurnEnd(in: text)
                    if self.turnDetector.observe(bonus, at: time, readable: readable),
                       self.gameState.phase != .switchPlayers {
                        self.gameState.turnFinished()
                        self.playerDetector = PlayerPromptDetector()
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    if bonus, self.gameState.phase == .turnEnded {
                        self.status = "Turn finished. Next player’s turn."
                    }
                    if let slot = self.playerDetector.observe(bonus ? nil : GameDisplayLayout.activePlayer(in: text), at: time),
                       self.gameState.phase != .switchPlayers {
                        if self.gameState.activeSlot != slot || self.gameState.phase != .playing {
                            self.gameState.playerIndicated(slot)
                        }
                    }
                }
            }
        }
    }

    private func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func pause() {
        guard isMonitoring, !isPaused else { return }
        generation = UUID()
        isPaused = true
        camera.stop()
        detector.discardPendingReadings()
        turnDetector.discardPendingReadings()
        playerDetector = PlayerPromptDetector()
        restoreIdleTimer()
        status = "Paused · Tap play to resume"
    }

    func stop() {
        generation = UUID()
        isMonitoring = false
        isPaused = false
        camera.stop()
        restoreIdleTimer()
        status = "Monitoring paused"
    }

    private func restoreIdleTimer() {
        if let previousIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
            self.previousIdleTimerDisabled = nil
        }
    }

    private func fail(_ message: String) {
        stop()
        error = message
    }
}
