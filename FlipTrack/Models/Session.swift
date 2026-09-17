import SwiftData
import Foundation

@Model
public final class Session: Identifiable, Hashable {
    public var id = UUID()
    public var date = Date()
    public var player1 = "Andreas"
    public var player2 = "Fredrik"
    // Raw display order, independent of score corrections and player assignment.
    public var lastCapturedScores: [Int] = []
    public var nextGameNumber: Int = 1
    public var currentGameNumberOverride: Int?
    public var startingPlayerOverride: Int?
    public var currentGameID: UUID?
    public var scanningRequested = false
    public var allowRepeatedCapture = false
    public var lastRecordedGameID: UUID?
    public var pendingCaptureScores: [Int] = []
    public var rejectedCaptureSignatures: [String] = []
    public var progressData: Data?
    public var raceWinnerIndex: Int?
    public var sessionFinished = false
    public var awaitingNextStart = false
    public var deferredGameData: Data?
    /// Additive, optional storage for observed features. Independent of wins,
    /// score editing and the currently selected/undone game.
    public var collectedFeatureData: Data?
    @Relationship(deleteRule: .cascade, inverse: \Game.session)
    public var games: [Game]?

    public init(date: Date) {
        self.date = date
        games = []
    }
    
    public var playerTotals: [Int] {
        var totals = [0, 0]
        _ = games?.map { totals[0] += $0.scores[0]; totals[1] += $0.scores[1] }
        return totals
    }
    
    public var playerWins: [Int] {
        var wins = [0, 0]
        _ = games?.filter { $0.winningIndex >= 0 }.map { wins[$0.winningIndex] += 1 }
        return wins
    }
    
    public var highScores: [Int] {
        var highest = [0, 0]
        _ = games?.map {
            highest[0] = max(highest[0], $0.scores[0])
            highest[1] = max(highest[1], $0.scores[1])
        }
        return highest
    }
    
    public var averageScores: [Int] {
        guard let games, games.count > 0 else { return [0, 0] }
        let n = Double(games.count)
        return [
            Int(Double(playerTotals[0]) / n),
            Int(Double(playerTotals[1]) / n),
        ]
    }
    
    public var upcomingGameNumber: Int {
        if let currentGameNumberOverride, currentGameNumberOverride > 0,
           games?.contains(where: { $0.nr == currentGameNumberOverride }) != true {
            return currentGameNumberOverride
        }
        return max(nextGameNumber, (games?.map(\.nr).max() ?? 0) + 1)
    }
    public var firstPlayerIndex: Int {
        if let startingPlayerOverride, (0...1).contains(startingPlayerOverride) { return startingPlayerOverride }
        return upcomingGameNumber % 2
    }

    var progress: GameProgress {
        guard let progressData else { return GameProgress() }
        return (try? JSONDecoder().decode(GameProgress.self, from: progressData)) ?? GameProgress(needsResync: true)
    }

    var currentPlayerIndex: Int {
        progress.turn?.slot == 2 ? 1-firstPlayerIndex : firstPlayerIndex
    }

    /// Live scores are already in machine order. Only the names follow the
    /// starter; saved Game.scores remain in permanent person order.
    var activeDisplay: ActiveGameDisplay {
        let state = progress
        let missingFinals = state.nextGameTurn != nil
        let visible = !sessionFinished && pendingCaptureScores.isEmpty
        return ActiveGameDisplay(leftName: firstPlayer, rightName: secondPlayer,
            leftPerson: firstPlayerIndex,
            left: missingFinals ? nil : state.left, right: missingFinals ? nil : state.right,
            turn: state.observedStart && !state.needsResync && !missingFinals ? state.turn : nil,
            uncertain: state.needsResync, missingFinals: missingFinals, visible: visible)
    }

    func recalculateRace() {
        var wins = [0, 0]
        raceWinnerIndex = nil
        for game in (games ?? []).sorted(by: { $0.nr < $1.nr }) where game.winningIndex >= 0 {
            wins[game.winningIndex] += 1
            if wins[game.winningIndex] == 10 { raceWinnerIndex = game.winningIndex; break }
        }
        sessionFinished = raceWinnerIndex != nil && !progress.observedStart
        if sessionFinished { scanningRequested = false }
    }

