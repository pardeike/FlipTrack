import Foundation

enum PinballMode: String, Codable, CaseIterable, Sendable {
    case getTheIdol, streetsOfCairo, wellOfSouls, ravenBar, monkeyBrains, stealTheStones
    case mineCart, ropeBridge, castleGrunewald, tankChase, threeChallenges, chooseWisely

    var title: String {
        switch self {
        case .getTheIdol: "Get the Idol"
        case .streetsOfCairo: "Streets of Cairo"
        case .wellOfSouls: "Well of Souls"
        case .ravenBar: "Raven Bar"
        case .monkeyBrains: "Monkey Brains"
        case .stealTheStones: "Steal the Stones"
        case .mineCart: "Escape in the Mine Cart"
        case .ropeBridge: "Rope Bridge"
        case .castleGrunewald: "Castle Grunewald"
        case .tankChase: "Tank Chase"
        case .threeChallenges: "Three Challenges"
        case .chooseWisely: "Choose Wisely"
        }
    }
    var aliases: [String] {
        switch self {
        case .threeChallenges: [title, "The Three Challenges", "The 3 Challenges", "3 Challenges"]
        case .ropeBridge: [title, "Survive the Rope Bridge"]
        case .mineCart: [title, "Mine Cart"]
        // Observed W/N substitution in both camera runs of this title. This
        // alias still needs the complete instruction/result layout below.
        case .castleGrunewald: [title, "Castle Grunenald"]
        default: [title]
        }
    }
}

/// These are observed screen meanings, not changes to game/turn authority.
enum FeatureKind: String, Codable, Sendable {
    case modeStarted, modeScore, multiballStarted, multiballEnded
    case jackpotAward, jackpotValue, ballSaved, ballSaveActive, shootAgain
    case bonus, bonusTotal, modeBonusTotal, lockedBallCount, extraBallAward, extraBallLit
}

struct FeatureReading: Codable, Equatable, Sendable {
    let kind: FeatureKind
    var mode: PinballMode? = nil
    var variant: String? = nil
    var score: Int? = nil
    var count: Int? = nil
    var text: [String] = []
    var confidence: Float = 1

    /// Numeric fields deliberately do not define an occurrence.
    var key: String { [kind.rawValue, mode?.rawValue ?? "", variant ?? ""].joined(separator: "/") }
}

