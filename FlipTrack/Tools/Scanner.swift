import UIKit
import AVFoundation
import Vision
import CoreImage

class Scanner {
    
    static let store = ConfigStore()
    static let camera = Camera()
    static var callback: (([Int]) -> Void)? = nil
    
    static var previousScores: [Int] = []
    static var scanHistory: [[Int]] = []
    static var scanCounts: [String: Int] = [:]
    static let scannerDelegate = ScannerDelegate()
    
    class ScannerDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
        func captureOutput(_ output: AVCaptureOutput,
                           didOutput sampleBuffer: CMSampleBuffer,
                           from connection: AVCaptureConnection) {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let rawImage = CIImage(cvPixelBuffer: pixelBuffer)
            let filteredImage = store.config.filterImage
                ? rawImage.preprocessImage(strength: store.config.filterStrength)
                : rawImage
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
        scanHistory.removeAll()
        scanCounts.removeAll()
        previousScores.removeAll()
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
        let cleanText = text
            .replacing("O", with: "0")
            .replacing("S", with: "5")
            .replacing("l", with: "1")
            .replacing("B", with: "8")
        if let num = NumberFormatter.american.number(from: cleanText) {
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
            let text = candidate.string.uppercased()
            if try! /FREE ?PLAY\.?/.wholeMatch(in: text) != nil {
                // let start = candidate.string.firstIndex(of: "F")!
                // let end = candidate.string.lastIndex(of: "Y")!
                // let range = Range(uncheckedBounds: (start, end))
                // let pos = try! candidate.boundingBox(for: range)!
                // print("### \(text) @ \(pos.topLeft) \(pos.topRight) \(pos.bottomLeft) \(pos.bottomRight)")
                hasFreePlay = true
            } else {
                if let score = scoreFromText(text) {
                    scores.append((score: score, rect: observation.boundingBox))
                } else if hasFreePlay && text.contains("0") {
                    // print("# - [\(text)]")
                }
            }
        }
        guard hasFreePlay, scores.count == 2 else { return }
        
        let sortedScores = scores.sorted { $0.rect.midX < $1.rect.midX }
        let leftScore = sortedScores.first!.score
        let rightScore = sortedScores.last!.score
        let currentScores = [leftScore, rightScore]
        if previousScores != currentScores {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            previousScores = currentScores
        }

        scanHistory.append(currentScores)
        let key = "\(currentScores[0]),\(currentScores[1])"
        scanCounts[key, default: 0] += 1
        if scanHistory.count > store.config.historyLimit {
            let old = scanHistory.removeFirst()
            let oldKey = "\(old[0]),\(old[1])"
            if let c = scanCounts[oldKey], c > 1 { scanCounts[oldKey] = c - 1 } else { scanCounts.removeValue(forKey: oldKey) }
        }
        if scanCounts[key, default: 0] >= store.config.requiredScanCount {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            callback?(currentScores)
            scanHistory.removeAll()
            scanCounts.removeAll()
        }
    }
}
