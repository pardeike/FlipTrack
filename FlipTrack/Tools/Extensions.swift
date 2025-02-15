import UIKit

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
        for score in scores {
            session.games?.append(Game(nr: nr, scores: score, session: session))
            nr += 1
        }
        return session
    }
}
