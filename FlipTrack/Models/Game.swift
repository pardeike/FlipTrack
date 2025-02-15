import SwiftData
import Foundation

@Model
public final class Game: Identifiable, Hashable {
    public var id = UUID()
    public var nr = 0
    public var scores = [0, 0]
    public var session: Session?

    public var winningIndex: Int {
        if (scores[0] == scores[1]) { return -1 }
        return scores[1] >= scores[0] ? 1 : 0
    }

    public init(nr: Int, scores: [Int], session: Session) {
        self.nr = nr
        self.scores = nr % 2 == 0 ? scores : scores.reversed()
        self.session = session
    }

    public convenience init() {
        self.init(nr: 0, scores: [0, 0], session: Session(date: Date.now))
    }
}
