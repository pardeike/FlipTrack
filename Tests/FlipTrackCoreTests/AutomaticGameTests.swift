import Testing
import Foundation
@testable import FlipTrackCore

private let finalScore = DisplayResult(left: 24_274_100, right: 37_531_870)
private let zero = DisplayResult(left: 0, right: 0)

@Test func zeroScoresStartButNeverFinishAGame() {
    var detector = EndGameDetector()
    for tick in 0...15 {
        #expect(detector.observe(zero, at: Double(tick) * 0.5, readable: true) == nil)
        #expect(detector.detectedStart == (tick == 2))
    }
    #expect(detector.lastRegistered == nil)
    #expect(detector.armed)
    var finishes = 0
    for tick in 16...35 {
        if detector.observe(finalScore, at: Double(tick) * 0.5, readable: true) != nil { finishes += 1 }
    }
    #expect(finishes == 1)
}

@Test func startScreenUnlocksNextGameWithoutWaitingEightSeconds() {
    var detector = EndGameDetector(lastScores: finalScore.scores)
    #expect(!detector.armed)
    for tick in 0...2 { _ = detector.observe(nil, at: Double(tick) * 0.5, readable: true, newGame: true) }
    #expect(detector.detectedStart)
    #expect(detector.armed)
    // The old result cycling back must still not be recorded twice.
    for tick in 3...15 { #expect(detector.observe(finalScore, at: Double(tick) * 0.5, readable: true) == nil) }
    let next = DisplayResult(left: 10_000, right: 20_000)
    var count = 0
    for tick in 16...40 { if detector.observe(next, at: Double(tick) * 0.5, readable: true) != nil { count += 1 } }
    #expect(count == 1)
}

@Test func fleetingOrInterruptedZeroReadingsDoNotStart() {
    var detector = EndGameDetector(lastScores: finalScore.scores)
    for tick in 0...20 {
        _ = detector.observe(tick % 2 == 0 ? zero : nil, at: Double(tick) * 0.5, readable: true)
        #expect(!detector.detectedStart)
    }
    _ = detector.observe(zero, at: 30, readable: true)
    _ = detector.observe(zero, at: 40, readable: true)
    #expect(!detector.detectedStart)
    #expect(!detector.armed)
}

@Test func actionPersonTracksTurnsThenBecomesNextStarter() {
    var state = AutomaticGameState(firstPlayerIndex: 1)
    #expect(state.phase == .ready)
    #expect(state.actionPlayerIndex == 1)
    state.gameStarted()
    #expect(state.phase == .playing)
    state.playerIndicated(1)
    #expect(state.actionPlayerIndex == 0)
    #expect(state.otherPlayerIndex == 1)
    state.gameFinished(finalScore)
    #expect(state.phase == .switchPlayers)
    #expect(state.actionPlayerIndex == 0)
    #expect(state.finishedScores == [37_531_870, 24_274_100])
    // Attract-mode player prompts cannot dismiss the switch screen.
    state.playerIndicated(1)
    #expect(state.phase == .switchPlayers)
    #expect(state.actionPlayerIndex == 0)
    state.gameStarted()
    #expect(state.phase == .playing)
    #expect(state.actionPlayerIndex == 0)
    state.playerIndicated(1)
    #expect(state.actionPlayerIndex == 1)
    state.gameFinished(DisplayResult(left: 1000, right: 2000))
    #expect(state.actionPlayerIndex == 1)
    #expect(state.finishedScores == [1000, 2000])
}

@Test func resumesWithThePersonWhoStartsNext() {
    let state = AutomaticGameState(firstPlayerIndex: 0, lastScores: finalScore.scores)
    #expect(state.phase == .switchPlayers)
    #expect(state.actionPlayerIndex == 0)
    #expect(state.finishedScores == [37_531_870, 24_274_100])
}

private func text(_ value: String, x: CGFloat = 0.1, y: CGFloat = 0.7, confidence: Float = 1, inside: Bool = true) -> DisplayText {
    DisplayText(text: value, confidence: confidence, bounds: CGRect(x: x, y: y, width: 0.1, height: 0.1), isInsideDisplay: inside)
}

@Test func zeroLayoutNeedsAScoreboard() {
    func label(_ value: String, _ bounds: CGRect) -> DisplayText {
        DisplayText(text: value, confidence: 1, bounds: bounds)
    }
    let large = CGRect(x: 0.42, y: 0.65, width: 0.09, height: 0.05)
    let small = CGRect(x: 0.65, y: 0.67, width: 0.05, height: 0.025)
    let ball = CGRect(x: 0.27, y: 0.58, width: 0.12, height: 0.025)
    let free = CGRect(x: 0.46, y: 0.58, width: 0.17, height: 0.025)
    let layout = [label("00", large), label("00", small), label("BALL 1", ball), label("FREE PLAY", free)]
    #expect(GameDisplayLayout.isNewGame(in: layout))
    #expect(EndGameLayout.result(in: layout) == nil)
    for index in layout.indices {
        var missing = layout
        missing.remove(at: index)
        #expect(!GameDisplayLayout.isNewGame(in: missing))
    }
    for value in ["1000", "10", "OOPS", "00000"] {
        var wrongScore = layout
        wrongScore[0] = label(value, large)
        #expect(!GameDisplayLayout.isNewGame(in: wrongScore))
    }
    var laterBall = layout
    laterBall[2] = label("BALL 2", ball)
    #expect(!GameDisplayLayout.isNewGame(in: laterBall))
    #expect(EndGameLayout.result(in: laterBall) == nil)
    var equalSize = layout
    equalSize[0] = label("00", CGRect(x: large.minX, y: small.minY, width: small.width, height: small.height))
    #expect(!GameDisplayLayout.isNewGame(in: equalSize))
    for scale in [0.4, 0.8] {
        let shifted = layout.map { observation in
            label(observation.text, observation.bounds.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: 0.1, ty: 0.05)))
        }
        #expect(GameDisplayLayout.isNewGame(in: shifted))
    }
}

