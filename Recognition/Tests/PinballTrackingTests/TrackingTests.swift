import Foundation
import Testing
@testable import PinballTracking

private func tracker() throws -> SessionTracker {
    try SessionTracker(firstPlayer: "person-a", secondPlayer: "person-b")
}
private func turn(_ id: String, _ time: Double, _ slot: Int, _ ball: Int, newGame: Bool = false) -> TrackingObservation {
    TrackingObservation(id: id, kind: .turn, sourceTime: time, slot: slot, ball: ball, newGame: newGame)
}

@Test func auditedBaselineInterpretationIsNotAnImageRecognitionBenchmark() throws {
    let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let data = try String(contentsOf: directory.appendingPathComponent("baseline-observations.jsonl"), encoding: .utf8)
    struct Expected: Decodable { let observationID: String; let game: Int; let slot: Int; let player: String; let kind: TrackingEvent.Kind }
    let expected = try JSONDecoder().decode([Expected].self, from: Data(contentsOf: directory.appendingPathComponent("baseline-expected.json")))
    var state = try tracker()
    var events: [TrackingEvent] = []
    for line in data.split(whereSeparator: \.isNewline) {
        let input = try JSONDecoder().decode(TrackingObservation.self, from: Data(line.utf8))
        events += try state.consume(input)
        #expect(try state.consume(input).isEmpty)
        // Process interruption/restart must preserve ownership and duplicate suppression.
        state = try JSONDecoder().decode(SessionTracker.self, from: JSONEncoder().encode(state))
    }
    #expect(events.count == expected.count)
    for (actual, wanted) in zip(events, expected) {
        #expect(actual.observationID == wanted.observationID)
        #expect(actual.kind == wanted.kind)
        #expect(actual.context?.game == wanted.game)
        #expect(actual.context?.slot == wanted.slot)
        #expect(actual.context?.player == wanted.player)
    }
    #expect(events.filter { $0.kind == .turnStarted }.count == 38)
    #expect(events.filter { $0.kind == .modeStarted }.count == 12)
    #expect(events.filter { $0.kind == .gameFinished }.count == 6)
    #expect(events.filter { $0.kind == .reviewRequired }.isEmpty)
    #expect(events.first { $0.context?.game == 2 && $0.kind == .gameFinished }?.parameters["score2"] == "unknown")
    #expect(events.first { $0.context?.game == 2 && $0.kind == .gameFinished }?.parameters["winner"] == "unknown")
}

@Test func samePersonContinuesAtNewGameAndRepeatedScoreboardsDoNotSwitch() throws {
    var state = try tracker()
    for (i, slot) in [1, 2, 1, 2, 1, 2].enumerated() {
        _ = try state.consume(turn("t\(i)", Double(i), slot, i / 2 + 1))
    }
    let prior = state.turns.last?.player
    let result = try state.consume(turn("next-game", 10, 1, 1, newGame: true))
    #expect(result.first?.context?.player == prior)
    #expect(result.first?.context?.game == 2)
    #expect(result.first?.parameters["personChanged"] == "false")
    #expect(try state.consume(turn("repeat-new-game", 11, 1, 1, newGame: true)).isEmpty)
    #expect(try state.consume(turn("save-or-extra-ball", 12, 1, 1)).isEmpty)
    #expect(state.turns.count == 7)
}

@Test func missingTransitionDoesNotInventPlayerParityAndExplicitAnchorRestoresIt() throws {
    var state = try tracker()
    _ = try state.consume(turn("first", 0, 1, 1))
    let missing = try state.consume(turn("skipped", 10, 2, 2))
    #expect(missing.first?.kind == .reviewRequired)
    #expect(state.needsIdentityAnchor)
    #expect(state.context(at: 15) == nil)
    #expect(state.context(at: 5)?.player == "person-a")
    _ = try state.consume(TrackingObservation(id: "restore", kind: .identityAnchor, sourceTime: 20,
                         slot: 2, ball: 2, anchorGame: 4, anchorPlayerOne: "person-b"))
    #expect(!state.needsIdentityAnchor)
    #expect(state.context(at: 20)?.player == "person-a")
    #expect(state.context(at: 15) == nil)
}

@Test func delayedModeUsesItsSourceTurnAndOccurrenceDedupAllowsLaterMode() throws {
    var state = try tracker()
    _ = try state.consume(turn("first", 0, 1, 1))
    _ = try state.consume(turn("second", 10, 2, 1))
    let input = TrackingObservation(id: "mode-confirmed", occurrenceID: "mode-1", kind: .modeStart,
                                   sourceTime: 9, observedTime: 11, mode: "Steal the Stones")
    let output = try state.consume(input)
    #expect(output.first?.context?.player == "person-a")
    #expect(output.first?.sourceTime == 9 && output.first?.observedTime == 11)
    var repeatInput = input; repeatInput.id = "mode-another-frame"; repeatInput.observedTime = 12
    #expect(try state.consume(repeatInput).isEmpty)
    repeatInput.id = "later-mode"; repeatInput.occurrenceID = "mode-2"
    repeatInput.sourceTime = 13; repeatInput.observedTime = 13
    #expect(try state.consume(repeatInput).first?.context?.player == "person-b")
}

