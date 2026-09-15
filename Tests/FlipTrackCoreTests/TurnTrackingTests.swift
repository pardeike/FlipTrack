import Testing
import Foundation
import CoreImage
import SwiftData
@testable import FlipTrackCore

private func reading(_ slot: Int, _ ball: Int, left: Int? = 100, right: Int? = 200) -> LiveScoreboard {
    LiveScoreboard(turn: MachineTurn(slot: slot, ball: ball), left: left, right: right)
}

@Test func turnChangesNeedRepeatedLiveEvidenceAndDoNotAlternateBlindly() {
    var tracker = GameTracker()
    for tick in 0...2 { _ = tracker.observe(reading(1, 1), at: Double(tick)*0.5) }
    #expect(tracker.progress.turn == MachineTurn(slot: 1, ball: 1))
    #expect(tracker.progress.left == 100)
    for tick in 3...30 { _ = tracker.observe(nil, at: Double(tick)*0.5) }
    #expect(tracker.progress.turn?.slot == 1)
    for tick in 31...37 { _ = tracker.observe(reading(2, 1), at: Double(tick)*0.5) }
    #expect(tracker.progress.turn == MachineTurn(slot: 2, ball: 1))
    for tick in 38...44 { _ = tracker.observe(reading(2, 3), at: Double(tick)*0.5) }
    #expect(tracker.progress.needsResync)
    #expect(tracker.progress.turn == MachineTurn(slot: 2, ball: 1))
}

@Test func recoveryNeedsFreshStableOutgoingScoreAndCancelDoesNotAdvance() {
    let initial = GameProgress(turn: MachineTurn(slot: 1, ball: 2), left: 100, observedStart: true, needsResync: true)
    var tracker = GameTracker(progress: initial)
    tracker.beginRecovery(at: 20)
    for tick in 0...40 { _ = tracker.observe(reading(2, 2), at: Double(tick)*0.5) }
    #expect(tracker.progress == initial)
    for tick in 41...48 { _ = tracker.observe(reading(2, 2, left: nil), at: Double(tick)*0.5) }
    #expect(tracker.recovering)
    tracker.cancelRecovery(at: 25)
    #expect(tracker.progress == initial)
    #expect(!tracker.recovering)
    tracker.beginRecovery(at: 30)
    for tick in 61...70 { _ = tracker.observe(reading(2, 2, left: 450), at: Double(tick)*0.5) }
    #expect(!tracker.recovering)
    #expect(tracker.progress.turn == MachineTurn(slot: 2, ball: 2))
    #expect(tracker.progress.left == 450)
    #expect(!tracker.progress.needsResync)
}

@Test func terminalTurnDoesNotFinishOnExtraBallOrFileNextGameScoresAsFinals() {
    var tracker = GameTracker(progress: GameProgress(turn: MachineTurn(slot: 2, ball: 3), observedStart: true))
    tracker.beginRecovery(at: 0)
    for tick in 1...5 { _ = tracker.observe(reading(2, 3), at: Double(tick)*0.5) }
    #expect(!tracker.recovering)
    #expect(tracker.progress.nextGameTurn == nil)
    for tick in 10...20 { _ = tracker.observe(reading(1, 1, left: 0, right: 0), at: Double(tick)*0.5) }
    #expect(tracker.progress.nextGameTurn == MachineTurn(slot: 1, ball: 1))
    #expect(tracker.progress.turn == MachineTurn(slot: 2, ball: 3))
    #expect(tracker.progress.left == 100)
    #expect(tracker.progress.needsResync)
}

@Test func missingFramesAndInterruptedCandidatesCannotCreateATurn() {
    var tracker = GameTracker()
    for tick in 0...20 { _ = tracker.observe(tick % 3 == 0 ? reading(2, 2) : nil, at: Double(tick)*0.5) }
    #expect(tracker.progress.turn == nil)
    _ = tracker.observe(reading(2, 2), at: 20)
    _ = tracker.observe(reading(2, 2), at: 30)
    #expect(tracker.progress.turn == nil)
}

@Test @MainActor func progressPersistsWithoutAddingWinsAndStaleUpdatesAreRejected() throws {
    let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext, session = Session(date: .now)
    context.insert(session)
    try session.prepareCurrentGame(in: context)
    let id = try #require(session.currentGameID)
    let progress = GameProgress(turn: MachineTurn(slot: 2, ball: 2), left: 400, right: 500, observedStart: true)
    try session.updateProgress(progress, for: id, in: context)
    #expect(session.games?.isEmpty == true)
    #expect(session.playerWins == [0,0])
    #expect(try ModelContext(container).fetch(FetchDescriptor<Session>()).first?.progress == progress)
    try session.record(DisplayResult(left: 400, right: 500), for: id, in: context)
    #expect(throws: Session.RecordingError.self) { try session.updateProgress(progress, for: id, in: context) }
}