@Test func explicitPlayerPromptsNeedAgreement() {
    #expect(GameDisplayLayout.activePlayer(in: [text("PLAYER 1")]) == 0)
    #expect(GameDisplayLayout.activePlayer(in: [text("PLAYER 2 UP")]) == 1)
    #expect(GameDisplayLayout.activePlayer(in: [text("PLAYER 1"), text("PLAYER 2")]) == nil)
    #expect(GameDisplayLayout.activePlayer(in: [text("HIGH SCORE PLAYER 1")]) == nil)
    #expect(GameDisplayLayout.activePlayer(in: [text("PLAYER 3")]) == nil)
    #expect(GameDisplayLayout.activePlayer(in: [text("PLAYER 1", confidence: 0.2)]) == nil)
    #expect(GameDisplayLayout.activePlayer(in: [text("PLAYER 1", inside: false)]) == nil)
    var detector = PlayerPromptDetector()
    #expect(detector.observe(0, at: 0) == nil)
    #expect(detector.observe(1, at: 0.5) == nil)
    #expect(detector.observe(1, at: 1) == 1)
    #expect(detector.observe(nil, at: 1.5) == nil)
    #expect(detector.observe(0, at: 2) == nil)
    #expect(detector.observe(0, at: 5) == nil)
}

@Test func pauseDropsPartialEvidenceButKeepsSavedGameProtection() {
    var detector = EndGameDetector()
    for tick in 0...2 {
        #expect(detector.observe(finalScore, at: Double(tick) * 0.5, readable: true) == nil)
    }
    detector.discardPendingReadings()
    // Even a very quick pause must require a fresh complete confirmation.
    for tick in 3...5 {
        #expect(detector.observe(finalScore, at: Double(tick) * 0.5, readable: true) == nil)
    }
    #expect(detector.observe(finalScore, at: 3, readable: true) == finalScore)
    for tick in 7...21 { _ = detector.observe(nil, at: Double(tick) * 0.5, readable: true) }
    detector.discardPendingReadings()
    #expect(!detector.armed)
    #expect(detector.lastRegistered == finalScore)
    _ = detector.observe(nil, at: 100, readable: true)
    #expect(!detector.armed)
    for tick in 201...220 {
        #expect(detector.observe(finalScore, at: Double(tick) * 0.5, readable: true) == nil)
    }
}

