import Foundation

/// Input is a confirmed semantic observation, not an unverified single-frame match.
/// The image recognizer supplies occurrence IDs after temporal grouping. Repeated
/// presentations of one occurrence share an ID; later occurrences get new IDs.
public struct TrackingObservation: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case turn, modeStart, gameResult, continuityLost, identityAnchor }
    public var id: String
    public var occurrenceID: String
    public var kind: Kind
    public var sourceTime: Double
    public var observedTime: Double
    public var slot: Int?
    public var ball: Int?
    public var newGame: Bool
    public var mode: String?
    public var scores: [String: Int64]?
    /// Only an explicit app/user identity anchor may supply these values.
    public var anchorGame: Int?
    public var anchorPlayerOne: String?

    public init(id: String, occurrenceID: String? = nil, kind: Kind, sourceTime: Double,
                observedTime: Double? = nil, slot: Int? = nil, ball: Int? = nil,
                newGame: Bool = false, mode: String? = nil, scores: [String: Int64]? = nil,
                anchorGame: Int? = nil, anchorPlayerOne: String? = nil) {
        self.id = id; self.occurrenceID = occurrenceID ?? id; self.kind = kind
        self.sourceTime = sourceTime; self.observedTime = observedTime ?? sourceTime
        self.slot = slot; self.ball = ball; self.newGame = newGame
        self.mode = mode; self.scores = scores
        self.anchorGame = anchorGame; self.anchorPlayerOne = anchorPlayerOne
    }
}

public struct TurnContext: Codable, Sendable, Equatable {
    public let id: String
    public let start: Double
    public let game: Int
    public let slot: Int
    public let ball: Int
    public let player: String
    public let playerOne: String
}

public struct TrackingEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case turnStarted, modeStarted, gameFinished, reviewRequired, identityRestored }
    public let id: String
    public let observationID: String
    public let kind: Kind
    public let sourceTime: Double
    public let observedTime: Double
    public let context: TurnContext?
    public let parameters: [String: String]
}

public enum TrackingError: Error { case invalidPlayers, invalidObservation, nonMonotonicDelivery }

/// Value-type state, owned serially by the session/capture actor. Codable snapshots
/// include deduplication and uncertainty history so replay/restart is deterministic.
/// It never reads annotation game/player labels to infer a transition.
public struct SessionTracker: Codable, Sendable {
    public private(set) var schemaVersion = 1
    public let firstPlayer: String
    public let secondPlayer: String
    public private(set) var turns: [TurnContext] = []
    public private(set) var needsIdentityAnchor = false
    private var seenObservations: Set<String> = []
    private var emittedOccurrences: Set<String> = []
    private var finishedGames: Set<Int> = []
    private var gameFinishTimes: [Int: Double] = [:]
    private var uncertainIntervals: [UncertainInterval] = []
    private var lastDeliveryTime = -1.0

    private struct UncertainInterval: Codable, Sendable {
        let start: Double
        var end: Double?
    }

    public init(firstPlayer: String, secondPlayer: String) throws(TrackingError) {
        guard !firstPlayer.isEmpty, !secondPlayer.isEmpty, firstPlayer != secondPlayer else {
            throw .invalidPlayers
        }
        self.firstPlayer = firstPlayer; self.secondPlayer = secondPlayer
    }

