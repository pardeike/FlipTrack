import CoreImage
import Vision

/// Locate the display frame, correct perspective, then read the layout. No
/// position or size is tied to the original holder photo.
enum DisplayReader {
    static func read(_ input: CIImage) throws -> [DisplayText] {
        let image = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))
        let rectangles = VNDetectRectanglesRequest()
        rectangles.minimumAspectRatio = 0.15
        rectangles.maximumAspectRatio = 0.65
        rectangles.minimumSize = 0.04
        rectangles.minimumConfidence = 0.6
        rectangles.maximumObservations = 4
        rectangles.quadratureTolerance = 35
        try VNImageRequestHandler(ciImage: image).perform([rectangles])
        var matches: [[DisplayText]] = []
        var displayText: [DisplayText] = []
        for rectangle in rectangles.results ?? [] {
            guard let corrected = correctedDisplay(image, rectangle: rectangle) else { continue }
            let text = try recognize(corrected)
            if EndGameLayout.result(in: text) != nil { matches.append(text) }
            if EndGameLayout.hasDisplayText(in: text) { displayText = text }
        }
        if matches.count == 1 { return matches[0] }
        // Multiple matching displays are ambiguous; never pick one arbitrarily.
        if matches.count > 1 { return [] }
        let fullText = try recognize(image)
        if EndGameLayout.result(in: fullText) != nil { return fullText }
        // Glare can hide the frame. A partial FREE PLAY reading may locate a
        // crop, but only a complete, re-read layout can confirm a result.
        for anchor in fullText where anchor.text.uppercased()
            .range(of: #"^[FP]REE ?PLA"#, options: .regularExpression) != nil {
            let a = anchor.bounds
            let region = CGRect(x: a.midX - a.width * 2.4, y: a.minY - a.height,
                                width: a.width * 4.8, height: a.height * 13)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            let crop = CGRect(x: image.extent.minX + region.minX * image.extent.width,
                              y: image.extent.minY + region.minY * image.extent.height,
                              width: region.width * image.extent.width, height: region.height * image.extent.height)
            guard crop.width > 0, crop.height > 0 else { continue }
            let scale = max(1, 1800 / crop.width)
            let aligned = image.cropped(to: crop)
                .transformed(by: CGAffineTransform(rotationAngle: -anchor.rotation))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let text = try recognize(aligned)
            if EndGameLayout.result(in: text) != nil { return text }
        }
        return displayText.isEmpty ? fullText : displayText
    }

    private static func correctedDisplay(_ image: CIImage, rectangle: VNRectangleObservation) -> CIImage? {
        func point(_ p: CGPoint) -> CIVector {
            CIVector(x: image.extent.minX + p.x * image.extent.width,
                     y: image.extent.minY + p.y * image.extent.height)
        }
        let corrected = image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": point(rectangle.topLeft), "inputTopRight": point(rectangle.topRight),
            "inputBottomLeft": point(rectangle.bottomLeft), "inputBottomRight": point(rectangle.bottomRight)
        ])
        let ratio = corrected.extent.width / corrected.extent.height
        guard ratio >= 2, ratio <= 6 else { return nil }
        // Give Vision a consistent text size even when the screen occupies a
        // small part of a video frame. Upsampling cannot recover hidden digits.
        let scale = max(1, 1400 / corrected.extent.width)
        return corrected.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private static func recognize(_ input: CIImage) throws -> [DisplayText] {
        let image = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.008
        try VNImageRequestHandler(ciImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first else { return nil }
            let angle = atan2((observation.topRight.y - observation.topLeft.y) * image.extent.height,
                              (observation.topRight.x - observation.topLeft.x) * image.extent.width)
            return DisplayText(text: text.string, confidence: text.confidence, bounds: observation.boundingBox, rotation: angle)
        }
    }
}
