import Foundation

struct AutomaticGameState: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case ready, playing, turnEnded, switchPlayers }

    private(set) var phase: Phase
    private(set) var firstPlayerIndex: Int
    private(set) var activeSlot = 0
    private(set) var finishedScores: [Int]?

    init(firstPlayerIndex: Int = 1, lastScores: [Int] = []) {
        self.firstPlayerIndex = firstPlayerIndex
        phase = lastScores.count == 2 ? .switchPlayers : .ready
        // The stored pair belongs to the previous game, whose starter is the
        // other player. The session already points to the upcoming game.
        if lastScores.count == 2 {
            finishedScores = firstPlayerIndex == 1 ? lastScores : Array(lastScores.reversed())
        }
    }

    var actionPlayerIndex: Int { (firstPlayerIndex + activeSlot) % 2 }
    var otherPlayerIndex: Int { 1 - actionPlayerIndex }

    mutating func gameStarted() {
        phase = .playing
        activeSlot = 0
        finishedScores = nil
    }

    mutating func playerIndicated(_ slot: Int) {
        guard phase != .switchPlayers, (0...1).contains(slot) else { return }
        phase = .playing
        activeSlot = slot
    }

    mutating func turnFinished() {
        guard phase != .switchPlayers else { return }
        phase = .turnEnded
        activeSlot = 1 - activeSlot
    }

    mutating func gameFinished(_ scores: DisplayResult) {
        finishedScores = firstPlayerIndex == 0 ? scores.scores : Array(scores.scores.reversed())
        firstPlayerIndex = 1 - firstPlayerIndex
        activeSlot = 0
        phase = .switchPlayers
    }
}

/// Explicit player prompts can name the person who is playing or being called
/// to play. Two player labels are a scoreboard, not an active-player signal.
enum GameDisplayLayout {
    static func isTurnEnd(in observations: [DisplayText]) -> Bool {
        observations.contains { header in
            let normalized = header.text.uppercased().filter { !$0.isWhitespace }
            guard header.confidence >= 0.7, normalized == "TOTALBONUS" else { return false }
            let h = header.bounds
            guard h.width > 0, h.height > 0 else { return false }
            if header.isInsideDisplay {
                return h.midY > 0.5 && abs(h.midX - 0.5) < 0.2
            }
            // Without a visible frame, the centered amount below the heading
            // locates the bonus layout relative to the text, not the camera.
            return observations.contains { amount in
                let a = amount.bounds
                return amount.confidence >= 0.5 && EndGameLayout.score(from: amount.text) != nil &&
                    a.maxY < h.minY && h.midY - a.midY < h.height * 5 &&
                    abs(a.midX - h.midX) < h.width * 0.2 &&
                    a.height >= h.height * 0.8 && a.width < h.width * 1.5
            }
        }
    }

    static func activePlayer(in observations: [DisplayText]) -> Int? {
        var slots = Set<Int>()
        for observation in observations where observation.isInsideDisplay && observation.confidence >= 0.7 {
            let text = observation.text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            for slot in 1...2 {
                let pattern = "^(?:PLAYER ?\(slot)(?: UP| SHOOT AGAIN)?|(?:UP|SHOOT AGAIN) PLAYER ?\(slot))[.!]?$"
                if text.range(of: pattern, options: .regularExpression) != nil { slots.insert(slot - 1) }
            }
        }
        return slots.count == 1 ? slots.first : nil
    }

    static func isNewGame(in observations: [DisplayText]) -> Bool {
        let readable = observations.filter { $0.confidence >= 0.5 }
        let anchors = readable.filter {
            $0.confidence >= 0.7 && $0.text.uppercased().replacingOccurrences(of: " ", with: "")
                .trimmingCharacters(in: .punctuationCharacters) == "FREEPLAY"
        }
        var matches = 0
        for anchor in anchors {
            let a = anchor.bounds
            guard a.width > 0, a.height > 0 else { continue }
            // BALL may lose its small trailing 1 in OCR. Reject other ball numbers.
            let ball = readable.contains {
                let t = $0.text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let r = $0.bounds
                return $0.confidence >= 0.7 && (t == "BALL 1" || t == "BALL") && r.midX < a.minX &&
                    a.minX - r.maxX < a.width && abs(r.midY - a.midY) < max(r.height, a.height)
            }
            guard ball else { continue }
            let scores = readable.filter {
                let r = $0.bounds
                return r.minY > a.maxY && r.midY - a.midY < a.height * 12 &&
                    abs(r.midX - a.midX) < a.width * 2 && r.height >= a.height * 0.65 &&
                    ($0.text.range(of: #"^0{1,2}\s*-?$"#, options: .regularExpression) != nil || EndGameLayout.score(from: $0.text) != nil)
            }.sorted { $0.bounds.midX < $1.bounds.midX }
            guard scores.count == 2, scores.allSatisfy({
                $0.text.range(of: #"^0{1,2}\s*-?$"#, options: .regularExpression) != nil
            }) else { continue }
            let l = scores[0].bounds, r = scores[1].bounds
            // The active zero is large, with the other zero smaller to its right.
            guard r.height > 0, l.height / r.height > 1.4, l.height / r.height < 3,
                  l.maxX < r.minX, l.midX < a.midX, r.midX > a.maxX - a.width * 0.2,
                  abs(l.maxY - r.maxY) < l.height * 0.65 else { continue }
            matches += 1
        }
        return matches == 1
    }
}

/// Debounce a player prompt without alternating on unreadable frames.
struct PlayerPromptDetector {
    private var candidate: Int?
    private var since: TimeInterval?
    private var lastTime: TimeInterval?
    private var count = 0

    mutating func observe(_ slot: Int?, at time: TimeInterval) -> Int? {
        if slot != candidate || lastTime.map({ time <= $0 || time - $0 > 2 }) == true {
            candidate = slot
            since = nil
            count = 0
        }
        lastTime = time
        guard let slot else { since = nil; count = 0; return nil }
        if since == nil { since = time }
        count += 1
        return count >= 2 && time - (since ?? time) >= 0.5 ? slot : nil
    }
}

/// Emit once per bonus screen. Unreadable frames and pauses never rearm it.
struct TurnEndDetector {
    private var confirmation = PlayerPromptDetector()
    private var latched = false
    private var absentSince: TimeInterval?
    private var lastTime: TimeInterval?

    mutating func discardPendingReadings() {
        confirmation = PlayerPromptDetector()
        absentSince = nil
        lastTime = nil
    }

    mutating func observe(_ bonus: Bool, at time: TimeInterval, readable: Bool) -> Bool {
        if lastTime.map({ time <= $0 || time - $0 > 2 }) == true {
            discardPendingReadings()
        }
        lastTime = time
        if bonus {
            absentSince = nil
            let confirmed = confirmation.observe(0, at: time) != nil
            guard confirmed, !latched else { return false }
            latched = true
            return true
        }
        _ = confirmation.observe(nil, at: time)
        if readable {
            if absentSince == nil { absentSince = time }
            if time - (absentSince ?? time) >= 2 { latched = false }
        } else {
            absentSince = nil
        }
        return false
    }
}
