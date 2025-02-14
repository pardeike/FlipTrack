import Foundation

var rndScore: Int { 10 * (Range(100...60000).randomElement() ?? 0) }

@MainActor
public class EventViewModel: ObservableObject {
    @Published public var events: [Event] = []
    @Published public var games: [Game] = []

    public let player1: String = "Andreas"
    public let player2: String = "Fredrik"

    private var eventData: EventData

    public static let sampleGames: [Game] = [
        Game(nr: 1, scores: [rndScore, rndScore]),
        Game(nr: 2, scores: [rndScore, rndScore]),
        Game(nr: 3, scores: [rndScore, rndScore]),
        Game(nr: 4, scores: [rndScore, rndScore]),
        Game(nr: 5, scores: [rndScore, rndScore]),
        Game(nr: 6, scores: [rndScore, rndScore]),
        Game(nr: 7, scores: [rndScore, rndScore]),
        Game(nr: 8, scores: [rndScore, rndScore]),
        Game(nr: 9, scores: [rndScore, rndScore]),
        Game(nr: 10, scores: [rndScore, rndScore]),
        Game(nr: 11, scores: [rndScore, rndScore]),
        Game(nr: 12, scores: [rndScore, rndScore])
    ]

    public init() {
        eventData = EventData(events: [], games: [])
        events = []
        games = []
    }

    public var playerTotals: [Int] {
        let res = games.reduce(Game()) { Game(nr: 0, scores: [$0.scores[0] + $1.scores[0], $0.scores[1] + $1.scores[1]]) }
        return res.scores
    }

    public var playerWins: [Int] {
        var wins = [0, 0]
        _ = games.map { wins[$0.winningIndex] += 1 }
        return wins
    }

    public var firstPlayerIndex: Int { (games.count + 1) % 2 }
    public var firstPlayer: String { [player1, player2][firstPlayerIndex] }
    public var secondPlayer: String { [player1, player2][1 - firstPlayerIndex] }

    public func addGame(scores: [Int]) async {
        let newGame = Game(nr: games.count + 1, scores: scores)
        await eventData.addGame(newGame)
        games.append(newGame)
    }

    public func refreshGames() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        games = await eventData.games
    }
}