    @MainActor
    func updateProgress(_ progress: GameProgress, for gameID: UUID?, in context: ModelContext) throws {
        let before = SessionSnapshot(self)
        guard gameID == currentGameID, !sessionFinished else { throw RecordingError.staleGame }
        if progress.observedStart { awaitingNextStart = false }
        progressData = try JSONEncoder().encode(progress)
        do { try context.save(); Telemetry.shared.change("session.progressSaved", before: before, session: self) }
        catch { context.rollback(); Telemetry.shared.log("session.progressSaved.error", ["message": error.localizedDescription]); throw error }
    }

    @MainActor
    func resetCurrentTracking(in context: ModelContext) throws {
        guard !sessionFinished, progress.nextGameTurn == nil, deferredGameData == nil else {
            throw RecordingError.staleGame
        }
        guard pendingCaptureScores.isEmpty else { throw RecordingError.pendingCapture }
        let before = SessionSnapshot(self)
        // Keep actual start evidence for the first-to-ten continuation rule.
        // Clearing readings must not invent zero scores or a confirmed turn.
        progressData = try JSONEncoder().encode(GameProgress(observedStart: progress.observedStart))
        awaitingNextStart = true
        allowRepeatedCapture = false
        do { try context.save(); Telemetry.shared.change("session.trackingReset", before: before, session: self) }
        catch { context.rollback(); Telemetry.shared.log("session.trackingReset.error", ["message": error.localizedDescription]); throw error }
    }

    @MainActor
    func prepareCurrentGame(in context: ModelContext) throws {
        let before = SessionSnapshot(self)
        guard currentGameID == nil else { return }
        currentGameID = UUID()
        do { try context.save(); Telemetry.shared.change("session.prepared", before: before, session: self) }
        catch { context.rollback(); Telemetry.shared.log("session.prepared.error", ["message": error.localizedDescription]); throw error }
    }

    @MainActor
    func stageCapture(_ result: DisplayResult, in context: ModelContext) throws {
        let before = SessionSnapshot(self)
        if currentGameID == nil { currentGameID = UUID() }
        pendingCaptureScores = result.scores
        do { try context.save(); Telemetry.shared.change("session.captureStaged", before: before, session: self) }
        catch { context.rollback(); Telemetry.shared.log("session.captureStaged.error", ["message": error.localizedDescription]); throw error }
    }

    @MainActor
    func record(_ result: DisplayResult, for gameID: UUID? = nil, in context: ModelContext) throws {
        let before = SessionSnapshot(self)
        if let gameID {
            // A retry of a committed capture is a no-op, even after relaunch.
            if games?.contains(where: { $0.captureGameID == gameID }) == true { return }
            guard gameID == currentGameID else { throw RecordingError.staleGame }
        }
        let deferred = try deferredGameData.map { try JSONDecoder().decode(DeferredGame.self, from: $0) }
        let number = upcomingGameNumber
        let nextObservedTurn = progress.nextGameTurn
        awaitingNextStart = nextObservedTurn == nil
        let explicitNumber = currentGameNumberOverride != nil
        let starter = firstPlayerIndex
        let ordered = firstPlayerIndex == 0 ? result.scores : result.scores.reversed().map { $0 }
        let game = Game(nr: number, scores: ordered, session: self)
        // Set the relationship once. SwiftData maintains its inverse.
        game.startingPlayerIndex = starter
        game.captureGameID = currentGameID ?? UUID()
        game.previousCapturedScores = lastCapturedScores
        context.insert(game)
        lastRecordedGameID = game.id
        allowRepeatedCapture = false
        nextGameNumber = number + 1
        if explicitNumber {
            var next = number + 1
            while games?.contains(where: { $0.nr == next }) == true { next += 1 }
            currentGameNumberOverride = next
        }
        startingPlayerOverride = 1 - starter
        lastCapturedScores = result.scores
        currentGameID = UUID()
        pendingCaptureScores = []
        progressData = try JSONEncoder().encode(GameProgress(turn: nextObservedTurn, observedStart: nextObservedTurn != nil))
        if let deferred {
            currentGameID = deferred.id
            nextGameNumber = deferred.number
            currentGameNumberOverride = deferred.number
            startingPlayerOverride = deferred.starter
            progressData = try JSONEncoder().encode(deferred.progress)
            awaitingNextStart = false
        }
        deferredGameData = nil
        // Use chronological game order for both normal saves and a missing
        // historical result. Appending a trailing game preserves the first winner.
        recalculateRace()
        do {
            try context.save(); Telemetry.shared.change("session.gameSaved", before: before, session: self)
        } catch {
            context.rollback()
            Telemetry.shared.log("session.gameSaved.error", ["message": error.localizedDescription])
            throw error
        }
    }
    public var lastRecordedGame: Game? {
        if let lastRecordedGameID, let game = games?.first(where: { $0.id == lastRecordedGameID }) { return game }
        return games?.max { $0.nr < $1.nr }
    }