    public mutating func consume(_ input: TrackingObservation) throws(TrackingError) -> [TrackingEvent] {
        guard !input.id.isEmpty, !input.occurrenceID.isEmpty, input.sourceTime.isFinite,
              input.observedTime.isFinite, input.sourceTime >= 0,
              input.observedTime >= input.sourceTime else { throw .invalidObservation }
        if seenObservations.contains(input.id) { return [] }
        guard input.observedTime >= lastDeliveryTime else { throw .nonMonotonicDelivery }
        // Validate before changing durable state; malformed input can be corrected/retried.
        switch input.kind {
        case .turn, .identityAnchor:
            guard let slot = input.slot, (1...2).contains(slot),
                  let ball = input.ball, (1...3).contains(ball) else { throw .invalidObservation }
            if input.kind == .identityAnchor {
                guard let game = input.anchorGame, game > 0,
                      let player = input.anchorPlayerOne,
                      [firstPlayer, secondPlayer].contains(player) else { throw .invalidObservation }
            }
        case .modeStart:
            guard let mode = input.mode, !mode.isEmpty else { throw .invalidObservation }
        case .gameResult:
            guard let scores = input.scores, !scores.isEmpty,
                  scores.allSatisfy({ ["1", "2"].contains($0.key) && $0.value >= 0 }) else {
                throw .invalidObservation
            }
        case .continuityLost: break
        }
        seenObservations.insert(input.id); lastDeliveryTime = input.observedTime
        let key = input.kind.rawValue + ":" + input.occurrenceID
        if emittedOccurrences.contains(key) { return [] }

        switch input.kind {
        case .continuityLost:
            emittedOccurrences.insert(key)
            return loseContinuity(input, reason: "Unobserved interval may contain game boundaries")
        case .identityAnchor:
            guard input.sourceTime >= (turns.last?.start ?? 0),
                  input.sourceTime >= (uncertainIntervals.last?.start ?? 0),
                  let game = input.anchorGame, let playerOne = input.anchorPlayerOne else {
                return [event(input, .reviewRequired, nil, ["reason": "Identity anchor predates current state"])]
            }
            if needsIdentityAnchor, !uncertainIntervals.isEmpty {
                uncertainIntervals[uncertainIntervals.count - 1].end = input.sourceTime
            }
            needsIdentityAnchor = false
            let context = makeTurn(input, game: game, playerOne: playerOne)
            turns.append(context); emittedOccurrences.insert(key)
            return [event(input, .identityRestored, context, [:])]
        case .turn:
            guard !needsIdentityAnchor else { return [] }
            let previous = turns.last
            if let previous {
                guard input.sourceTime >= previous.start else {
                    return [event(input, .reviewRequired, nil, ["reason": "Late turn cannot rewrite established history"])]
                }
                if input.slot == previous.slot, input.ball == previous.ball,
                   !(input.newGame && finishedGames.contains(previous.game)) { return [] }
            }
            let isNewGame = previous != nil && input.newGame
            if let previous {
                let normal = previous.slot == 1
                    ? input.slot == 2 && input.ball == previous.ball
                    : previous.ball < 3 && input.slot == 1 && input.ball == previous.ball + 1
                let boundary = input.newGame && input.slot == 1 && input.ball == 1 &&
                    (previous.slot == 2 && previous.ball == 3 || finishedGames.contains(previous.game))
                guard boundary || (!input.newGame && normal && !finishedGames.contains(previous.game)) else {
                    return loseContinuity(input, reason: "Unexpected turn sequence; game/person parity is uncertain")
                }
            } else if input.slot != 1 || input.ball != 1 {
                return loseContinuity(input, reason: "Mid-game start requires an explicit identity anchor")
            }
            let playerOne = isNewGame ? other(previous?.playerOne ?? firstPlayer) : previous?.playerOne ?? firstPlayer
            let context = makeTurn(input, game: (previous?.game ?? 1) + (isNewGame ? 1 : 0), playerOne: playerOne)
            turns.append(context); emittedOccurrences.insert(key)
            return [event(input, .turnStarted, context,
                          ["newGame": String(previous == nil || isNewGame),
                           "personChanged": previous.map { String($0.player != context.player) } ?? "unknown"])]
        case .modeStart, .gameResult:
            guard let context = context(at: input.sourceTime) else {
                emittedOccurrences.insert(key)
                return [event(input, .reviewRequired, nil, ["reason": "No reliable originating turn", "kind": input.kind.rawValue])]
            }
            emittedOccurrences.insert(key)
            if input.kind == .modeStart {
                guard input.sourceTime < (gameFinishTimes[context.game] ?? .infinity) else {
                    return [event(input, .reviewRequired, context, ["reason": "Mode start after game result"])]
                }
                return [event(input, .modeStarted, context, ["mode": input.mode ?? ""])]
            }
            // Multiple GAME OVER/scoreboard presentations finish one game only once.
            guard !finishedGames.contains(context.game) else { return [] }
            finishedGames.insert(context.game)
            gameFinishTimes[context.game] = input.sourceTime
            var parameters: [String: String] = [:]
            for slot in [1, 2] {
                let person = slot == 1 ? context.playerOne : other(context.playerOne)
                parameters["player\(slot)"] = person
                parameters["score\(slot)"] = input.scores?[String(slot)].map(String.init) ?? "unknown"
            }
            if let a = input.scores?["1"], let b = input.scores?["2"] {
                parameters["winner"] = a == b ? "tie" : a > b ? context.playerOne : other(context.playerOne)
            } else { parameters["winner"] = "unknown" }
            return [event(input, .gameFinished, context, parameters)]
        }
    }

    public func context(at time: Double) -> TurnContext? {
        guard time.isFinite, !uncertainIntervals.contains(where: {
            time >= $0.start && time < ($0.end ?? .infinity)
        }) else { return nil }
        return turns.last { $0.start <= time }
    }

    private func other(_ player: String) -> String { player == firstPlayer ? secondPlayer : firstPlayer }
    private func makeTurn(_ input: TrackingObservation, game: Int, playerOne: String) -> TurnContext {
        TurnContext(id: input.occurrenceID, start: input.sourceTime, game: game,
                    slot: input.slot ?? 1, ball: input.ball ?? 1,
                    player: input.slot == 1 ? playerOne : other(playerOne), playerOne: playerOne)
    }
    private func event(_ input: TrackingObservation, _ kind: TrackingEvent.Kind, _ context: TurnContext?,
                       _ parameters: [String: String]) -> TrackingEvent {
        TrackingEvent(id: kind.rawValue + ":" + input.occurrenceID, observationID: input.id,
                      kind: kind, sourceTime: input.sourceTime, observedTime: input.observedTime,
                      context: context, parameters: parameters)
    }
    private mutating func loseContinuity(_ input: TrackingObservation, reason: String) -> [TrackingEvent] {
        guard !needsIdentityAnchor else { return [] }
        needsIdentityAnchor = true
        uncertainIntervals.append(UncertainInterval(start: input.sourceTime, end: nil))
        return [event(input, .reviewRequired, nil, ["reason": reason])]
    }
}
