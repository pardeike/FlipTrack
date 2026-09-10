import Testing
import Foundation
import SwiftData
@testable import FlipTrackCore

@Test @MainActor func scoresPersistInPlayerOrderAndAlternate() throws {
    let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let session = Session(date: .now)
    context.insert(session)
    try context.save()
    #expect(session.firstPlayer == "Fredrik")
    try session.record(DisplayResult(left: 100, right: 200), in: context)
    #expect(session.games?.count == 1)
    #expect(session.games?.first?.scores == [200, 100])
    #expect(session.firstPlayer == "Andreas")
    try session.record(DisplayResult(left: 300, right: 400), in: context)
    #expect(session.games?.count == 2)
    #expect(session.games?.first(where: { $0.nr == 2 })?.scores == [300, 400])
    #expect(session.firstPlayer == "Fredrik")
    #expect(session.playerTotals == [500, 500])
    let id = session.id
    let freshContext = ModelContext(container)
    let saved = try #require(freshContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })).first)
    #expect(saved.lastCapturedScores == [300, 400])
    #expect(saved.nextGameNumber == 3)
    #expect(saved.games?.count == 2)
    // Deleting a mistaken score entry must not change who starts next.
    let deleted = try #require(session.games?.first(where: { $0.nr == 2 }))
    context.delete(deleted)
    try context.save()
    #expect(session.firstPlayer == "Fredrik")
    #expect(session.upcomingGameNumber == 3)
}

@Test @MainActor func optionalRelationshipAndExistingNumbering() throws {
    let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let session = Session(date: .now)
    session.games = nil
    context.insert(session)
    try session.record(DisplayResult(left: 100, right: 200), in: context)
    #expect(session.games?.count == 1)
    session.games?.first?.nr = 8
    session.nextGameNumber = 1
    #expect(session.upcomingGameNumber == 9)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPTRACK_OLD_STORE"] != nil))
@MainActor func upgradesOriginalStoreWithoutLosingGames() throws {
    let path = try #require(ProcessInfo.processInfo.environment["FLIPTRACK_OLD_STORE"])
    let config = ModelConfiguration(url: URL(fileURLWithPath: path), cloudKitDatabase: .none)
    let container = try ModelContainer(for: Session.self, Game.self, configurations: config)
    let session = try #require(container.mainContext.fetch(FetchDescriptor<Session>()).first)
    #expect(session.games?.count == 1)
    #expect(session.games?.first?.scores == [100, 200])
    #expect(session.upcomingGameNumber == 9)
    #expect(session.lastCapturedScores.isEmpty)
    try session.record(DisplayResult(left: 300, right: 400), in: container.mainContext)
    #expect(session.games?.count == 2)
    #expect(session.games?.first(where: { $0.nr == 9 })?.scores == [400, 300])
}

@Test @MainActor func correctedOrderAndPendingCaptureSurviveRelaunch() throws {
    let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let session = Session(date: .now)
    context.insert(session)
    session.startingPlayerOverride = 0
    session.scanningRequested = true
    try session.prepareCurrentGame(in: context)
    let gameID = try #require(session.currentGameID)
    try session.stageCapture(DisplayResult(left: 120, right: 340), in: context)
    let sessionID = session.id
    let restoredContext = ModelContext(container)
    let restored = try #require(restoredContext.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.id == sessionID })).first)
    #expect(restored.currentGameID == gameID)
    #expect(restored.scanningRequested)
    #expect(restored.firstPlayerIndex == 0)
    #expect(restored.pendingCaptureScores == [120, 340])
    try restored.record(DisplayResult(left: 120, right: 340), for: gameID, in: restoredContext)
    #expect(restored.games?.first?.scores == [120, 340])
    #expect(restored.games?.first?.startingPlayerIndex == 0)
    #expect(restored.firstPlayerIndex == 1)
    #expect(restored.pendingCaptureScores.isEmpty)
    let nextID = restored.currentGameID
    try restored.record(DisplayResult(left: 120, right: 340), for: gameID, in: restoredContext)
    #expect(restored.games?.count == 1)
    #expect(restored.currentGameID == nextID)
    #expect(restored.upcomingGameNumber == 2)
}

@Test @MainActor func staleCaptureCannotOverwriteCurrentGameAndIdenticalLaterGameIsValid() throws {
    let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let session = Session(date: .now)
    context.insert(session)
    try session.prepareCurrentGame(in: context)
    #expect(throws: Session.RecordingError.self) {
        try session.record(DisplayResult(left: 100, right: 200), for: UUID(), in: context)
    }
    #expect(session.games?.isEmpty == true)
    let firstID = try #require(session.currentGameID)
    try session.record(DisplayResult(left: 100, right: 200), for: firstID, in: context)
    let secondID = try #require(session.currentGameID)
    #expect(secondID != firstID)
    try session.record(DisplayResult(left: 100, right: 200), for: secondID, in: context)
    #expect(session.games?.count == 2)
    #expect(session.upcomingGameNumber == 3)
}