@Test func continuityLossAndLateResultsKeepUncertaintyIntervals() throws {
    var state = try tracker()
    _ = try state.consume(turn("first", 0, 1, 1))
    _ = try state.consume(TrackingObservation(id: "gap", kind: .continuityLost, sourceTime: 5))
    let event = try state.consume(TrackingObservation(id: "unowned", kind: .modeStart,
                                 sourceTime: 6, mode: "Tank Chase"))
    #expect(event.first?.context == nil)
    #expect(event.first?.kind == .reviewRequired)
    let beforeGap = try state.consume(TrackingObservation(id: "old", kind: .modeStart,
                                     sourceTime: 4, observedTime: 7, mode: "Tank Chase"))
    #expect(beforeGap.first?.context?.player == "person-a")
}

@Test func invalidInputDoesNotPoisonStateAndDeliveryOrderIsExplicit() throws {
    var state = try tracker()
    #expect(throws: TrackingError.self) { try state.consume(turn("bad", 0, 7, 1)) }
    #expect(try state.consume(turn("bad", 0, 1, 1)).count == 1)
    #expect(throws: TrackingError.self) { try state.consume(turn("nan", .nan, 2, 1)) }
    _ = try state.consume(turn("second", 10, 2, 1))
    #expect(throws: TrackingError.self) { try state.consume(turn("out-of-order", 9, 1, 2)) }
    #expect(state.turns.count == 2)
}

@Test func unknownScoreIsNotZeroAndRepeatedFinalsDoNotDuplicateWins() throws {
    var state = try tracker()
    _ = try state.consume(turn("first", 0, 1, 1))
    let result = try state.consume(TrackingObservation(id: "score", kind: .gameResult,
                                  sourceTime: 10, scores: ["1": 100]))
    #expect(result.first?.parameters["score2"] == "unknown")
    #expect(result.first?.parameters["winner"] == "unknown")
    #expect(try state.consume(TrackingObservation(id: "recap", kind: .gameResult,
                            sourceTime: 11, scores: ["1": 100])).isEmpty)
    let delayed = try state.consume(TrackingObservation(id: "delayed-mode", kind: .modeStart,
                                   sourceTime: 9, observedTime: 12, mode: "Tank Chase"))
    #expect(delayed.first?.kind == .modeStarted)
}

@Test func geometryRefinementAcceptsEvidenceNotEveryMatchAndFreezesOnTrackingLoss() throws {
    var gate = GeometryRefinement()
    var evidence = GeometryEvidence(time: 1, referenceID: "lock-wall", trustedStaticReference: true,
                                   staticRegionsCovered: 2, heldOutBefore: 0.90, heldOutAfter: 0.98,
                                   maxCornerShiftDots: 1, homography: [1, 0, 1, 0, 1, 0, 0, 0, 1])
    #expect(gate.evaluate(evidence) == .accepted)
    evidence.time = 2; evidence.heldOutAfter = 0.89
    #expect(gate.evaluate(evidence) == .noImprovement)
    #expect(gate.lastAccepted?.time == 1)
    evidence.heldOutAfter = 0.98; evidence.trustedStaticReference = false
    #expect(gate.evaluate(evidence) == .untrustedReference)
    evidence.trustedStaticReference = true; evidence.staticRegionsCovered = 1
    #expect(gate.evaluate(evidence) == .insufficientCoverage)
    evidence.staticRegionsCovered = 2; evidence.maxCornerShiftDots = 10
    #expect(gate.evaluate(evidence) == .largeMovement)
    // A bad candidate alone doesn't invalidate a working calibration.
    #expect(!gate.requiresAcquisition)
    gate.trackingLost()
    evidence.maxCornerShiftDots = 1
    #expect(gate.evaluate(evidence) == .acquisitionRequired)
    gate = try JSONDecoder().decode(GeometryRefinement.self, from: JSONEncoder().encode(gate))
    #expect(gate.requiresAcquisition)
    gate.acquisitionConfirmed()
    #expect(gate.evaluate(evidence) == .accepted)
    #expect(gate.evaluate(evidence) == .stale)
    evidence.time = 3; evidence.homography = Array(repeating: 0, count: 9)
    #expect(gate.evaluate(evidence) == .invalidFit)
}

@Test func nativeGeometryGateReproducesTheRecordedWallExperiment() throws {
    struct Row: Decodable {
        let time: Double; let id: String; let accepted: Bool
        let heldOutBefore: Double; let heldOutAfter: Double
        let maxCornerShiftDisplayDots: Double
        let referenceToCurrentAffine: [[Double]]
    }
    struct Experiment: Decodable { let results: [Row] }
    let directory = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
    let experiment = try JSONDecoder().decode(Experiment.self, from: Data(contentsOf: directory.appendingPathComponent("lock-wall-results.json")))
    var gate = GeometryRefinement()
    var accepted = 0
    for row in experiment.results {
        let result = gate.evaluate(GeometryEvidence(time: row.time, referenceID: row.id,
            trustedStaticReference: true, staticRegionsCovered: 2,
            heldOutBefore: row.heldOutBefore, heldOutAfter: row.heldOutAfter,
            maxCornerShiftDots: row.maxCornerShiftDisplayDots,
            homography: row.referenceToCurrentAffine.flatMap { $0 } + [0, 0, 1]))
        #expect((result == .accepted) == row.accepted)
        if result == .accepted { accepted += 1 }
    }
    #expect(accepted == 3)
}

@Test func finishedGameCannotContinueWithoutNewGameEvidence() throws {
    var state = try tracker()
    _ = try state.consume(turn("first", 0, 1, 1))
    _ = try state.consume(TrackingObservation(id: "final", kind: .gameResult, sourceTime: 2, scores: ["1": 100]))
    #expect(try state.consume(turn("after-final", 3, 2, 1)).first?.kind == .reviewRequired)
    #expect(state.needsIdentityAnchor)
}