    @MainActor
    func undoLastGame(in context: ModelContext) throws {
        let before = SessionSnapshot(self)
        guard pendingCaptureScores.isEmpty else { throw RecordingError.pendingCapture }
        guard let game = lastRecordedGame else { return }
        let starter = game.startingPlayerIndex ?? game.nr % 2
        if deferredGameData == nil, progress.observedStart, progress.turn != nil {
            deferredGameData = try JSONEncoder().encode(DeferredGame(id: currentGameID ?? UUID(),
                number: upcomingGameNumber, starter: firstPlayerIndex, progress: progress))
        }
        let deferred = try deferredGameData.map { try JSONDecoder().decode(DeferredGame.self, from: $0) }
        let continuationTurn = deferred?.progress.turn
        awaitingNextStart = false
        nextGameNumber = game.nr
        currentGameNumberOverride = game.nr
        startingPlayerOverride = starter
        currentGameID = game.captureGameID ?? UUID()
        rejectCapture(lastCapturedScores)
        pendingCaptureScores = starter == 0 ? game.scores : Array(game.scores.reversed())
        lastCapturedScores = game.previousCapturedScores
        lastRecordedGameID = games?.filter { $0.id != game.id }.max { $0.nr < $1.nr }?.id
        allowRepeatedCapture = false
        progressData = try JSONEncoder().encode(GameProgress(observedStart: true, needsResync: true, nextGameTurn: continuationTurn))
        games?.removeAll { $0.id == game.id }
        context.delete(game)
        recalculateRace()
        do { try context.save(); Telemetry.shared.change("session.gameUndone", before: before, session: self) }
        catch { context.rollback(); Telemetry.shared.log("session.gameUndone.error", ["message": error.localizedDescription]); throw error }
    }

    @MainActor
    func discardPendingCapture(in context: ModelContext) throws {
        let before = SessionSnapshot(self)
        rejectCapture(pendingCaptureScores)
        pendingCaptureScores = []
        do { try context.save(); Telemetry.shared.change("session.captureDiscarded", before: before, session: self) }
        catch { context.rollback(); Telemetry.shared.log("session.captureDiscarded.error", ["message": error.localizedDescription]); throw error }
    }

    private func rejectCapture(_ scores: [Int]) {
        guard scores.count == 2 else { return }
        let signature = DisplayResult(left: scores[0], right: scores[1]).signature
        if !rejectedCaptureSignatures.contains(signature) { rejectedCaptureSignatures.append(signature) }
        if rejectedCaptureSignatures.count > 20 { rejectedCaptureSignatures.removeFirst(rejectedCaptureSignatures.count - 20) }
    }

    enum RecordingError: LocalizedError {
        case staleGame, pendingCapture
        var errorDescription: String? {
            switch self {
            case .staleGame:
                "This reading belongs to a different game. Review the current game before saving."
            case .pendingCapture:
                "Review or discard the current captured scores before undoing another game."
            }
        }
    }

    public var firstPlayer: String { [player1, player2][firstPlayerIndex] }
    public var secondPlayer: String { [player1, player2][1 - firstPlayerIndex] }
}

/// While an older result is reopened, retain the game already being played.
/// This is separate from that older game's draft and survives app termination.
struct DeferredGame: Codable, Equatable, Sendable {
    let id: UUID
    let number: Int
    let starter: Int
    let progress: GameProgress
}

struct ActiveGameDisplay {
    let leftName: String
    let rightName: String
    let leftPerson: Int
    let left: Int?
    let right: Int?
    let turn: MachineTurn?
    let uncertain: Bool
    let missingFinals: Bool
    let visible: Bool
}
