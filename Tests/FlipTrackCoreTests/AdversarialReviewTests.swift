import Foundation
import SwiftData
import Testing
@testable import FlipTrackCore

@MainActor private func reviewSession() throws -> (Session, ModelContainer) {
    let container = try ModelContainer(for: Session.self, Game.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    let session = Session(date: .now)
    container.mainContext.insert(session)
    return (session, container)
}

@Test @MainActor func insertingMissingHistoricalWinRecomputesWhoReachedTenFirst() throws {
    let (session, container) = try reviewSession()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    let firstPlayerWins: Set<Int> = [1,2,4,5,6,7,8,9,19]
    for number in 1...20 where number != 3 {
        session.currentGameNumberOverride = number
        session.startingPlayerOverride = 0
        try session.record(DisplayResult(left: firstPlayerWins.contains(number) ? 200 : 100,
                                         right: firstPlayerWins.contains(number) ? 100 : 200), in: context)
    }
    #expect(session.raceWinnerIndex == 1)
    session.currentGameNumberOverride = 3
    session.startingPlayerOverride = 0
    try session.record(DisplayResult(left: 200, right: 100), in: context)
    #expect(session.playerWins == [10,10])
    // The missing win means person 0 reached ten in game 19, before person 1 in game 20.
    #expect(session.raceWinnerIndex == 0)
}

@Test @MainActor func undoAndResaveWinningGamePreservesAlreadyStartedContinuation() throws {
    let (session, container) = try reviewSession()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    for _ in 0..<9 {
        session.startingPlayerOverride = 0
        try session.record(DisplayResult(left: 200, right: 100), in: context)
    }
    session.startingPlayerOverride = 0
    try session.updateProgress(GameProgress(turn: .init(slot:2, ball:3), observedStart:true,
        needsResync:true, nextGameTurn:.init(slot:1, ball:1)), for:session.currentGameID, in:context)
    try session.record(DisplayResult(left:200, right:100), for:session.currentGameID, in:context)
    #expect(session.raceWinnerIndex == 0)
    #expect(!session.sessionFinished)
    let continuationID = session.currentGameID
    let continuation = GameProgress(turn:.init(slot:2,ball:1), left:7_000,right:500, observedStart:true)
    try session.updateProgress(continuation, for:continuationID, in:context)
    try session.undoLastGame(in:context)
    let reopenedID = session.currentGameID
    // The editable draft and the already-started game must both survive a reload.
    let reloadedContext = ModelContext(context.container)
    let reloaded = try #require(reloadedContext.fetch(FetchDescriptor<Session>()).first)
    try reloaded.record(DisplayResult(left:200,right:100), for:reopenedID,in:reloadedContext)
    #expect(!reloaded.sessionFinished)
    #expect(reloaded.currentGameID == continuationID)
    #expect(reloaded.progress == continuation)
    #expect(reloaded.upcomingGameNumber == 11)
}

@Test @MainActor func liveEvidenceDoesNotIncludeFramesOutsideTurnVoteWindow() throws {
    let (session, container) = try reviewSession()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    try session.prepareCurrentGame(in:context)
    let before = SessionSnapshot(session)
    var evidence = ScoreEvidence()
    var old = DisplayObservation([])
    old.live = .init(turn:.init(slot:2,ball:1),left:100,right:200)
    old.jpeg = Data([1])
    evidence.append(old,at:0)
    for time in [1.5,3.0,3.5,TurnDetector.confirmationWindow + 0.1] {
        var fresh = DisplayObservation([])
        fresh.live = old.live
        fresh.jpeg = Data([2])
        evidence.append(fresh,at:time)
    }
    try session.updateProgress(GameProgress(turn:.init(slot:2,ball:1),left:100,right:200,observedStart:true),for:session.currentGameID,in:context)
    let accepted = evidence.accepted(before:before,after:SessionSnapshot(session))
    #expect(!accepted.0.supportingFrames.contains(old.frameID))
}

private final class ReviewErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return storage }
}

@Test func removingActiveTelemetryFolderCannotSilentlyLoseLaterEvents() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let errors = ReviewErrors()
    let writer = try TelemetryWriter(root:root,onError: { errors.append($0) })
    try writer.record("before", ["score":100])
    try await writer.flush()
    try FileManager.default.removeItem(at:writer.directory)
    try writer.record("after", ["score":200])
    try await writer.flush()
    #expect(!errors.values.isEmpty)
}

