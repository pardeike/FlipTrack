import Testing
import Foundation
import SwiftData
import CoreImage
@testable import FlipTrackCore

private func panel(_ lines: [String], inside: Bool = true) -> [DisplayText] {
    lines.enumerated().map { index, text in
        DisplayText(text: text, confidence: 1,
                    bounds: CGRect(x: 0.12, y: 0.75-Double(index)*0.2, width: 0.76, height: 0.14),
                    isInsideDisplay: inside)
    }
}

@Test func featureScreenMeaningsStaySeparateFromAwardsAndStarts() {
    let start = FeatureLayout.readings(in: panel(["STEAL THE STONES", "GET LIT LIGHTS ON", "PATH OF ADVENTURE"]))
    #expect(start.first?.kind == .modeStarted && start.first?.mode == .stealTheStones)
    let recap = FeatureLayout.readings(in: panel(["STEAL THE STONES", "TOTAL", "12,345,000"]))
    #expect(recap.first?.kind == .modeScore && recap.first?.score == 12_345_000)
    #expect(!recap.contains { $0.kind == .modeStarted })
    let status = FeatureLayout.readings(in: panel(["LOOP JACKPOT VALUE", "5,000,000"]))
    #expect(status.first?.kind == .jackpotValue)
    #expect(FeatureLayout.readings(in: panel(["JACKPOT", "SHOOT THE RAMP", "5,000,000"])).isEmpty)
    #expect(FeatureLayout.readings(in: panel(["SUPER JACKPOT", "50,000,000"])).first?.kind == .jackpotAward)
    #expect(FeatureLayout.readings(in: panel(["TOTAL MODE BONUS", "00"])).first?.kind == .modeBonusTotal)
    #expect(FeatureLayout.readings(in: panel(["0 BALLS LOCKED", "IN IDOL"])).first?.kind == .lockedBallCount)
    #expect(FeatureLayout.readings(in: panel(["3 BALLS LOCKED", "IN IDOL"])).allSatisfy { $0.kind != .multiballStarted })
    #expect(FeatureLayout.readings(in: panel(["SHOOT FOR MULTIBALL"])).isEmpty)
    #expect(FeatureLayout.readings(in: panel(["MULTIBALL", "LOCK 3 BALLS TO START"])).isEmpty)
    #expect(FeatureLayout.readings(in: panel(["BALL SAVE"])).first?.kind == .ballSaveActive)
    #expect(FeatureLayout.readings(in: panel(["BALL SAVED"])).first?.kind == .ballSaved)
    #expect(FeatureLayout.readings(in: panel(["SHOOT AGAIN"])).first?.kind == .shootAgain)
    #expect(FeatureLayout.readings(in: panel(["EXTRA BALL LIT"])).first?.kind == .extraBallLit)
    #expect(FeatureLayout.readings(in: panel(["EXTRA BALL"])).isEmpty)
    #expect(FeatureLayout.readings(in: panel(["EXTRA BALL AWARDED"])).first?.kind == .extraBallAward)
    #expect(FeatureLayout.readings(in: panel(["6 BALL MULTIBALL"])).first?.count == 6)
    #expect(FeatureLayout.readings(in: panel(["MULTIBALL OVER"])).first?.kind == .multiballEnded)
    #expect(FeatureLayout.readings(in: panel(["BALL 2", "TOTAL BONUS", "100,000"])).isEmpty)
    #expect(FeatureLayout.readings(in: panel(["GAME OVER", "TANK CHASE", "1,000,000"])).isEmpty)
    #expect(FeatureLayout.readings(in: panel(["MULTIBALL"], inside: false)).isEmpty)
    let tunnels = FeatureLayout.readings(in: panel(["19 TUNNELS PASSED", "10 MILLION HALF WAY BONUS", "29,000,000"]))
    #expect(tunnels.first?.mode == .mineCart && tunnels.first?.score == 29_000_000 && tunnels.first?.count == 19)
}

@MainActor private func collectionSession() throws -> (ModelContainer, Session) {
    let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let session = Session(date: .now)
    container.mainContext.insert(session)
    session.startingPlayerOverride = 1
    try session.prepareCurrentGame(in: container.mainContext)
    try session.updateProgress(GameProgress(turn: .init(slot: 2, ball: 1), left: 100, right: 200, observedStart: true),
                               for: session.currentGameID, in: container.mainContext)
    return (container, session)
}

