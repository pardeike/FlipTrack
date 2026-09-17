import Foundation

struct FeatureContext: Codable, Equatable, Sendable {
    let sessionID: UUID
    var gameID: UUID?
    var gameNumber: Int?
    var turn: MachineTurn?
    var playerIndex: Int?
    var uncertainty: String?

    init(_ snapshot: SessionSnapshot) {
        sessionID = snapshot.sessionID
        let observed = snapshot.progress.observedStart && !snapshot.awaitingNextStart &&
            !snapshot.finished && snapshot.progress.nextGameTurn == nil && snapshot.pending.isEmpty
        gameID = observed ? snapshot.id : nil
        gameNumber = observed ? snapshot.number : nil
        turn = observed && !snapshot.progress.needsResync ? snapshot.progress.turn : nil
        playerIndex = turn.map { $0.slot == 1 ? snapshot.starter : 1-snapshot.starter }
        uncertainty = turn == nil ? "unconfirmedTurn" : nil
    }

    func unassigned(_ reason: String) -> Self {
        var result = self
        result.turn = nil; result.playerIndex = nil; result.uncertainty = reason
        return result
    }
}

/// Revisions update an observed presentation; they are not additional awards.
/// Named scores may refer to an earlier start, but never fabricate a start.
struct CollectedFeature: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var revision: Int
    let context: FeatureContext
    var reading: FeatureReading
    let sourceTime: TimeInterval
    var confirmedAt: TimeInterval
    let firstSeen: Date
    var lastConfirmed: Date
    let recordingID: UUID
    var confirmationRecordingID: UUID
    var modeOccurrenceID: UUID?
    var supportingFrames: [UUID]
    var missingImages: [UUID]
    var evidenceRun: String?
}

struct FeatureConfirmation: Sendable {
    let event: CollectedFeature
    let images: [DisplayObservation]
}

/// Bounded per-frame state. Durable events seed presentation latches on resume;
/// a fresh scoreboard is required before trusting a restored player's identity.
struct FeatureCollector {
    private struct Sample {
        let time: TimeInterval
        let date: Date
        let observation: DisplayObservation
        let reading: FeatureReading
        let context: FeatureContext
    }
    private struct Latch {
        var event: CollectedFeature
        var absentReadableSeconds: Double = 0
    }
    private let recordingID: UUID
    private var records: [CollectedFeature]
    private var pending: [String: [Sample]] = [:]
    private var latches: [String: Latch] = [:]
    private var context: FeatureContext?
    private var lastTime: TimeInterval?
    private var turnProof = TurnDetector()
    private var freshTurn = false
    private var bonusContext: FeatureContext?

    init(previous: [CollectedFeature] = [], recordingID: UUID = UUID()) {
        records = previous
        self.recordingID = recordingID
    }

    mutating func invalidate() {
        pending = [:]; lastTime = nil; freshTurn = false; bonusContext = nil
        turnProof.reset()
    }

