import Foundation

/// Durable evidence for the selected game. Unknown scores remain nil.
struct GameProgress: Codable, Equatable, Sendable {
    var turn: MachineTurn?
    var left: Int?
    var right: Int?
    var observedStart = false
    var needsResync = false
    var nextGameTurn: MachineTurn?

    mutating func accept(_ reading: LiveScoreboard) {
        turn = reading.turn
        if let value = reading.left { left = value }
        if let value = reading.right { right = value }
        observedStart = true
        needsResync = false
    }
}

/// Temporal confirmation shared by ordinary tracking and explicit recovery.
/// A missing/ambiguous frame is evidence against confirmation, not another vote.
struct TurnDetector {
    private var readings: [(TimeInterval, LiveScoreboard?)] = []
    private var lastTime: TimeInterval?

    mutating func reset() { readings = []; lastTime = nil }

    mutating func observe(_ reading: LiveScoreboard?, at time: TimeInterval,
                          requireScoreForSlot: Int? = nil) -> LiveScoreboard? {
        if let lastTime, time <= lastTime || time - lastTime > 2 { readings = [] }
        lastTime = time
        readings.append((time, reading))
        readings.removeAll { time - $0.0 > 3 }
        guard let reading else { return nil }
        let matching = readings.filter { sample in
            guard sample.1?.turn == reading.turn else { return false }
            if let slot = requireScoreForSlot {
                guard let value = reading.score(slot: slot) else { return false }
                return sample.1?.score(slot: slot) == value
            }
            return true
        }
        guard matching.count >= 3, Double(matching.count) / Double(readings.count) >= 0.6,
              let first = matching.first, time-first.0 >= 1 else { return nil }
        // Only persist a number after it agrees on at least three observations.
        func confirmed(_ value: Int?, slot: Int) -> Int? {
            guard let value, matching.filter({ $0.1?.score(slot: slot) == value }).count >= 3 else { return nil }
            return value
        }
        return LiveScoreboard(turn: reading.turn, left: confirmed(reading.left, slot: 1), right: confirmed(reading.right, slot: 2))
    }
}

struct GameTracker {
    private(set) var progress: GameProgress
    private var detector = TurnDetector()
    private(set) var recovering = false
    private(set) var recoveryNextTurn: MachineTurn?
    private var acceptAfter = -Double.infinity

    init(progress: GameProgress = GameProgress()) { self.progress = progress }

    mutating func beginRecovery(at time: TimeInterval) {
        recoveryNextTurn = nil
        recovering = true; acceptAfter = time; detector.reset()
    }

    mutating func cancelRecovery(at time: TimeInterval) {
        recoveryNextTurn = nil
        recovering = false; acceptAfter = time; detector.reset()
    }

    mutating func observe(_ reading: LiveScoreboard?, at time: TimeInterval) -> GameProgress? {
        guard time > acceptAfter else { return nil }
        let outgoing = recovering ? (progress.turn?.slot ?? reading.map { 3-$0.turn.slot }) : nil
        guard let confirmed = detector.observe(reading, at: time, requireScoreForSlot: outgoing) else { return nil }
        let before = progress
        if let previous = progress.turn, previous.isLast, confirmed.turn == MachineTurn(slot: 1, ball: 1) {
            // The old game's final pair is still needed. Remember actual next-game
            // start, but never file its live scores as the old game's result.
            if recovering {
                recoveryNextTurn = confirmed.turn
            } else {
                progress.nextGameTurn = confirmed.turn
                progress.needsResync = true
            }
        } else if progress.nextGameTurn != nil {
            // Keep the old game selected until its finals are recorded/reviewed.
        } else if recovering {
            progress.accept(confirmed)
            recovering = false; detector.reset()
        } else if !progress.needsResync {
            if progress.turn == nil || progress.turn == confirmed.turn || progress.turn?.next == confirmed.turn {
                progress.accept(confirmed)
            } else {
                progress.needsResync = true
            }
        }
        return before == progress ? nil : progress
    }
}
