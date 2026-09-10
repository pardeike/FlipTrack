import Foundation

struct DisplayText: Sendable {
    let text: String
    let confidence: Float
    /// Vision coordinates: origin at bottom left, normalized to the image.
    let bounds: CGRect
    var rotation: CGFloat = 0
    var isInsideDisplay = false
}

struct DisplayResult: Equatable, Sendable {
    let left: Int
    let right: Int
    var scores: [Int] { [left, right] }
    var isZero: Bool { left == 0 && right == 0 }
}

/// The Indiana Jones two-player result layout, including the angled holder view.
enum EndGameLayout {
    static func score(from text: String) -> Int? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        // Correct isolated letter/digit confusion, but never parse a numeric prefix
        // of a label, bonus message, decimal, or malformed thousands grouping.
        let normalized = text.replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "I", with: "1")
            .replacingOccurrences(of: "L", with: "1")
            .replacingOccurrences(of: "S", with: "5")
            .replacingOccurrences(of: "B", with: "8")
        let pattern = #"^(?:[0-9]{1,10}|[0-9]{1,3}(?:,[0-9]{3})+|[0-9]{1,3}(?:\.[0-9]{3})+|[0-9]{1,3}(?: [0-9]{3})+)$"#
        guard text.contains(where: { $0.isASCII && $0.isNumber }),
              normalized.range(of: pattern, options: .regularExpression) != nil,
              let value = Int(normalized.filter { $0.isNumber }),
              value >= 0, value < 10_000_000_000, value % 10 == 0 else { return nil }
        return value
    }

    static func hasDisplayText(in observations: [DisplayText]) -> Bool {
        observations.contains {
            guard $0.confidence >= 0.5 else { return false }
            let text = $0.text.uppercased()
            return score(from: text) != nil ||
                text.range(of: #"\b(?:TOTAL BONUS|BALL|PLAYER|GAME|CREDITS?|FREE ?PLAY)\b"#, options: .regularExpression) != nil
        }
    }

    static func result(in observations: [DisplayText]) -> DisplayResult? {
        // A live score screen also says FREE PLAY; BALL distinguishes it from results.
        guard !observations.contains(where: {
            $0.confidence >= 0.5 && $0.text.uppercased().range(of: #"^BALL(?:\s|$)"#, options: .regularExpression) != nil
        }) else { return nil }
        guard !GameDisplayLayout.isTurnEnd(in: observations) else { return nil }
        let readable = observations.filter { $0.confidence >= 0.5 }
        let anchors = readable.filter {
            $0.text.uppercased().replacingOccurrences(of: " ", with: "")
                .trimmingCharacters(in: .punctuationCharacters) == "FREEPLAY"
        }
        var results: [DisplayResult] = []
        for anchor in anchors {
            let a = anchor.bounds
            guard a.width > 0, a.height > 0 else { continue }
            let scores = readable.compactMap { observation -> (Int, CGRect)? in
                let r = observation.bounds
                guard let score = score(from: observation.text),
                      r.midY > a.maxY,
                      r.midY - a.midY < a.height * 12,
                      abs(r.midX - a.midX) < a.width * 2.4,
                      r.height >= a.height * 0.65, r.height <= a.height * 3.5 else { return nil }
                return (score, r)
            }.sorted { $0.1.midX < $1.1.midX }
            guard scores.count == 2 else { continue }
            let (left, l) = scores[0]
            let (right, r) = scores[1]
            guard l.midX < a.midX, r.midX > a.midX,
                  l.maxX < r.minX,
                  abs(l.midY - r.midY) < max(l.height, r.height) * 1.25,
                  max(l.height, r.height) / min(l.height, r.height) < 2 else { continue }
            results.append(DisplayResult(left: left, right: right))
        }
        return results.count == 1 ? results[0] : nil
    }
}

/// Time-based confirmation and a latch prevent repeated saves from static or
/// cycling results. Missing/uncertain frames count against confirmation.
struct EndGameDetector {
    private struct Reading {
        let time: TimeInterval
        let result: DisplayResult?
    }
    private var readings: [Reading] = []
    private var lastTime: TimeInterval?
    private var absentSince: TimeInterval?
    private var startSince: TimeInterval?
    private var startCount = 0
    private var startLatched = false
    private(set) var detectedStart = false
    private(set) var lastRegistered: DisplayResult?
    private(set) var armed: Bool
    let requiredReadings: Int
    let historyLimit: Int

    init(lastScores: [Int] = [], requiredReadings: Int = 4, historyLimit: Int = 10) {
        lastRegistered = lastScores.count == 2 ? DisplayResult(left: lastScores[0], right: lastScores[1]) : nil
        armed = lastRegistered == nil
        self.requiredReadings = max(4, min(10, requiredReadings))
        self.historyLimit = max(self.requiredReadings, min(20, historyLimit))
    }

    /// Pausing discards incomplete evidence while retaining saved-game latches.
    mutating func discardPendingReadings() {
        readings.removeAll()
        lastTime = nil
        absentSince = nil
        startSince = nil
        startCount = 0
        detectedStart = false
    }

    mutating func observe(_ result: DisplayResult?, at time: TimeInterval, readable: Bool, newGame: Bool = false) -> DisplayResult? {
        detectedStart = false
        // A stopped camera or a long OCR stall is not evidence of a new game.
        if let lastTime, time <= lastTime || time - lastTime > 2 {
            readings.removeAll()
            absentSince = nil
            startSince = nil
            startCount = 0
        }
        lastTime = time
        if newGame || result?.isZero == true {
            readings.removeAll()
            absentSince = nil
            if !startLatched {
                if startSince == nil { startSince = time }
                startCount += 1
                if startCount >= 3, time - (startSince ?? time) >= 1 {
                    detectedStart = true
                    startLatched = true
                    armed = true
                    startSince = nil
                    startCount = 0
                }
            }
            return nil
        }
        startSince = nil
        startCount = 0
        if !armed {
            if result != nil || !readable {
                absentSince = nil
            } else {
                if absentSince == nil { absentSince = time }
                if time - (absentSince ?? time) >= 8 { armed = true }
            }
            readings.removeAll()
            return nil
        }
        readings.append(Reading(time: time, result: result))
        readings.removeAll { time - $0.time > 5 }
        if readings.count > historyLimit { readings.removeFirst(readings.count - historyLimit) }
        guard let result, result != lastRegistered else { return nil }
        let matching = readings.filter { $0.result == result }
        guard matching.count >= requiredReadings,
              Double(matching.count) / Double(readings.count) >= 0.8,
              let first = matching.first, time - first.time >= 1.5 else { return nil }
        lastRegistered = result
        startLatched = false
        armed = false
        absentSince = nil
        readings.removeAll()
        return result
    }
}
