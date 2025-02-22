import UIKit
import AVFoundation
import Vision
import CoreImage

class Scanner {
    
    static let store = ConfigStore()
    static let camera = Camera()
    static var callback: (([Int]) -> Void)? = nil
    
    static var previousScores: [Int] = []
    static var scanRepeatCount = 0
    static let scannerDelegate = ScannerDelegate()
    
    class ScannerDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        func captureOutput(_ output: AVCaptureOutput,
                           didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
            let filteredImage = store.config.filterImage ? rawImage.preprocessImage() : rawImage
            let requestHandler = VNImageRequestHandler(ciImage: filteredImage, options: [:])
            let textRequest = VNRecognizeTextRequest { request, error in
                if let observations = request.results as? [VNRecognizedTextObservation] {
                    processTextObservations(observations)
                }
            }
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = false
            try? requestHandler.perform([textRequest])
        }
    }
    
    static func startScanning(_ cb: @escaping ([Int]) -> Void) {
        callback = cb
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(scannerDelegate, queue: DispatchQueue(label: "videoQueue"))
        if camera.session.canAddOutput(videoOutput) {
            camera.session.addOutput(videoOutput)
        }
    }
    
    static func stopScanning() {
        camera.session.outputs.forEach { camera.session.removeOutput($0) }
    }
    
    static func scoreFromText(_ text: String) -> Int? {
        if let num = NumberFormatter.american.number(from: text) {
            let score = Int(truncating: num)
            if score % 10 == 0 && score >= 100 && score < 10_000_000_000 { return score }
        }
        return nil
    }
    
    static func processTextObservations(_ observations: [VNRecognizedTextObservation]) {
        var hasFreePlay = false
        var scores: [(score: Int, rect: CGRect)] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if text == "FREEPLAY" || text == "FREE PLAY" || text == "FREEPLAY." || text == "FREE PLAY." {
                hasFreePlay = true
            } else {
                if let score = scoreFromText(text) {
                    scores.append((score: score, rect: observation.boundingBox))
                } else if hasFreePlay && text.contains("0") {
                    print("# - [\(text)]")
                }
            }
        }
        guard hasFreePlay, scores.count == 2 else { return }
        
        let sortedScores = scores.sorted { $0.rect.midX < $1.rect.midX }
        let leftScore = sortedScores.first!.score
        let rightScore = sortedScores.last!.score
        let currentScores = [leftScore, rightScore]
        if previousScores != currentScores {
            print("# New scan \(leftScore), \(rightScore)")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            previousScores = currentScores
            scanRepeatCount = 1
        } else {
            scanRepeatCount += 1
            print("# Scan nr \(scanRepeatCount): \(leftScore), \(rightScore)")
            if scanRepeatCount >= store.config.requiredScanCount {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                callback?(currentScores)
            }
        }
    }
}
