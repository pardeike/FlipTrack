import SwiftUI
import CoreImage

extension Session {
    static func dummy(_ deltaDays: Int = 0, _ scores: [[Int]] = []) -> Session {
        let session = Session(date: Date.now.addingTimeInterval(-24 * 3600 * Double(deltaDays)))
        var nr = 1
        session.games = scores.map {
            let game = Game(nr: nr, scores: $0, session: session)
            nr += 1
            return game
        }
        return session
    }
}

extension Color {
    static let color1 = Color(hue: 0.07, saturation: 1, brightness: 1)
    static let color2 = Color(hue: 0.54, saturation: 1, brightness: 1)
}

extension CIImage {
    func preprocessImage(strength: Float = 0.5,
                         contrast: Float = 1.5,
                         sharpness: Float = 0.5) -> CIImage {
        let colorMatrix = CIFilter(name: "CIColorMatrix")!
        colorMatrix.setValue(self, forKey: kCIInputImageKey)
        colorMatrix.setValue(CIVector(x: 1 + CGFloat(strength), y: 0, z: 0, w: 0), forKey: "inputRVector")
        colorMatrix.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 1 - CGFloat(strength), w: 0), forKey: "inputBVector")

        let colorControls = CIFilter(name: "CIColorControls")!
        colorControls.setValue(colorMatrix.outputImage, forKey: kCIInputImageKey)
        colorControls.setValue(contrast, forKey: kCIInputContrastKey)
        colorControls.setValue(0.0, forKey: kCIInputSaturationKey)

        let medianFilter = CIFilter(name: "CIMedianFilter")!
        medianFilter.setValue(colorControls.outputImage, forKey: kCIInputImageKey)

        let sharpenFilter = CIFilter(name: "CISharpenLuminance")!
        sharpenFilter.setValue(medianFilter.outputImage, forKey: kCIInputImageKey)
        sharpenFilter.setValue(sharpness, forKey: kCIInputSharpnessKey)

        return sharpenFilter.outputImage!
    }
}