private func board() -> DisplayObservation {
    var result = DisplayObservation([])
    result.live = LiveScoreboard(turn: .init(slot: 2, ball: 1), left: 100, right: 200)
    return result
}

@Test @MainActor func featuresConfirmValuesSeparatelyAndPersistWithoutChangingGameAuthority() throws {
    let (container, session) = try collectionSession()
    let authority = SessionSnapshot(session), context = FeatureContext(authority)
    var collector = FeatureCollector()
    for time in [0.0, 0.5, 1.0] { #expect(collector.observe(board(), at: time, context: context).isEmpty) }
    let bonus = DisplayObservation(panel(["TOTAL BONUS", "5.104,000"]))
    #expect(collector.observe(DisplayObservation(bonus.text), at: 1.5, context: context).isEmpty)
    let first = try #require(collector.observe(DisplayObservation(bonus.text), at: 2, context: context).first)
    #expect(first.event.reading.score == nil)
    #expect(first.event.context.playerIndex == 0)
    try session.collect(first.event, for: authority, in: container.mainContext)
    let revision = try #require(collector.observe(DisplayObservation(bonus.text), at: 2.5, context: context).first)
    #expect(revision.event.id == first.event.id && revision.event.revision == 2)
    #expect(revision.event.reading.score == 5_104_000)
    try session.collect(revision.event, for: authority, in: container.mainContext)
    try session.collect(revision.event, for: authority, in: container.mainContext)
    #expect(try session.collectedFeatures().count == 1)
    #expect(SessionSnapshot(session) == authority)
    // A mode after the outgoing bonus is not assigned to that outgoing player.
    let mode = DisplayObservation(panel(["TANK CHASE", "SHOOT THE LOOPS"]))
    _ = collector.observe(DisplayObservation(mode.text), at: 3, context: context)
    let unowned = try #require(collector.observe(DisplayObservation(mode.text), at: 3.5, context: context).first)
    #expect(unowned.event.context.playerIndex == nil)
    #expect(unowned.event.context.uncertainty == "freshTurnRequired")
    // Editing the starter invalidates an already queued collection write.
    session.startingPlayerOverride = 0
    #expect(throws: Session.RecordingError.self) {
        try session.collect(unowned.event, for: authority, in: container.mainContext)
    }
    #expect(try session.collectedFeatures().count == 1)
}

@Test @MainActor func featureLatchesSurviveResumeAndUnknownFramesCannotRearmThem() throws {
    let (container, session) = try collectionSession()
    defer { withExtendedLifetime(container) {} }
    let context = FeatureContext(SessionSnapshot(session))
    var collector = FeatureCollector()
    let mode = DisplayObservation(panel(["TANK CHASE", "SHOOT THE LOOPS"]))
    _ = collector.observe(DisplayObservation(mode.text), at: 0, context: context)
    let first = try #require(collector.observe(DisplayObservation(mode.text), at: 0.5, context: context).first)
    #expect(first.event.context.playerIndex == nil)
    var resumed = FeatureCollector(previous: [first.event])
    _ = resumed.observe(DisplayObservation(mode.text), at: 10, context: context)
    #expect(resumed.observe(DisplayObservation(mode.text), at: 10.5, context: context).isEmpty)
    for time in [11.0, 12, 13, 14] { _ = resumed.observe(DisplayObservation([]), at: time, context: context) }
    _ = resumed.observe(DisplayObservation(mode.text), at: 14.5, context: context)
    #expect(resumed.observe(DisplayObservation(mode.text), at: 15, context: context).isEmpty)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPTRACK_FEATURE_FIXTURES"] != nil))
@MainActor func originalModeFeaturePixels() async throws {
    struct Sample: Decodable { let path: String; let time: Double; let mode: String?; let episode: Int }
    let path = try #require(ProcessInfo.processInfo.environment["FLIPTRACK_FEATURE_FIXTURES"])
    let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    var found = Set<Int>()
    var confirmed = Set<Int>()
    var collectors: [Int: FeatureCollector] = [:]
    let (container, session) = try collectionSession()
    defer { withExtendedLifetime(container) {} }
    let context = FeatureContext(SessionSnapshot(session))
    var results: [Int: Int] = [:]
    var data = Data()
    for sample in samples {
        let imageURL = URL(fileURLWithPath: sample.path)
        let observation = try await Task.detached {
            try autoreleasepool {
                let image = try #require(CIImage(contentsOf: imageURL))
                return try DisplayReader.analyze(image)
            }
        }.value
        try autoreleasepool {
            if let mode = sample.mode, observation.features.contains(where: { $0.kind == .modeStarted && $0.mode?.title.lowercased() == mode.lowercased() }) {
                found.insert(sample.episode)
            }
            let events = collectors[sample.episode, default: FeatureCollector()].observe(observation, at: sample.time, context: context)
            if events.contains(where: { $0.event.reading.kind == .modeStarted }) { confirmed.insert(sample.episode) }
            if let result = observation.features.first(where: { $0.kind == .modeScore }), let score = result.score {
                results[sample.episode] = score
            }
            print("FEATURE", sample.episode, sample.time, observation.features, observation.text.map(\.text))
            data.append(try JSONEncoder().encode(FrameReading(observation, at: sample.time))); data.append(10)
        }
    }
    try data.write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("readings.jsonl"))
    print("Recognized mode episodes", found.sorted())
    #expect(found.count == 12)
    #expect(confirmed.count == 12)
    #expect(results == [12: 5_000_000, 13: 15_000_000, 14: 5_000_000])
}

