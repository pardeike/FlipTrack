import Testing
import Foundation
import CoreImage
@testable import FlipTrackCore

@Test func ballLabelRepairIsBoundedToLocatedScreensAndBallsOneThroughThree() {
    func word(_ text: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double, inside: Bool = true) -> DisplayText {
        DisplayText(text: text, confidence: 1, bounds: CGRect(x: x, y: y, width: w, height: h), isInsideDisplay: inside)
    }
    let scores = [word("361,330", 0.08, 0.52, 0.4, 0.3), word("4,298,550", 0.61, 0.65, 0.34, 0.15),
                  word("FREE PLAY", 0.5, 0.1, 0.3, 0.1)]
    #expect(LiveGameLayout.result(in: scores + [word("BALL Z", 0.15, 0.1, 0.25, 0.1)])?.turn == MachineTurn(slot: 1, ball: 2))
    #expect(LiveGameLayout.result(in: scores + [word("BALL Z", 0.15, 0.1, 0.25, 0.1, inside: false)]) == nil)
    for ball in ["0", "4", "12", "2 BONUS"] {
        #expect(LiveGameLayout.result(in: scores + [word("BALL " + ball, 0.15, 0.1, 0.25, 0.1)]) == nil)
    }
    // Two small/partially refreshed scores cannot identify an active player.
    let small = [word("361,330", 0.08, 0.65, 0.35, 0.16), word("4,298,550", 0.61, 0.67, 0.34, 0.12)]
    #expect(LiveGameLayout.result(in: small + [scores[2], word("BALL 2", 0.15, 0.1, 0.25, 0.1)]) == nil)
}

@Test func semicolonScoreRepairStillRequiresCompleteThousandsGroups() {
    #expect(EndGameLayout.score(from: "13,097;110") == 13_097_110)
    for text in ["13;97;110", "13;097;11", "13;097;110 BONUS", "1 3,097;110", "361,3304,298,550"] {
        #expect(EndGameLayout.score(from: text) == nil)
    }
}

/// Private pixels stay outside Git. The manifest records source timestamps and
/// expected visible turns; no generated OCR text is used as recognition input.
@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPTRACK_SWITCH_FIXTURES"] != nil))
func recordedSwitchesAndGameOver() throws {
    struct Sample: Decodable { let path: String; let time: Double; let slot: Int?; let ball: Int? }
    let path = try #require(ProcessInfo.processInfo.environment["FLIPTRACK_SWITCH_FIXTURES"])
    let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    #expect(samples.count == 210)
    var tracker = GameTracker()
    var finals = EndGameDetector()
    var turns: [MachineTurn] = []
    var times: [Double] = []
    var saved: [DisplayResult] = []
    for sample in samples {
        try autoreleasepool {
            let image = try #require(CIImage(contentsOf: URL(fileURLWithPath: sample.path)))
            let observation = try DisplayReader.analyze(image)
            if let live = observation.live {
                #expect(live.turn.slot == sample.slot && live.turn.ball == sample.ball, "Wrong turn at \(sample.time): \(live.turn)")
                #expect(observation.final == nil)
            }
            if let result = observation.final {
                #expect((82...96).contains(sample.time))
                #expect(result.scores == [13_097_110, 457_000])
            }
            if let progress = tracker.observe(observation.live, at: sample.time) {
                #expect(!progress.needsResync)
                if let turn = progress.turn, turns.last != turn { turns.append(turn); times.append(sample.time) }
            }
            let canFinish = tracker.progress.canAcceptFinal(recovering: false)
            if let result = finals.observe(canFinish ? observation.final : nil, at: sample.time,
                                            readable: EndGameLayout.hasDisplayText(in: observation.text)) {
                saved.append(result)
                tracker = GameTracker()
            }
        }
    }
    #expect(turns == [MachineTurn(slot: 2, ball: 2), MachineTurn(slot: 1, ball: 3),
                      MachineTurn(slot: 2, ball: 3), MachineTurn(slot: 1, ball: 1)])
    #expect(saved == [DisplayResult(left: 13_097_110, right: 457_000)])
    if times.count == 4 {
        #expect(times[0] <= 3 && times[1] <= 33 && times[2] <= 64 && times[3] <= 102)
    }
    print("Switch recording confirmed turns at", times)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPTRACK_CAMERA_FIXTURES"] != nil))
func capturedLiveCameraSwitches() throws {
    struct Capture: Decodable { let folder: String; let slot: Int; let ball: Int; let left: Int; let right: Int }
    let path = try #require(ProcessInfo.processInfo.environment["FLIPTRACK_CAMERA_FIXTURES"])
    let captures = try JSONDecoder().decode([Capture].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    for capture in captures {
        let expected = MachineTurn(slot: capture.slot, ball: capture.ball)
        let previous = expected.slot == 2 ? MachineTurn(slot: 1, ball: expected.ball) : MachineTurn(slot: 2, ball: expected.ball - 1)
        var tracker = GameTracker(progress: GameProgress(turn: previous, observedStart: true))
        var firstConfirmation: Double?
        for index in 0..<32 {
            try autoreleasepool {
                let path = URL(fileURLWithPath: capture.folder).appendingPathComponent("frame-\(index).jpg")
                let image = try #require(CIImage(contentsOf: path))
                let observation = try DisplayReader.analyze(image)
                #expect(observation.final == nil)
                if let turn = observation.live?.turn { #expect(turn == expected) }
                if let progress = tracker.observe(observation.live, at: Double(index) * 0.5) {
                    #expect(!progress.needsResync)
                    if progress.turn == expected && firstConfirmation == nil { firstConfirmation = Double(index) * 0.5 }
                }
            }
        }
        print("Camera capture", capture.slot, tracker.progress, String(describing: firstConfirmation))
        #expect(tracker.progress.turn == expected)
        #expect(tracker.progress.left == capture.left && tracker.progress.right == capture.right)
        #expect(try #require(firstConfirmation) <= 5)
    }
}
