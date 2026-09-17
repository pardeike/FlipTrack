import Testing
import Foundation
import SwiftData
@testable import FlipTrackCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPTRACK_COLLECTION_PROFILE"] != nil))
@MainActor func collectionPersistenceProfile() throws {
    struct Profile: Encodable { let records: Int; let bytes: Int; let updateMS: [Double] }
    let path = try #require(ProcessInfo.processInfo.environment["FLIPTRACK_COLLECTION_PROFILE"])
    let container = try ModelContainer(for: Session.self, Game.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let session = Session(date: .now)
    container.mainContext.insert(session)
    try session.prepareCurrentGame(in: container.mainContext)
    let snapshot = SessionSnapshot(session), owner = FeatureContext(snapshot)
    let recordingID = UUID()
    let records = (0..<1_000).map { index in
        CollectedFeature(id: UUID(), revision: 1, context: owner,
            reading: FeatureReading(kind: .modeScore, mode: .mineCart, score: 29_000_000,
                                    count: 19, text: ["19 TUNNELS PASSED", "29,000,000"]),
            sourceTime: Double(index), confirmedAt: Double(index)+1,
            firstSeen: .now, lastConfirmed: .now, recordingID: recordingID,
            confirmationRecordingID: recordingID, supportingFrames: [UUID(), UUID(), UUID()], missingImages: [])
    }
    session.collectedFeatureData = try JSONEncoder().encode(records)
    try container.mainContext.save()
    var last = try #require(records.last)
    var durations: [Double] = []
    for revision in 2...22 {
        last.revision = revision; last.reading.score = revision*1_000_000
        let start = ProcessInfo.processInfo.systemUptime
        try session.collect(last, for: snapshot, in: container.mainContext)
        let duration = (ProcessInfo.processInfo.systemUptime-start)*1000
        if revision > 2 { durations.append(duration) } // warm-up excluded
    }
    #expect(try session.collectedFeatures().count == records.count)
    #expect(try session.collectedFeatures().last == last)
    #expect(SessionSnapshot(session) == snapshot)
    let profile = Profile(records: records.count, bytes: session.collectedFeatureData?.count ?? 0, updateMS: durations)
    try JSONEncoder().encode(profile).write(to: URL(fileURLWithPath: path))
    print("COLLECTION PERFORMANCE", durations)
}
