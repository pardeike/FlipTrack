import Foundation

struct MachineTurn: Codable, Equatable, Sendable {
    let slot: Int
    let ball: Int

    var next: MachineTurn? {
        if slot == 1 { return MachineTurn(slot: 2, ball: ball) }
        return ball < 3 ? MachineTurn(slot: 1, ball: ball + 1) : nil
    }
    var isLast: Bool { slot == 2 && ball == 3 }
}

struct LiveScoreboard: Codable, Equatable, Sendable {
    let turn: MachineTurn
    let left: Int?
    let right: Int?
    func score(slot: Int) -> Int? { slot == 1 ? left : right }
}

/// Live screens have BALL and differently sized active/inactive scores.
/// Their numbers are never a completed-game result.
enum LiveGameLayout {
    static func result(in observations: [DisplayText], activeSlot: Int? = nil) -> LiveScoreboard? {
        if GameDisplayLayout.isNewGame(in: observations) {
            return LiveScoreboard(turn: MachineTurn(slot: 1, ball: 1), left: 0, right: 0)
        }
        guard let layout = scoreboard(in: observations) else { return nil }
        let (ball, a, scores) = layout
        var left: Int?, right: Int?, sizedSlot: Int?
        if scores.count == 2 {
            let l = scores[0], r = scores[1]
            guard l.1.maxX <= r.1.minX, abs(l.1.maxY-r.1.maxY) < max(l.1.height,r.1.height) else { return nil }
            left = l.0; right = r.0
            if l.2 > r.2 * 1.15 && l.2 > a.height*1.9 { sizedSlot = 1 }
            if r.2 > l.2 * 1.15 && r.2 > a.height*1.9 { sizedSlot = 2 }
        } else if scores.count == 1, let activeSlot {
            // A single OCR number does not establish its side on a full frame.
            // Rectified display coordinates can still supply a partial score.
            if observations.allSatisfy(\.isInsideDisplay) {
                if scores[0].1.midX < 0.48 { left = scores[0].0 }
                if scores[0].1.midX > 0.52 { right = scores[0].0 }
            }
            return LiveScoreboard(turn: MachineTurn(slot: activeSlot, ball: ball), left: left, right: right)
        }
        if let activeSlot, let sizedSlot, activeSlot != sizedSlot { return nil }
        guard let slot = sizedSlot ?? activeSlot, (1...2).contains(slot) else { return nil }
        return LiveScoreboard(turn: MachineTurn(slot: slot, ball: ball), left: left, right: right)
    }

    /// A located scoreboard whose active score can be in the dark blink phase.
    /// This supplies context only; it never supplies an active-player vote.
    static func visibleBall(in observations: [DisplayText]) -> Int? {
        guard let layout = scoreboard(in: observations), !layout.scores.isEmpty,
              observations.allSatisfy(\.isInsideDisplay) else { return nil }
        return layout.ball
    }

    private static func scoreboard(in observations: [DisplayText]) -> (ball: Int, anchor: CGRect, scores: [(Int, CGRect, CGFloat)])? {
        var text = observations.filter { $0.confidence >= 0.5 }.map { word in
            // The dot-matrix 2 resembles Z. Correct only the complete ball label
            // inside a located display; the footer and score layout must still agree.
            if word.isInsideDisplay && word.text.uppercased() == "BALL Z" {
                return DisplayText(text: "BALL 2", confidence: word.confidence, bounds: word.bounds,
                                   rotation: word.rotation, isInsideDisplay: true,
                                   characterHeight: word.characterHeight, corners: word.corners)
            }
            return word
        }
        for word in text where word.text.uppercased().range(of: #"^BALL\s*[123]\s+FREE\s*PLAY\.?$"#, options: .regularExpression) != nil {
            let digit = word.text.first(where: \.isNumber)!
            let r = word.bounds
            text.removeAll { $0.text == word.text && $0.bounds == r }
            text.append(DisplayText(text: "BALL " + String(digit), confidence: word.confidence,
                                    bounds: CGRect(x:r.minX,y:r.minY,width:r.width*0.4,height:r.height), isInsideDisplay:word.isInsideDisplay))
            text.append(DisplayText(text: "FREE PLAY", confidence: word.confidence,
                                    bounds: CGRect(x:r.minX+r.width*0.45,y:r.minY,width:r.width*0.55,height:r.height), isInsideDisplay:word.isInsideDisplay))
        }
        // Vision sometimes separates the small ball digit from BALL.
        for word in text where word.text.uppercased() == "BALL" {
            let digits = text.filter { item in
                ["1","2","3"].contains(item.text) && item.bounds.minX >= word.bounds.maxX &&
                item.bounds.minX-word.bounds.maxX < word.bounds.width &&
                abs(item.bounds.midY-word.bounds.midY) < word.bounds.height
            }
            if digits.count == 1 {
                var combined = word
                combined = DisplayText(text: "BALL " + digits[0].text, confidence: min(word.confidence,digits[0].confidence),
                                       bounds: word.bounds.union(digits[0].bounds), isInsideDisplay: word.isInsideDisplay)
                text.removeAll { $0.text == word.text && $0.bounds == word.bounds }
                text.append(combined)
            }
        }
        guard !GameDisplayLayout.isBonusScreen(in: text) else { return nil }
        let balls = text.compactMap { observation -> (Int, CGRect)? in
            guard let range = observation.text.uppercased().range(of: #"^BALL\s*([123])\s*[._-]?$"#, options: .regularExpression),
                  let digit = observation.text[range].first(where: { $0.isNumber }), let ball = Int(String(digit)) else { return nil }
            return (ball, observation.bounds)
        }
        let anchors = text.filter { $0.text.uppercased().filter { !$0.isWhitespace }.trimmingCharacters(in: .punctuationCharacters) == "FREEPLAY" }
        guard balls.count == 1, anchors.count == 1 else { return nil }
        let (ball, b) = balls[0], a = anchors[0].bounds
        guard b.midX < a.midX, abs(b.midY - a.midY) < max(a.height, b.height) * 1.5 else { return nil }
        let scores = text.compactMap { observation -> (Int, CGRect, CGFloat)? in
            let r = observation.bounds
            guard !observation.isInsideDisplay || (r.minX > 0.015 && r.maxX < 0.985),
                  let score = EndGameLayout.score(from: observation.text), r.midY > max(a.maxY, b.maxY),
                  r.midY - a.midY < a.height * 12, abs(r.midX - a.midX) < a.width * 2.4,
                  r.height >= a.height * 0.65 else { return nil }
            return (score, r, observation.characterHeight ?? r.height)
        }.sorted { $0.1.midX < $1.1.midX }
        return (ball, a, scores)
    }

}
