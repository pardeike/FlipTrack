import Foundation

enum GameDisplayLayout {
    static func isBonusScreen(in observations: [DisplayText]) -> Bool {
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

