import Foundation
import SwiftData

extension Session {
    func collectedFeatures() throws -> [CollectedFeature] {
        guard let collectedFeatureData else { return [] }
        return try JSONDecoder().decode([CollectedFeature].self, from: collectedFeatureData)
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
        collectedFeatureData = try JSONEncoder().encode(records)
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
}
