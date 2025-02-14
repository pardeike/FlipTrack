import Foundation

@MainActor
class EventViewModel: ObservableObject {
    @Published var games: [Game] = []

    // Hard-coded settings.
    let player1: String = "Andreas"
    let player2: String = "Fredrik"

    private var eventData: EventData

    init() {
        // Sample games.
        let sampleGames = [
            Game(id: 1, leftScore: 500, rightScore: 300),
            Game(id: 2, leftScore: 200, rightScore: 450),
            Game(id: 3, leftScore: 600, rightScore: 600)
        ]
        eventData = EventData(games: sampleGames)
        games = sampleGames
    }

    // Total scores computed per event. For odd-numbered games, Andreas is first (leftScore) and Fredrik is second (rightScore).
    // For even-numbered games, the roles are swapped.
    var playerTotals: (player1Score: Int, player2Score: Int) {
        var score1 = 0, score2 = 0
        for game in games {
            if game.id % 2 != 0 {
                score1 += game.leftScore
                score2 += game.rightScore
            } else {
                score1 += game.rightScore
                score2 += game.leftScore
            }
        }
        return (score1, score2)
    }

    // Number of games won per player.
    var playerWins: (player1Wins: Int, player2Wins: Int) {
        var wins1 = 0, wins2 = 0
        for game in games {
            let p1Score = (game.id % 2 != 0) ? game.leftScore : game.rightScore
            let p2Score = (game.id % 2 != 0) ? game.rightScore : game.leftScore
            if p1Score > p2Score {
                wins1 += 1
            } else if p2Score > p1Score {
                wins2 += 1
            }
        }
        return (wins1, wins2)
    }

    // Computes who starts the current (or next) game.
    var currentGameInfo: (firstPlayer: String, secondPlayer: String) {
        let nextGameNumber = games.count + 1
        if nextGameNumber % 2 != 0 {
            return (firstPlayer: player1, secondPlayer: player2)
        } else {
            return (firstPlayer: player2, secondPlayer: player1)
        }
    }

    // Asynchronously adds a new game.
    func addGame(leftScore: Int, rightScore: Int) async {
        let newGame = Game(id: games.count + 1, leftScore: leftScore, rightScore: rightScore)
        await eventData.addGame(newGame)
        games.append(newGame)
    }

    // In a real app this would fetch data from SwiftData.
    func refreshGames() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
        games = await eventData.games
    }
}
