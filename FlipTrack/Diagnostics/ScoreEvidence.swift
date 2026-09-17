import Foundation

struct FrameReading: Encodable, Sendable {
    let id: UUID
    let capturedAt: TimeInterval
    let processingMS: Double?
    let text: [DisplayText]
    let visibleBall: Int?
    let live: LiveScoreboard?
    let final: DisplayResult?
    let features: [FeatureReading]
    let imageAvailable: Bool
    init(_ observation: DisplayObservation, at time: TimeInterval) {
        id = observation.frameID
        capturedAt = time
        processingMS = observation.processingMS
        text = observation.text
        visibleBall = observation.visibleBall
        live = observation.live
        final = observation.final
        features = observation.features
        imageAvailable = observation.jpeg != nil
    }
}

/// Only the short confirmation window is retained in memory. Save the agreeing
/// source images, including partial pairs, when their readings become durable.
struct ScoreEvidence {
    private let finalHistoryLimit: Int
    init(finalHistoryLimit: Int = 10) { self.finalHistoryLimit = max(4, min(20, finalHistoryLimit)) }
    private var frames: [(time: TimeInterval, observation: DisplayObservation)] = []
    mutating func clear() { frames.removeAll() }
    mutating func append(_ observation: DisplayObservation, at time: TimeInterval) {
        if let last = frames.last, time <= last.time || time - last.time > 2 { clear() }
        frames.append((time, observation))
        frames.removeAll { time - $0.time > 5 }
        if frames.count > 20 { frames.removeFirst(frames.count - 20) }
    }

    struct Acceptance: Encodable {
        let before: SessionSnapshot
        let after: SessionSnapshot
        let final: DisplayResult?
        let proposedProgress: GameProgress?
        let supportingFrames: [UUID]
        let missingImages: [UUID]
    }

    func accepted(before: SessionSnapshot, after: SessionSnapshot, final: DisplayResult? = nil, proposedProgress: GameProgress? = nil) -> (Acceptance, [TelemetryWriter.Image]) {
        let acceptedProgress = proposedProgress ?? after.progress
        let now = frames.last?.time ?? 0
        let candidates = final == nil ? frames : Array(frames.suffix(finalHistoryLimit))
        let selected = candidates.filter { frame in
            if let final { return frame.observation.final == final }
            guard now - frame.time <= TurnDetector.confirmationWindow, let live = frame.observation.live, live.turn == acceptedProgress.turn else { return false }
            return (live.left != nil && live.left == acceptedProgress.left) ||
                (live.right != nil && live.right == acceptedProgress.right)
        }
        let eventID = UUID().uuidString
        let progress = final == nil ? "ball-\(acceptedProgress.turn?.ball ?? 0)-active-p\(acceptedProgress.turn?.slot ?? 0)" : "final"
        let prefix = String(format: "game-%03d", before.number) + "-\(progress)-\(eventID)"
        let images = selected.compactMap { frame -> TelemetryWriter.Image? in
            guard let data = frame.observation.jpeg else { return nil }
            return .init(name: "\(prefix)-\(frame.observation.frameID.uuidString).jpg", data: data)
        }
        return (Acceptance(before: before, after: after, final: final, proposedProgress: proposedProgress,
                           supportingFrames: selected.map { $0.observation.frameID },
                           missingImages: selected.filter { $0.observation.jpeg == nil }.map { $0.observation.frameID }), images)
    }
}
