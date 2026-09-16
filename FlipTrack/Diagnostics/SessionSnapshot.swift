import Foundation

/// A value snapshot, shared by diagnostics and the scanner's correction boundary.
/// Machine slots stay separate from person identities; edits remain authoritative.
struct SessionSnapshot: Codable, Equatable, Sendable {
    let sessionID: UUID
    let date: Date
    let players: [String]
    let id: UUID?
    let number: Int
    let starter: Int
    let progress: GameProgress
    let awaitingNextStart: Bool
    let finished: Bool
    let raceWinner: Int?
    let lastScores: [Int]
    let allowRepeated: Bool
    let rejected: [String]
    let pending: [Int]
    let deferredGame: Data?
    let games: [SavedGame]

    struct SavedGame: Codable, Equatable, Sendable {
        let id: UUID
        let number: Int
        let scores: [Int]
        let starter: Int?
        let captureID: UUID?
    }

    @MainActor init(_ session: Session) {
        sessionID = session.id
        date = session.date
        players = [session.player1, session.player2]
        id = session.currentGameID
        number = session.upcomingGameNumber
        starter = session.firstPlayerIndex
        progress = session.progress
        awaitingNextStart = session.awaitingNextStart
        finished = session.sessionFinished
        raceWinner = session.raceWinnerIndex
        lastScores = session.lastCapturedScores
        allowRepeated = session.allowRepeatedCapture
        rejected = session.rejectedCaptureSignatures
        pending = session.pendingCaptureScores
        deferredGame = session.deferredGameData
        games = (session.games ?? []).map {
            SavedGame(id: $0.id, number: $0.nr, scores: $0.scores, starter: $0.startingPlayerIndex, captureID: $0.captureGameID)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
