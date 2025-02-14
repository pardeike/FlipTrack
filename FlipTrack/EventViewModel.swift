import Foundation

var rndScore: Int { 10 * (Range(100...60000).randomElement() ?? 0) }

@MainActor
class EventViewModel: ObservableObject {
    @Published var games: [Game] = []

    let player1: String = "Andreas"
    let player2: String = "Fredrik"

    private var eventData: EventData

    init() {
        let sampleGames: [Game] = [
            /*Game(id: 1, scores: [rndScore, rndScore]),
            Game(id: 2, scores: [rndScore, rndScore]),
            Game(id: 3, scores: [rndScore, rndScore]),
            Game(id: 4, scores: [rndScore, rndScore]),
            Game(id: 5, scores: [rndScore, rndScore]),
            Game(id: 6, scores: [rndScore, rndScore]),
            Game(id: 7, scores: [rndScore, rndScore]),
            Game(id: 8, scores: [rndScore, rndScore]),
            Game(id: 9, scores: [rndScore, rndScore]),
            Game(id: 10, scores: [rndScore, rndScore]),
            Game(id: 11, scores: [rndScore, rndScore]),
            Game(id: 12, scores: [rndScore, rndScore]),*/
        ]
        eventData = EventData(games: sampleGames)
        games = sampleGames
    }

    var playerTotals: [Int] {
        let res = games.reduce(Game()) { Game(scores: [$0.scores[0] + $1.scores[0], $0.scores[1] + $1.scores[1]]) }
        return res.scores
    }

    var playerWins: [Int] {
        var wins = [0, 0]
        _ = games.map { wins[$0.winningIndex] += 1 }
        return wins
    }
    
    var firstPlayerIndex: Int { (games.count + 1) % 2 }
    var firstPlayer: String { [player1, player2][firstPlayerIndex] }
    var secondPlayer: String { [player1, player2][1 - firstPlayerIndex] }

    func addGame(scores: [Int]) async {
        let newGame = Game(nr: games.count + 1, scores: scores)
        await eventData.addGame(newGame)
        games.append(newGame)
    }

    // In a real app this would fetch data from SwiftData.
    func refreshGames() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        games = await eventData.games
    }
}
