import Foundation

struct Game: Identifiable {
    var id = UUID()
    var nr = 0
    var scores = [0, 0]
    
    var winningIndex: Int {
        scores[1] >= scores[0] ? 1 : 0
    }
}
