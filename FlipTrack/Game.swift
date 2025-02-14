import Foundation

public struct Game: Identifiable {
    public var id = UUID()
    public var nr: Int
    public var scores: [Int]

    public var winningIndex: Int {
        scores[1] >= scores[0] ? 1 : 0
    }

    public init(nr: Int, scores: [Int]) {
        self.nr = nr
        self.scores = scores
    }

    public init() {
        self.init(nr: 0, scores: [0, 0])
    }
}
