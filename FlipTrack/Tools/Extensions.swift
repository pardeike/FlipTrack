import UIKit
import AVFoundation
import SwiftUI

extension View {
    @ViewBuilder func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

extension UIImage {
    
    func croppedBy(_ ratio: CGFloat) -> UIImage? {
        let imageWidth = self.size.width
        let imageHeight = self.size.height
        
        let cropHeight = imageWidth / ratio
        
        let yOffset = (imageHeight - cropHeight) / 2.0
        let cropRect = CGRect(x: 0, y: yOffset, width: imageWidth, height: cropHeight)
        
        let scaleCropRect = CGRect(x: cropRect.origin.x * self.scale,
                                   y: cropRect.origin.y * self.scale,
                                   width: cropRect.size.width * self.scale,
                                   height: cropRect.size.height * self.scale)
        
        guard let cgImage = self.cgImage,
              let croppedCGImage = cgImage.cropping(to: scaleCropRect) else {
            return nil
        }
        
        return UIImage(cgImage: croppedCGImage, scale: self.scale, orientation: .up)
    }
    
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage ?? self
    }
}

extension UIDevice {
    static var isXcodePreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != nil
    }
    static var isSimulator: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil
    }
}

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
    static let color1b = color1.mix(with: .black, by: 0.3)
    static let color2 = Color(hue: 0.54, saturation: 1, brightness: 1)
    static let color2b = color2.mix(with: .black, by: 0.3)
    static let highlight = Color.yellow.mix(with: .black, by: 0.3)
    func asBackground() -> (AnyView) -> AnyView {
        { view in AnyView(view.background(self)) }
    }
}

extension NumberFormatter {
    static let american: NumberFormatter = ({
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    })()
}

extension CIImage {
    func preprocessImage() -> CIImage {
        // Step 1: Adjust contrast and saturation.
        let colorControls = CIFilter(name: "CIColorControls")!
        colorControls.setValue(self, forKey: kCIInputImageKey)
        // Increase contrast to help the digits pop out.
        colorControls.setValue(1.5, forKey: kCIInputContrastKey)
        // Reduce saturation to remove distracting color noise.
        colorControls.setValue(0.0, forKey: kCIInputSaturationKey)
        
        // Step 2: Apply a median filter to smooth out the dot noise.
        let medianFilter = CIFilter(name: "CIMedianFilter")!
        medianFilter.setValue(colorControls.outputImage, forKey: kCIInputImageKey)
        
        // Step 3: Sharpen the image to enhance the edges.
        let sharpenFilter = CIFilter(name: "CISharpenLuminance")!
        sharpenFilter.setValue(medianFilter.outputImage, forKey: kCIInputImageKey)
        sharpenFilter.setValue(0.5, forKey: kCIInputSharpnessKey)
        
        return sharpenFilter.outputImage!
    }
}