@Test @MainActor func featureVotesRequireDistinctFramesAndGapsDiscardPartialValues() throws {
    let (container, session) = try collectionSession()
    defer { withExtendedLifetime(container) {} }
    let context = FeatureContext(SessionSnapshot(session))
    var collector = FeatureCollector()
    let sameFrame = DisplayObservation(panel(["SUPER JACKPOT", "50,000,000"]))
    #expect(collector.observe(sameFrame, at: 0, context: context).isEmpty)
    #expect(collector.observe(sameFrame, at: 0.5, context: context).isEmpty)
    #expect(collector.observe(DisplayObservation(sameFrame.text), at: 4, context: context).isEmpty)
    let first = try #require(collector.observe(DisplayObservation(sameFrame.text), at: 4.5, context: context).first)
    #expect(first.event.reading.score == nil)
    let revision = try #require(collector.observe(DisplayObservation(sameFrame.text), at: 5, context: context).first)
    #expect(revision.event.id == first.event.id && revision.event.reading.score == 50_000_000)
    #expect(revision.event.supportingFrames.count == 3)
    #expect(revision.event.missingImages.count == 3)
    // Another presentation needs a recognized intervening screen, then fresh votes.
    for time in [5.5, 6, 6.5, 7, 7.5] { _ = collector.observe(board(), at: time, context: context) }
    #expect(collector.observe(DisplayObservation(sameFrame.text), at: 8, context: context).isEmpty)
    let next = try #require(collector.observe(DisplayObservation(sameFrame.text), at: 8.5, context: context).first)
    #expect(next.event.id != first.event.id && next.event.reading.score == nil)
    #expect(next.event.context.turn == MachineTurn(slot: 2, ball: 1))
}

@Test @MainActor func featureStorageRoundTripsAndRejectsCorruptCollection() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let configuration = ModelConfiguration(url: folder.appendingPathComponent("features.store"), cloudKitDatabase: .none)
    let container = try ModelContainer(for: Session.self, Game.self, configurations: configuration)
    let session = Session(date: .now)
    container.mainContext.insert(session)
    try session.prepareCurrentGame(in: container.mainContext)
    let authority = SessionSnapshot(session)
    var collector = FeatureCollector()
    let text = panel(["BALL SAVED"])
    _ = collector.observe(DisplayObservation(text), at: 0, context: FeatureContext(authority))
    let event = try #require(collector.observe(DisplayObservation(text), at: 0.5, context: FeatureContext(authority)).first?.event)
    try session.collect(event, for: authority, in: container.mainContext)
    let reloaded = try ModelContainer(for: Session.self, Game.self, configurations: configuration)
    let restored = try #require(reloaded.mainContext.fetch(FetchDescriptor<Session>()).first)
    #expect(try restored.collectedFeatures() == [event])
    // Same ID/revision/count can arrive with corrected bytes. Cache identity
    // must follow the persisted value, including after a rollback or clearing.
    var replacement = event
    replacement.reading.text = ["corrected source text"]
    restored.collectedFeatureData = try JSONEncoder().encode([replacement])
    #expect(try restored.collectedFeatures() == [replacement])
    reloaded.mainContext.rollback()
    #expect(try restored.collectedFeatures() == [event])
    restored.collectedFeatureData = nil
    #expect(try restored.collectedFeatures().isEmpty)
    restored.collectedFeatureData = Data("broken".utf8)
    #expect(throws: (any Error).self) { try restored.collectedFeatures() }
}
