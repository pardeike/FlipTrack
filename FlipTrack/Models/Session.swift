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
        guard gameID == currentGameID, !sessionFinished else { throw RecordingError.staleGame }
        progressData = try JSONEncoder().encode(progress)
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    @MainActor
    func prepareCurrentGame(in context: ModelContext) throws {
        guard currentGameID == nil else { return }
        currentGameID = UUID()
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    @MainActor
    func stageCapture(_ result: DisplayResult, in context: ModelContext) throws {
        if currentGameID == nil { currentGameID = UUID() }
        pendingCaptureScores = result.scores
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    @MainActor
    func record(_ result: DisplayResult, for gameID: UUID? = nil, in context: ModelContext) throws {
        if let gameID {
            // A retry of a committed capture is a no-op, even after relaunch.
            if games?.contains(where: { $0.captureGameID == gameID }) == true { return }
            guard gameID == currentGameID else { throw RecordingError.staleGame }
        }
        let number = upcomingGameNumber
        let nextObservedTurn = progress.nextGameTurn
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
        // Latch the first player to reach ten confirmed wins. An observed next
        // game is allowed to finish; merely allocating an ID never extends play.
        if raceWinnerIndex == nil {
            var wins = [0, 0]
            for saved in games ?? [] where saved.id != game.id && saved.winningIndex >= 0 { wins[saved.winningIndex] += 1 }
            if game.winningIndex >= 0 { wins[game.winningIndex] += 1 }
            raceWinnerIndex = wins.firstIndex(where: { $0 >= 10 })
        }
        if raceWinnerIndex != nil, nextObservedTurn == nil {
            sessionFinished = true
            scanningRequested = false
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
    public var lastRecordedGame: Game? {
        if let lastRecordedGameID, let game = games?.first(where: { $0.id == lastRecordedGameID }) { return game }
        return games?.max { $0.nr < $1.nr }
    }

    @MainActor
    func undoLastGame(in context: ModelContext) throws {
        guard pendingCaptureScores.isEmpty else { throw RecordingError.pendingCapture }
        guard let game = lastRecordedGame else { return }
        let starter = game.startingPlayerIndex ?? game.nr % 2
        nextGameNumber = game.nr
        currentGameNumberOverride = game.nr
        startingPlayerOverride = starter
        currentGameID = game.captureGameID ?? UUID()
        rejectCapture(lastCapturedScores)
        pendingCaptureScores = starter == 0 ? game.scores : Array(game.scores.reversed())
        lastCapturedScores = game.previousCapturedScores
        lastRecordedGameID = games?.filter { $0.id != game.id }.max { $0.nr < $1.nr }?.id
        allowRepeatedCapture = false
        progressData = try JSONEncoder().encode(GameProgress(observedStart: true, needsResync: true))
        games?.removeAll { $0.id == game.id }
        context.delete(game)
        recalculateRace()
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    @MainActor
    func discardPendingCapture(in context: ModelContext) throws {
        rejectCapture(pendingCaptureScores)
        pendingCaptureScores = []
        do { try context.save() }
        catch { context.rollback(); throw error }
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
