import SwiftData
import Foundation

@Model
public final class Session: Identifiable, Hashable {
    public var id = UUID()
    public var date = Date()
    public var player1 = "Andreas"
    public var player2 = "Fredrik"
    @Relationship(deleteRule: .cascade, inverse: \Game.session)
    public var games: [Game]?

    public init(date: Date) {
        self.date = date
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
    
    public var firstPlayerIndex: Int { ((games?.count ?? 0) + 1) % 2 }
    public var firstPlayer: String { [player1, player2][firstPlayerIndex] }
    public var secondPlayer: String { [player1, player2][1 - firstPlayerIndex] }
}
