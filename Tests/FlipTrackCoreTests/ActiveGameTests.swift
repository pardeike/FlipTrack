import Foundation
import SwiftData
import Testing
@testable import FlipTrackCore

@Test @MainActor func activeDisplayKeepsMachineScoresWhileNamesAndSavedScoresFollowTheirOrders() throws {
    let container = try ModelContainer(for: Session.self, Game.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly:true,cloudKitDatabase:.none))
    let context = container.mainContext
    let session = Session(date:.now)
    context.insert(session)
    try session.prepareCurrentGame(in:context)
    session.startingPlayerOverride = 1
    try session.updateProgress(GameProgress(turn:.init(slot:1,ball:2),left:67_060_330,right:24_838_210,observedStart:true),for:session.currentGameID,in:context)
    #expect(session.activeDisplay.leftName == "Fredrik")
    #expect(session.activeDisplay.rightName == "Andreas")
    #expect(session.activeDisplay.left == 67_060_330)
    #expect(session.activeDisplay.right == 24_838_210)
    #expect(session.activeDisplay.turn?.slot == 1)
    // Correcting assignment remaps names, never machine scores.
    session.startingPlayerOverride = 0
    #expect(session.activeDisplay.leftName == "Andreas")
    #expect(session.activeDisplay.left == 67_060_330)
    session.startingPlayerOverride = 1
    try session.record(.init(left:67_060_330,right:24_838_210),in:context)
    #expect(session.games?.first?.scores == [24_838_210,67_060_330])
    #expect(session.activeDisplay.leftName == "Andreas")
    #expect(session.activeDisplay.left == nil && session.activeDisplay.right == nil)
    #expect(session.activeDisplay.turn == nil)
}

@Test @MainActor func activeDisplayDoesNotInventScoresOrClaimUncertainTurns() throws {
    let container = try ModelContainer(for: Session.self, Game.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly:true,cloudKitDatabase:.none))
    let context = container.mainContext
    let session = Session(date:.now)
    context.insert(session)
    try session.prepareCurrentGame(in:context)
    #expect(session.activeDisplay.left == nil)
    try session.updateProgress(GameProgress(turn:.init(slot:2,ball:3),left:0,observedStart:true,needsResync:true),for:session.currentGameID,in:context)
    #expect(session.activeDisplay.left == 0 && session.activeDisplay.right == nil)
    #expect(session.activeDisplay.turn == nil)
    try session.updateProgress(GameProgress(turn:.init(slot:2,ball:3),left:100,right:200,observedStart:true,nextGameTurn:.init(slot:1,ball:1)),for:session.currentGameID,in:context)
    #expect(session.activeDisplay.missingFinals)
    #expect(session.activeDisplay.left == nil && session.activeDisplay.turn == nil)
    try session.stageCapture(.init(left:100,right:200),in:context)
    #expect(!session.activeDisplay.visible)
    session.pendingCaptureScores = []
    session.sessionFinished = true
    #expect(!session.activeDisplay.visible)
}
