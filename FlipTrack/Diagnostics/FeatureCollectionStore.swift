import Foundation
import SwiftData

struct FeatureCollectionCache {
    let data: Data
    let records: [CollectedFeature]
}

extension Session {
    @MainActor
    func collectedFeatures() throws -> [CollectedFeature] {
        guard let collectedFeatureData else { featureCollectionCache = nil; return [] }
        // Byte equality, not a revision/count heuristic: remote updates,
        // restores and rollbacks must invalidate an otherwise plausible cache.
        if let cached = featureCollectionCache, cached.data == collectedFeatureData { return cached.records }
        let records = try JSONDecoder().decode([CollectedFeature].self, from: collectedFeatureData)
        featureCollectionCache = FeatureCollectionCache(data: collectedFeatureData, records: records)
        return records
    }

    @MainActor
    func collect(_ event: CollectedFeature, for expected: SessionSnapshot, in context: ModelContext) throws {
        // A camera callback cannot append against an edited or completed game.
        // Collection writes themselves are not scanner-authority changes.
        guard SessionSnapshot(self) == expected, event.context.sessionID == id,
              event.context.gameID == nil || event.context.gameID == expected.id else {
            throw RecordingError.staleGame
        }
        var records = try collectedFeatures()
        if let index = records.firstIndex(where: { $0.id == event.id }) {
            guard event.revision > records[index].revision else { return }
            guard records[index].context == event.context,
                  records[index].reading.key == event.reading.key else { throw RecordingError.staleGame }
            records[index] = event
        } else { records.append(event) }
        let encoded = try JSONEncoder().encode(records)
        collectedFeatureData = encoded
        do {
            try context.save()
            featureCollectionCache = FeatureCollectionCache(data: encoded, records: records)
        } catch {
            context.rollback()
            featureCollectionCache = nil
            throw error
        }
    }
}