@Test func pauseDropsPartialStartAndKeepsConfirmedStartLatch() {
    var detector = EndGameDetector(lastScores: finalScore.scores)
    for tick in 0...1 { _ = detector.observe(zero, at: Double(tick) * 0.5, readable: true) }
    detector.discardPendingReadings()
    for tick in 2...3 {
        _ = detector.observe(zero, at: Double(tick) * 0.5, readable: true)
        #expect(!detector.detectedStart)
    }
    _ = detector.observe(zero, at: 2, readable: true)
    #expect(detector.detectedStart)
    detector.discardPendingReadings()
    #expect(detector.armed)
    for tick in 5...10 {
        _ = detector.observe(zero, at: Double(tick) * 0.5, readable: true)
        #expect(!detector.detectedStart)
    }
}

@Test func bonusAdvancesOnceUntilReadablePlayResumes() {
    var detector = TurnEndDetector()
    var state = AutomaticGameState(firstPlayerIndex: 1)
    for tick in 0...12 {
        if detector.observe(true, at: Double(tick) * 0.5, readable: true) { state.turnFinished() }
    }
    #expect(state.actionPlayerIndex == 0)
    #expect(state.phase == .turnEnded)
    detector.discardPendingReadings()
    for tick in 20...25 {
        #expect(detector.observe(true, at: Double(tick) * 0.5, readable: true) == false)
    }
    for tick in 26...35 {
        #expect(detector.observe(false, at: Double(tick) * 0.5, readable: false) == false)
    }
    #expect(detector.observe(true, at: 18, readable: true) == false)
    #expect(detector.observe(true, at: 18.5, readable: true) == false)
    for tick in 38...42 { _ = detector.observe(false, at: Double(tick) * 0.5, readable: true) }
    #expect(detector.observe(true, at: 21.5, readable: true) == false)
    #expect(detector.observe(true, at: 22, readable: true) == true)
    state.turnFinished()
    #expect(state.actionPlayerIndex == 1)
    state.gameFinished(finalScore)
    let saved = state
    state.turnFinished()
    #expect(state == saved)
}

@Test func bonusHeadingMustMatchAndBeAtTopCenter() {
    func header(_ value: String, x: CGFloat = 0.25, y: CGFloat = 0.7) -> DisplayText {
        DisplayText(text: value, confidence: 1, bounds: CGRect(x: x, y: y, width: 0.5, height: 0.12), isInsideDisplay: true)
    }
    #expect(GameDisplayLayout.isTurnEnd(in: [header("TOTAL BONUS")]))
    #expect(GameDisplayLayout.isTurnEnd(in: [header("total  bonus")]))
    #expect(!GameDisplayLayout.isTurnEnd(in: [header("BONUS")]))
    #expect(!GameDisplayLayout.isTurnEnd(in: [header("TOTAL BONUS X2")]))
    #expect(!GameDisplayLayout.isTurnEnd(in: [header("TOTAL BONUS", y: 0.1)]))
    #expect(!GameDisplayLayout.isTurnEnd(in: [header("TOTAL BONUS", x: 0)]))
    var detector = TurnEndDetector()
    #expect(detector.observe(true, at: 0, readable: true) == false)
    #expect(detector.observe(false, at: 0.5, readable: false) == false)
    #expect(detector.observe(true, at: 1, readable: true) == false)
    #expect(detector.observe(true, at: 4, readable: true) == false)
}

@Test func completeTwoPlayerGamesKeepNamesAndStarterOrder() {
    var state = AutomaticGameState(firstPlayerIndex: 1)
    for starter in [1, 0] {
        state.gameStarted()
        #expect(state.actionPlayerIndex == starter)
        for _ in 0..<3 {
            state.turnFinished()
            #expect(state.phase == .turnEnded)
            #expect(state.actionPlayerIndex == 1 - starter)
            state.playerIndicated(1)
            #expect(state.phase == .playing)
            #expect(state.actionPlayerIndex == 1 - starter)
            state.turnFinished()
            #expect(state.actionPlayerIndex == starter)
            state.playerIndicated(0)
        }
        state.gameFinished(finalScore)
        #expect(state.phase == .switchPlayers)
        #expect(state.actionPlayerIndex == 1 - starter)
        #expect(state.finishedScores == (starter == 0 ? finalScore.scores : Array(finalScore.scores.reversed())))
        state.turnFinished()
        state.playerIndicated(1)
        #expect(state.phase == .switchPlayers)
        #expect(state.actionPlayerIndex == 1 - starter)
    }
}