@Test @MainActor func repeatedUndoDoesNotReplaceTheAlreadyStartedGame() throws {
    let (session, container) = try reviewSession()
    defer { withExtendedLifetime(container) {} }
    let context = container.mainContext
    for _ in 0..<3 { try session.record(.init(left:100,right:200),in:context) }
    let activeID = session.currentGameID
    let activeProgress = GameProgress(turn:.init(slot:1,ball:2),left:4_000,right:3_000,observedStart:true)
    try session.updateProgress(activeProgress,for:activeID,in:context)
    try session.undoLastGame(in:context)
    try session.discardPendingCapture(in:context)
    try session.undoLastGame(in:context)
    try session.record(.init(left:300,right:400),for:session.currentGameID,in:context)
    #expect(session.currentGameID == activeID)
    #expect(session.progress == activeProgress)
    #expect(session.upcomingGameNumber == 4)
}

@Test func replacingActiveTelemetryFileCannotSilentlyLoseLaterEvents() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let errors = ReviewErrors()
    let writer = try TelemetryWriter(root:root,onError: { errors.append($0) })
    try writer.record("before", ["score":100])
    try await writer.flush()
    try Data().write(to:writer.directory.appendingPathComponent("events.jsonl"),options:.atomic)
    try writer.record("after", ["score":200])
    try await writer.flush()
    #expect(!errors.values.isEmpty)
}

@Test @MainActor func finalEvidenceUsesOnlyTheConfiguredReadingHistory() throws {
    let (session, container) = try reviewSession()
    defer { withExtendedLifetime(container) {} }
    try session.prepareCurrentGame(in:container.mainContext)
    let before = SessionSnapshot(session)
    var evidence = ScoreEvidence(finalHistoryLimit:4)
    var old = DisplayObservation([])
    old.final = .init(left:100,right:200)
    old.jpeg = Data([1])
    evidence.append(old,at:0)
    for time in [0.5,1.0,1.5,2.0] {
        var fresh = DisplayObservation([])
        fresh.final = old.final
        fresh.jpeg = Data([2])
        evidence.append(fresh,at:time)
    }
    let accepted = evidence.accepted(before:before,after:before,final:old.final)
    #expect(accepted.0.supportingFrames.count == 4)
    #expect(!accepted.0.supportingFrames.contains(old.frameID))
}

@Test @MainActor func telemetryFlushDoesNotBlockControlsBehindSlowStorage() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let queue = DispatchQueue(label:"test.blocked-telemetry")
    let release = DispatchSemaphore(value:0)
    let started = ReviewErrors(), timedOut = ReviewErrors()
    queue.async { release.wait() }
    // Emergency release lets the pre-fix blocking implementation fail instead of hang.
    DispatchQueue.global().asyncAfter(deadline:.now()+3) {
        timedOut.append("storage timeout")
        release.signal()
    }
    let writer = try TelemetryWriter(root:root,queue:queue)
    try writer.record("queued",["score":100])
    let flush = Task { @MainActor in
        started.append("flush requested")
        try await writer.flush()
    }
    while started.values.isEmpty { await Task.yield() }
    let responsive = timedOut.values.isEmpty
    release.signal()
    try await flush.value
    #expect(responsive)
}

@Test func slowTelemetryQueueHasABoundAndReportsTheGapWhenItRecovers() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:root) }
    let queue = DispatchQueue(label:"test.backlogged-telemetry")
    let release = DispatchSemaphore(value:0)
    queue.async { release.wait() }
    let writer = try TelemetryWriter(root:root,queue:queue,maxPendingBytes:100)
    let payload = ["value":String(repeating:"x",count:60)]
    try writer.record("first",payload)
    #expect(throws: (any Error).self) { try writer.record("overflow",payload) }
    release.signal()
    try await writer.flush()
    try writer.record("recovered",["value":1])
    try await writer.flush()
    let lines = try String(contentsOf:writer.directory.appendingPathComponent("events.jsonl"),encoding:.utf8).split(separator:"\n")
    #expect(lines.count == 2)
    let last = try #require(JSONSerialization.jsonObject(with:Data(lines.last!.utf8)) as? [String:Any])
    #expect(last["droppedEventsBefore"] as? Int == 1)
}
