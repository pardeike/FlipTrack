import Foundation
import SwiftData
import Testing
@testable import FlipTrackCore

@Test func telemetryWritesOrderedJSONAndExactEvidence() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let writer = try TelemetryWriter(root: root)
    let jpeg = Data([0xff, 0xd8, 0xff, 0xd9])
    try writer.record("first", ["score": 42], images: [.init(name: "game-003-ball-2-unique.jpg", data: jpeg)])
    for index in 0..<50 { try writer.record("action", ["index": index]) }
    try await writer.flush()
    let lines = try String(contentsOf: writer.directory.appendingPathComponent("events.jsonl"), encoding: .utf8).split(separator: "\n")
    #expect(lines.count == 51)
    for (index, line) in lines.enumerated() {
        let item = try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        #expect(item["sequence"] as? Int == index + 1)
        #expect(item["schemaVersion"] as? Int == 1)
    }
    let first = try #require(JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any])
    #expect(first["images"] as? [String] == ["images/game-003-ball-2-unique.jpg"])
    #expect(try Data(contentsOf: writer.directory.appendingPathComponent("images/game-003-ball-2-unique.jpg")) == jpeg)
}

@Test func imageFailureIsExplicitAndDoesNotDropScoreEvent() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let writer = try TelemetryWriter(root: root)
    try writer.record("score", ["left": 100], images: [.init(name: "../escape.jpg", data: Data())])
    try await writer.flush()
    let line = try Data(contentsOf: writer.directory.appendingPathComponent("events.jsonl"))
    let item = try #require(JSONSerialization.jsonObject(with: line) as? [String: Any])
    #expect(item["event"] as? String == "score")
    #expect(item["images"] as? [String] == [])
    #expect((item["imageErrors"] as? [String])?.count == 1)
    #expect(!FileManager.default.fileExists(atPath: writer.directory.appendingPathComponent("escape.jpg").path))
}

@Test @MainActor func evidenceSelectsOnlySupportingFramesAndClearsAtCorrectionBoundary() throws {
    let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    let session = Session(date: .now)
    container.mainContext.insert(session)
    try session.prepareCurrentGame(in: container.mainContext)
    let before = SessionSnapshot(session)
    var evidence = ScoreEvidence()
    var first = DisplayObservation([])
    first.live = LiveScoreboard(turn: .init(slot: 2, ball: 2), left: 100, right: nil)
    first.jpeg = Data([1])
    evidence.append(first, at: 1)
    var second = DisplayObservation([])
    second.live = LiveScoreboard(turn: .init(slot: 2, ball: 2), left: nil, right: 200)
    second.jpeg = Data([2])
    evidence.append(second, at: 1.5)
    var wrong = DisplayObservation([])
    wrong.live = LiveScoreboard(turn: .init(slot: 1, ball: 1), left: 100, right: 200)
    wrong.jpeg = Data([3])
    evidence.append(wrong, at: 2)
    try session.updateProgress(GameProgress(turn: .init(slot: 2, ball: 2), left: 100, right: 200, observedStart: true), for: session.currentGameID, in: container.mainContext)
    let accepted = evidence.accepted(before: before, after: SessionSnapshot(session))
    #expect(accepted.0.supportingFrames == [first.frameID, second.frameID])
    #expect(accepted.1.count == 2)
    #expect(accepted.1.allSatisfy { $0.name.hasPrefix("game-001-ball-2-active-p2-") })
    evidence.clear()
    #expect(evidence.accepted(before: before, after: SessionSnapshot(session)).1.isEmpty)
}

@Test @MainActor func manualGameAndCorrectionsChangeScannerAuthorityWithoutRewritingCapturedScores() throws {
    let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    let context = container.mainContext
    let session = Session(date: .now)
    context.insert(session)
    try session.prepareCurrentGame(in: context)
    let initial = SessionSnapshot(session)
    try session.record(DisplayResult(left: 100, right: 200), for: session.currentGameID, in: context)
    #expect(SessionSnapshot(session).id != initial.id)
    #expect(session.awaitingNextStart)
    let recorded = SessionSnapshot(session)
    let game = try #require(session.games?.first)
    game.scores = [900, 800]
    session.startingPlayerOverride = 1
    session.currentGameNumberOverride = 7
    try context.save()
    #expect(SessionSnapshot(session) != recorded)
    #expect(session.lastCapturedScores == [100, 200])
    let stored = try #require(ModelContext(container).fetch(FetchDescriptor<Session>()).first)
    #expect(stored.awaitingNextStart)
    try session.updateProgress(GameProgress(turn: .init(slot: 1, ball: 1), observedStart: true), for: session.currentGameID, in: context)
    #expect(!session.awaitingNextStart)
}