@Test @MainActor func undoRestoresGameIdentityOrderAndScoresAsDurableDraft() throws {
    let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let session = Session(date: .now)
    context.insert(session)
    try session.record(DisplayResult(left: 100, right: 200), in: context)
    let previousScores = session.lastCapturedScores
    session.startingPlayerOverride = 1
    try session.prepareCurrentGame(in: context)
    let gameID = session.currentGameID
    try session.record(DisplayResult(left: 300, right: 400), for: gameID, in: context)
    try session.undoLastGame(in: context)
    #expect(session.games?.count == 1)
    #expect(session.upcomingGameNumber == 2)
    #expect(session.firstPlayerIndex == 1)
    #expect(session.currentGameID == gameID)
    #expect(session.pendingCaptureScores == [300, 400])
    #expect(session.lastCapturedScores == previousScores)
    #expect(session.rejectedCaptureSignatures.contains("300,400"))
    let fresh = ModelContext(container)
    let restored = try #require(fresh.fetch(FetchDescriptor<Session>()).first)
    #expect(restored.pendingCaptureScores == [300, 400])
    #expect(restored.rejectedCaptureSignatures.contains("300,400"))
    #expect(restored.firstPlayerIndex == 1)
    try restored.record(DisplayResult(left: 500, right: 600), for: gameID, in: fresh)
    #expect(restored.games?.count == 2)
    #expect(restored.games?.first(where: { $0.nr == 2 })?.scores == [600, 500])
    #expect(restored.upcomingGameNumber == 3)
}

@Test @MainActor func undoCannotDestroyAnUnreviewedCapture() throws {
    let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let session = Session(date: .now)
    context.insert(session)
    try session.record(DisplayResult(left: 100, right: 200), in: context)
    try session.stageCapture(DisplayResult(left: 300, right: 400), in: context)
    #expect(throws: Session.RecordingError.self) { try session.undoLastGame(in: context) }
    #expect(session.games?.count == 1)
    #expect(session.pendingCaptureScores == [300, 400])
}

@Test @MainActor func undoUsesLastSavedIdentityAfterHistoricalNumberCorrection() throws {
    let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = container.mainContext
    let session = Session(date: .now)
    context.insert(session)
    try session.record(DisplayResult(left: 100, right: 200), in: context)
    let older = try #require(session.lastRecordedGame)
    try session.record(DisplayResult(left: 300, right: 400), in: context)
    older.nr = 10
    try context.save()
    #expect(session.lastRecordedGame?.nr == 2)
    try session.undoLastGame(in: context)
    #expect(session.upcomingGameNumber == 2)
    #expect(session.games?.first?.nr == 10)
    try session.record(DisplayResult(left: 500, right: 600), for: session.currentGameID, in: context)
    #expect(session.lastRecordedGame?.nr == 2)
    #expect(session.upcomingGameNumber == 3)
}
