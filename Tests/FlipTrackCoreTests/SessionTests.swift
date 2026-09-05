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
