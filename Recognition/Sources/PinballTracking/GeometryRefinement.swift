import Foundation

/// Pixel fitting/tracking supplies this evidence. This module deliberately does
/// not infer quality from the confidence of the classifier being calibrated.
public struct GeometryEvidence: Codable, Sendable {
    public var time: Double
    public var referenceID: String
    public var trustedStaticReference: Bool
    public var staticRegionsCovered: Int
    public var heldOutBefore: Double
    public var heldOutAfter: Double
    public var maxCornerShiftDots: Double
    /// Row-major 3x3 candidate mapping in the caller's documented coordinate system.
    public var homography: [Double]

    public init(time: Double, referenceID: String, trustedStaticReference: Bool,
                staticRegionsCovered: Int, heldOutBefore: Double, heldOutAfter: Double,
                maxCornerShiftDots: Double, homography: [Double]) {
        self.time = time; self.referenceID = referenceID
        self.trustedStaticReference = trustedStaticReference; self.staticRegionsCovered = staticRegionsCovered
        self.heldOutBefore = heldOutBefore; self.heldOutAfter = heldOutAfter
        self.maxCornerShiftDots = maxCornerShiftDots; self.homography = homography
    }
}

/// An acceptance policy for small refinements, not a homography estimator or
/// acquisition algorithm. Numerical defaults reproduce the exploratory wall
/// experiment; production thresholds require sequential live-video validation.
public struct GeometryRefinement: Codable, Sendable {
    public var minimumHeldOutCorrelation = 0.95
    public var minimumImprovement = 0.0001
    public var maximumCornerShiftDots = 3.0
    public private(set) var lastAccepted: GeometryEvidence?
    public private(set) var requiresAcquisition = false
    public init() {}

    public enum Decision: String, Codable, Sendable {
        case accepted, untrustedReference, insufficientCoverage, invalidFit, noImprovement, largeMovement, stale, acquisitionRequired
    }

    public mutating func evaluate(_ evidence: GeometryEvidence) -> Decision {
        guard !requiresAcquisition else { return .acquisitionRequired }
        guard evidence.time.isFinite, evidence.time >= 0,
              evidence.heldOutBefore.isFinite, evidence.heldOutAfter.isFinite,
              (-1...1).contains(evidence.heldOutBefore), (-1...1).contains(evidence.heldOutAfter),
              evidence.maxCornerShiftDots.isFinite, evidence.maxCornerShiftDots >= 0,
              evidence.homography.count == 9, evidence.homography.allSatisfy(\.isFinite) else { return .invalidFit }
        let h = evidence.homography
        let determinant = h[0] * (h[4] * h[8] - h[5] * h[7]) - h[1] * (h[3] * h[8] - h[5] * h[6]) + h[2] * (h[3] * h[7] - h[4] * h[6])
        guard abs(determinant) > 1e-9 else { return .invalidFit }
        if let lastAccepted, evidence.time <= lastAccepted.time { return .stale }
        guard evidence.trustedStaticReference, !evidence.referenceID.isEmpty else { return .untrustedReference }
        guard evidence.staticRegionsCovered >= 2 else { return .insufficientCoverage }
        guard evidence.maxCornerShiftDots <= maximumCornerShiftDots else { return .largeMovement }
        guard evidence.heldOutAfter >= minimumHeldOutCorrelation,
              evidence.heldOutAfter >= evidence.heldOutBefore + minimumImprovement else { return .noImprovement }
        lastAccepted = evidence
        return .accepted
    }

    /// Called by an independent tracking-loss decision, not by one bad template fit.
    public mutating func trackingLost() { requiresAcquisition = true }

    /// Full acquisition is a separate validated operation. Discard stale refinement.
    public mutating func acquisitionConfirmed() { lastAccepted = nil; requiresAcquisition = false }
}