    mutating func observe(_ observation: DisplayObservation, at time: TimeInterval,
                          date: Date = .now, context current: FeatureContext) -> [FeatureConfirmation] {
        guard time.isFinite else { return [] }
        let delta = lastTime.map { time-$0 } ?? 0
        if lastTime != nil && (delta <= 0 || delta > 2) { invalidate() }
        lastTime = time
        if context != current {
            context = current; pending = [:]; latches = [:]; freshTurn = false; bonusContext = nil
            turnProof.reset()
            // At most the latest presentation per key can still be on screen.
            for event in records where event.context == current || event.context == current.unassigned("freshTurnRequired") {
                latches[event.reading.key] = Latch(event: event)
            }
        }
        if let live = turnProof.observe(observation.live, at: time, visibleBall: observation.visibleBall),
           live.turn == current.turn, current.playerIndex != nil {
            freshTurn = true; bonusContext = nil
        }
        let keys = Set(observation.features.map(\.key))
        let readable = observation.live != nil || observation.final != nil || !keys.isEmpty
        if readable && delta > 0 && delta <= 2 {
            for key in Array(latches.keys) {
                if keys.contains(key) { latches[key]?.absentReadableSeconds = 0 }
                else {
                    latches[key]?.absentReadableSeconds += delta
                    if (latches[key]?.absentReadableSeconds ?? 0) >= 2 {
                        latches.removeValue(forKey: key)
                        pending.removeValue(forKey: key)
                    }
                }
            }
        }
        if observation.features.contains(where: { ![.bonus, .bonusTotal, .modeBonusTotal, .modeScore].contains($0.kind) }) {
            bonusContext = nil
        }
        for key in Array(pending.keys) {
            pending[key]?.removeAll { time-$0.time > 4 }
            if pending[key]?.isEmpty == true { pending.removeValue(forKey: key) }
        }
        var confirmations: [FeatureConfirmation] = []
        for reading in observation.features {
            let outgoingBonus = [.bonus, .bonusTotal, .modeBonusTotal, .modeScore].contains(reading.kind)
            let owner = freshTurn ? current : outgoingBonus ? (bonusContext ?? current.unassigned("freshTurnRequired"))
                : current.unassigned("freshTurnRequired")
            let sample = Sample(time: time, date: date, observation: observation, reading: reading, context: owner)
            var samples = (pending[reading.key] ?? []).filter { $0.context == owner }
            guard !samples.contains(where: { $0.observation.frameID == observation.frameID }) else { continue }
            samples.append(sample)
            if samples.count > 12 { samples.removeFirst(samples.count-12) }
            pending[reading.key] = samples
            guard samples.count >= 2, let first = samples.first, time-first.time >= 0.35,
                  time-first.time <= 4 else { continue }
            // Dynamic numbers are stricter than identity: three actual agreeing
            // readings; missing values neither invent zero nor overwrite a value.
            let scoreSamples = reading.score.map { value in samples.filter { $0.reading.score == value } } ?? []
            let countSamples = reading.count.map { value in samples.filter { $0.reading.count == value } } ?? []
            var confirmed = reading
            confirmed.score = scoreSamples.count >= 3 ? reading.score : nil
            confirmed.count = countSamples.count >= 3 ? reading.count : nil
            var support = Array(samples.suffix(2))
            if confirmed.score != nil { support += scoreSamples.suffix(3) }
            if confirmed.count != nil { support += countSamples.suffix(3) }
            var ids = Set<UUID>()
            support = support.filter { ids.insert($0.observation.frameID).inserted }
            var event: CollectedFeature
            if let previous = latches[reading.key]?.event {
                // Do not relabel an already emitted event after an identity
                // correction. Its original uncertainty remains inspectable.
                guard previous.context == owner else { continue }
                let scoreChanged = confirmed.score != nil && confirmed.score != previous.reading.score
                let countChanged = confirmed.count != nil && confirmed.count != previous.reading.count
                guard scoreChanged || countChanged else { continue }
                event = previous
                if scoreChanged { event.reading.score = confirmed.score }
                if countChanged { event.reading.count = confirmed.count }
                event.reading.text = reading.text
                event.revision += 1
                event.confirmedAt = time; event.lastConfirmed = date
                event.confirmationRecordingID = recordingID
                event.supportingFrames = support.map { $0.observation.frameID }
                event.missingImages = support.filter { $0.observation.jpeg == nil }.map { $0.observation.frameID }
            } else {
                let modeStarts = records.filter { $0.context == owner && $0.reading.kind == .modeStarted && $0.reading.mode == reading.mode }
                event = CollectedFeature(id: UUID(), revision: 1, context: owner, reading: confirmed,
                    sourceTime: first.time, confirmedAt: time, firstSeen: first.date, lastConfirmed: date,
                    recordingID: recordingID, confirmationRecordingID: recordingID,
                    modeOccurrenceID: reading.kind == .modeScore && owner.gameID != nil && owner.turn != nil &&
                        modeStarts.count == 1 ? modeStarts[0].id : nil,
                    supportingFrames: support.map { $0.observation.frameID },
                    missingImages: support.filter { $0.observation.jpeg == nil }.map { $0.observation.frameID })
            }
            latches[reading.key] = Latch(event: event)
            if let index = records.firstIndex(where: { $0.id == event.id }) { records[index] = event }
            else { records.append(event) }
            confirmations.append(FeatureConfirmation(event: event, images: support.map(\.observation)))
            if reading.kind == .bonusTotal {
                bonusContext = owner; freshTurn = false; turnProof.reset()
            }
        }
        return confirmations
    }
}