enum FeatureLayout {
    private static func normalized(_ value: String) -> String {
        value.uppercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }
    private static func compact(_ value: String) -> String { normalized(value).filter { $0.isLetter || $0.isNumber } }
    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    static func readings(in observations: [DisplayText]) -> [FeatureReading] {
        let words = observations.filter { $0.confidence >= 0.65 && $0.bounds.width > 0 && $0.bounds.height > 0 }
        guard !words.contains(where: { matches(normalized($0.text), #"^BALL\s*[123Z]$"#) }),
              !words.contains(where: { matches(normalized($0.text), #"^(?:GAME OVER|HIGH SCORES?|GRAND CHAMPION|BUY IN|PRESS START)$"#) }) else { return [] }
        let ordered = words.sorted { abs($0.bounds.midY - $1.bounds.midY) < min($0.bounds.height, $1.bounds.height)*0.4
            ? $0.bounds.minX < $1.bounds.minX : $0.bounds.midY > $1.bounds.midY }
        var result: [FeatureReading] = []

        // An anchor and supporting lines must belong to one compact display
        // panel. Full-frame cabinet text cannot act as remote corroboration.
        func neighbors(_ anchor: DisplayText) -> [DisplayText] {
            words.filter { word in
                let a = anchor.bounds, b = word.bounds
                return abs(b.midX-a.midX) < max(a.width, b.width)*0.65 &&
                    b.midY <= a.midY + a.height*0.25 && a.midY-b.midY < a.height*6 &&
                    b.height >= a.height*0.3 && b.height <= a.height*2.5
            }
        }
        func amount(_ group: [DisplayText], below anchor: DisplayText) -> Int? {
            let values = group.compactMap { word -> Int? in
                guard word.bounds.midY < anchor.bounds.midY - anchor.bounds.height*0.3 else { return nil }
                // Mixed OCR separators still require complete thousands groups.
                return EndGameLayout.score(from: word.text.replacingOccurrences(of: ".", with: ","))
            }
            return values.count == 1 ? values[0] : nil
        }
        func emit(_ kind: FeatureKind, anchor: DisplayText, mode: PinballMode? = nil,
                  variant: String? = nil, count: Int? = nil, needsSupport: Bool = false) {
            let group = neighbors(anchor)
            guard !needsSupport || group.count >= 2,
                  anchor.isInsideDisplay || group.count >= 2 else { return }
            let valueKinds: [FeatureKind] = [.modeScore, .jackpotAward, .jackpotValue, .bonus, .bonusTotal, .modeBonusTotal]
            let value = valueKinds.contains(kind) ? amount(group, below: anchor) : nil
            if kind == .jackpotAward {
                let qualifiers = group.map { normalized($0.text) }.joined(separator: " ")
                guard value != nil,
                      !matches(qualifiers, #"\b(?:SHOOT|LIT|LIGHT|LIGHTS|VALUE|FOR|COLLECT)\b"#) else { return }
            }
            result.append(FeatureReading(kind: kind, mode: mode, variant: variant,
                score: value, count: count,
                text: group.map(\.text), confidence: group.map(\.confidence).min() ?? anchor.confidence))
        }

        // Mode intros have a title AND instructions. A title/amount recap is
        // collected as a displayed score, never another mode-start occurrence.
        for index in ordered.indices {
            for length in 1...min(3, ordered.count-index) {
                let titleWords = Array(ordered[index..<(index+length)])
                let title = titleWords.map(\.text).joined(separator: " ")
                let candidates = PinballMode.allCases.filter { mode in
                    mode.aliases.contains { compact(title) == compact($0) }
                }
                guard candidates.count == 1, let mode = candidates.first else { continue }
                let bounds = titleWords.dropFirst().reduce(titleWords[0].bounds) { $0.union($1.bounds) }
                guard bounds.height <= titleWords[0].bounds.height*4,
                      titleWords.allSatisfy({ abs($0.bounds.midX-bounds.midX) <= bounds.width*0.55 }) else { continue }
                let anchor = DisplayText(text: title, confidence: titleWords.map(\.confidence).min() ?? 0,
                    bounds: bounds, isInsideDisplay: titleWords.allSatisfy(\.isInsideDisplay))
                let group = neighbors(anchor)
                let lower = group.filter { $0.bounds.midY < bounds.minY + titleWords.last!.bounds.height*0.25 }
                let instructions = lower.map { normalized($0.text) }.joined(separator: " ")
                let hasInstructions = matches(instructions, #"\b(?:SHOOT|HIT|GET|MAKE|COLLECT|COMPLETE|USE|VIDEO MODE|PATH OF ADVENTURE)\b"#) ||
                    (mode == .mineCart && instructions == "UIDEO MODE")
                if hasInstructions,
                   !matches(instructions, #"\b(?:TOTAL|PASSED|COMPLETED|AWARDED)\b"#) {
                    emit(.modeStarted, anchor: anchor, mode: mode, needsSupport: true)
                } else if amount(group, below: anchor) != nil || matches(instructions, #"\bTOTAL\b"#) {
                    emit(.modeScore, anchor: anchor, mode: mode, variant: "namedTotal", needsSupport: true)
                }
            }
        }
        for word in words {
            let text = normalized(word.text)
            if text == "TOTAL BONUS" { emit(.bonusTotal, anchor: word, needsSupport: true) }
            else if text == "TOTAL MODE BONUS" { emit(.modeBonusTotal, anchor: word, needsSupport: true) }
            else if text == "BONUS" || text == "BONUS VALUE" { emit(.bonus, anchor: word, variant: text == "BONUS" ? "tally" : "status", needsSupport: true) }
            else if matches(text, #"^(?:SUPER |DOUBLE |TRIPLE |LOOP |FRIENDS |ARK |STONES |GRAIL )?JACKPOT(?: VALUE)?$"#) {
                emit(text.hasSuffix(" VALUE") ? .jackpotValue : .jackpotAward,
                     anchor: word, variant: text.replacingOccurrences(of: " VALUE", with: ""), needsSupport: true)
            } else if matches(text, #"^(?:(?:2|3|6)[ -]?BALL )?MULTI[ -]?BALL(?: STARTED)?$"#) {
                let instructions = neighbors(word).map { normalized($0.text) }.joined(separator: " ")
                if !matches(instructions, #"\b(?:LOCK|LOCKS|LOCKED|LIT|READY|TO START)\b"#) {
                    emit(.multiballStarted, anchor: word, variant: "explicitAnnouncement",
                         count: text.first.flatMap { Int(String($0)) })
                }
            } else if matches(text, #"^MULTI[ -]?BALL (?:OVER|ENDED)$"#) { emit(.multiballEnded, anchor: word) }
            else if text == "BALL SAVED" { emit(.ballSaved, anchor: word) }
            else if text == "BALL SAVE" || text == "BALL SAVER" { emit(.ballSaveActive, anchor: word) }
            else if text == "SHOOT AGAIN" { emit(.shootAgain, anchor: word) }
            else if text == "EXTRA BALL AWARDED" { emit(.extraBallAward, anchor: word) }
            else if text == "EXTRA BALL LIT" || text == "EXTRA BALL IS LIT" { emit(.extraBallLit, anchor: word) }
            else if matches(text, #"^[0-6O] BALLS? LOCKED$"#) {
                emit(.lockedBallCount, anchor: word, count: text.first == "O" ? 0 : text.first.flatMap { Int(String($0)) })
            } else if matches(text, #"^[0-9]{1,2} TUNNELS PASSED$"#) {
                emit(.modeScore, anchor: word, mode: .mineCart, variant: "tunnelsPassed",
                     count: Int(text.prefix(while: \.isNumber)), needsSupport: true)
            }
        }
        // Overlapping title aliases must not multiply an observation.
        var seen = Set<String>()
        return result.filter { seen.insert($0.key).inserted }
    }
}