@Test @MainActor func tenWinsFinishOnlyAfterAnActuallyStartedTrailingGame() throws {
    for started in [false, true] {
        let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext, session = Session(date: .now)
        context.insert(session)
        for _ in 0..<9 {
            let result = session.firstPlayerIndex == 0 ? DisplayResult(left: 200, right: 100) : DisplayResult(left: 100, right: 200)
            try session.record(result, in: context)
        }
        let progress = GameProgress(turn: MachineTurn(slot: 2, ball: 3), observedStart: true,
                                    nextGameTurn: started ? MachineTurn(slot: 1, ball: 1) : nil)
        try session.updateProgress(progress, for: session.currentGameID, in: context)
        let result = session.firstPlayerIndex == 0 ? DisplayResult(left: 200, right: 100) : DisplayResult(left: 100, right: 200)
        try session.record(result, in: context)
        #expect(session.raceWinnerIndex == 0)
        #expect(session.sessionFinished == !started)
        if started {
            #expect(session.progress.observedStart)
            try session.record(DisplayResult(left: 300, right: 400), in: context)
            #expect(session.sessionFinished)
            #expect(session.raceWinnerIndex == 0)
            #expect(session.games?.count == 11)
        }
    }
}

@Test func liveLayoutCannotBecomeFinalAndConflictingActiveEvidenceIsRejected() {
    func label(_ value: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> DisplayText {
        DisplayText(text: value, confidence: 1, bounds: CGRect(x:x,y:y,width:w,height:h), isInsideDisplay: true)
    }
    let rows = [label("162,000",0.1,0.65,0.35,0.15), label("00",0.7,0.55,0.15,0.3),
                label("BALL 1",0.15,0.1,0.2,0.1), label("FREE PLAY",0.5,0.1,0.35,0.1)]
    #expect(LiveGameLayout.result(in: rows)?.turn == MachineTurn(slot: 2, ball: 1))
    #expect(LiveGameLayout.result(in: rows)?.left == 162000)
    #expect(LiveGameLayout.result(in: rows)?.right == 0)
    #expect(LiveGameLayout.result(in: rows, activeSlot: 1) == nil)
    #expect(EndGameLayout.result(in: rows) == nil)
    #expect(LiveGameLayout.result(in: Array(rows.dropLast())) == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPTRACK_LIVE_FIXTURES"] != nil))
func recordedLiveScoreboards() throws {
    struct Fixture: Decodable { let path: String; let slot: Int; let ball: Int; let allowUnknown: Bool?; let left: Int?; let right: Int? }
    let manifest = try #require(ProcessInfo.processInfo.environment["FLIPTRACK_LIVE_FIXTURES"])
    let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: manifest)))
    for fixture in fixtures {
        let original = try #require(CIImage(contentsOf: URL(fileURLWithPath: fixture.path)))
        for height in [1920.0, 1280.0] {
            let image = original.transformed(by: CGAffineTransform(scaleX: height/original.extent.height, y: height/original.extent.height))
            let observed = try DisplayReader.analyze(image)
            #expect(observed.live?.turn == MachineTurn(slot: fixture.slot, ball: fixture.ball) || (fixture.allowUnknown == true && observed.live == nil))
            if let left = fixture.left, let read = observed.live?.left { #expect(read == left) }
            if let right = fixture.right, let read = observed.live?.right { #expect(read == right) }
            #expect(EndGameLayout.result(in: observed.text) == nil)
        }
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPTRACK_TURN_SEQUENCE"] != nil))
func recordedPlayerSwitchAndResync() throws {
    struct Fixture: Decodable { let path: String }
    let manifest = try #require(ProcessInfo.processInfo.environment["FLIPTRACK_TURN_SEQUENCE"])
    let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: manifest)))
    for height in [1920.0,1280.0] {
        var automatic = GameTracker(progress: GameProgress(turn: MachineTurn(slot:1,ball:1), observedStart:true))
        var recovery = automatic
        recovery.beginRecovery(at: -1)
        for (index, fixture) in fixtures.enumerated() {
            let original = try #require(CIImage(contentsOf: URL(fileURLWithPath:fixture.path)))
            let image = original.transformed(by:CGAffineTransform(scaleX:height/original.extent.height,y:height/original.extent.height))
            let observed = try DisplayReader.analyze(image)
            #expect(observed.final == nil)
            if let live = observed.live {
                #expect(live.turn == MachineTurn(slot:2,ball:1))
                if let left = live.left { #expect(left == 5_539_000) }
            }
            _ = automatic.observe(observed.live, at:Double(index)*0.5)
            _ = recovery.observe(observed.live, at:Double(index)*0.5)
        }
        #expect(automatic.progress.turn == MachineTurn(slot:2,ball:1))
        #expect(recovery.progress.turn == MachineTurn(slot:2,ball:1))
        #expect(recovery.progress.left == 5_539_000)
        #expect(!recovery.recovering)
    }
}

@Test func cancellingFinalRecoveryDiscardsUncommittedNextGameEvidence() {
    let initial = GameProgress(turn:MachineTurn(slot:2,ball:3),left:100,right:200,observedStart:true)
    var tracker = GameTracker(progress:initial)
    tracker.beginRecovery(at:0)
    for tick in 1...8 { #expect(tracker.observe(reading(1,1,left:0,right:0),at:Double(tick)*0.5) == nil) }
    #expect(tracker.progress == initial)
    #expect(tracker.recoveryNextTurn == MachineTurn(slot:1,ball:1))
    tracker.cancelRecovery(at:5)
    #expect(tracker.progress == initial)
    #expect(tracker.recoveryNextTurn == nil)
}
