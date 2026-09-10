import Testing
import Foundation
import CoreImage
@testable import FlipTrackCore

private let pair = DisplayResult(left: 24_274_100, right: 37_531_870)
private let other = DisplayResult(left: 15_000_000, right: 42_000_000)

private func layout(_ transform: CGAffineTransform = .identity) -> [DisplayText] {
    [
        DisplayText(text: "24,274,100", confidence: 1, bounds: CGRect(x: 0.235, y: 0.544, width: 0.236, height: 0.044).applying(transform)),
        DisplayText(text: "37,531,870", confidence: 1, bounds: CGRect(x: 0.544, y: 0.541, width: 0.167, height: 0.035).applying(transform)),
        DisplayText(text: "FREE PLAY", confidence: 1, bounds: CGRect(x: 0.422, y: 0.478, width: 0.157, height: 0.020).applying(transform))
    ]
}

@Test func strictScoreParsing() {
    for (text, value) in [("24,274,100", 24_274_100), ("37.531.870", 37_531_870), ("1 234 000", 1_234_000), ("1O0", 100), ("0", 0)] {
        #expect(EndGameLayout.score(from: text) == value)
    }
    for text in ["100 BONUS", "BALL 1", "SCORE 1000", "12,34", "12.50", "-100", "1e3", "SSS", "123", "10,000,000,000"] {
        #expect(EndGameLayout.score(from: text) == nil, "Incorrectly accepted \(text)")
    }
}

@Test func layoutUsesRelativeGeometry() {
    for transform in [CGAffineTransform.identity,
                      CGAffineTransform(scaleX: 0.45, y: 0.6).translatedBy(x: 0.8, y: -0.2),
                      CGAffineTransform(a: 1.1, b: 0.07, c: 0.12, d: 0.8, tx: -0.15, ty: 0.12)] {
        #expect(EndGameLayout.result(in: layout(transform)) == pair)
    }
    #expect(EndGameLayout.result(in: Array(layout().prefix(2))) == nil)
    #expect(EndGameLayout.result(in: layout().map { DisplayText(text: $0.text, confidence: 0.2, bounds: $0.bounds) }) == nil)
    var wrong = layout()
    wrong[1] = DisplayText(text: "37,531,870", confidence: 1, bounds: CGRect(x: 0.6, y: 0.8, width: 0.15, height: 0.04))
    #expect(EndGameLayout.result(in: wrong) == nil)
    let extra = DisplayText(text: "10,000", confidence: 1, bounds: CGRect(x: 0.49, y: 0.54, width: 0.04, height: 0.03))
    #expect(EndGameLayout.result(in: layout() + [extra]) == nil)
}

@Test func confirmsOnceAndRequiresNewGame() {
    var detector = EndGameDetector()
    for tick in 0..<3 { #expect(detector.observe(pair, at: Double(tick) * 0.5, readable: true) == nil) }
    #expect(detector.observe(pair, at: 1.5, readable: true) == pair)
    for tick in 4...40 { #expect(detector.observe(pair, at: Double(tick) * 0.5, readable: true) == nil) }
    // Brief animations and glare do not unlock the detector.
    for tick in 41...50 { #expect(detector.observe(nil, at: Double(tick) * 0.5, readable: true) == nil) }
    #expect(detector.observe(other, at: 25.5, readable: true) == nil)
    #expect(!detector.armed)
    // A sustained readable non-result display unlocks the next result.
    for tick in 52...70 { _ = detector.observe(nil, at: Double(tick) * 0.5, readable: true) }
    #expect(detector.armed)
    for tick in 71...90 { #expect(detector.observe(pair, at: Double(tick) * 0.5, readable: true) == nil) }
    var emitted: [DisplayResult] = []
    for tick in 91...115 {
        if let value = detector.observe(other, at: Double(tick) * 0.5, readable: true) { emitted.append(value) }
    }
    #expect(emitted == [other])
}

@Test func missesNoiseAndStallsDoNotAccumulateConfirmation() {
    var detector = EndGameDetector()
    for tick in 0...20 {
        #expect(detector.observe(tick % 2 == 0 ? pair : nil, at: Double(tick) * 0.5, readable: true) == nil)
    }
    #expect(detector.observe(pair, at: 20, readable: true) == nil)
    #expect(detector.observe(pair, at: 30, readable: true) == nil)
    #expect(detector.observe(pair, at: 40, readable: true) == nil)
    #expect(detector.observe(pair, at: 40.5, readable: true) == nil)
}

@Test func restoredScoresAndUnreadableFramesCannotDuplicate() {
    var detector = EndGameDetector(lastScores: pair.scores)
    for tick in 0...30 { #expect(detector.observe(nil, at: Double(tick) * 0.5, readable: false) == nil) }
    #expect(!detector.armed)
    for tick in 31...50 { _ = detector.observe(nil, at: Double(tick) * 0.5, readable: true) }
    for tick in 51...80 { #expect(detector.observe(pair, at: Double(tick) * 0.5, readable: true) == nil) }
}

@Test func brokenSettingsCannotDisableConfirmation() {
    let detector = EndGameDetector(requiredReadings: -1, historyLimit: 0)
    #expect(detector.requiredReadings == 4)
    #expect(detector.historyLimit >= detector.requiredReadings)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPTRACK_REFERENCE_PHOTO"] != nil))
func referencePhoto() throws {
    guard let path = ProcessInfo.processInfo.environment["FLIPTRACK_REFERENCE_PHOTO"] else { return }
    let image = try #require(CIImage(contentsOf: URL(fileURLWithPath: path), options: [.applyOrientationProperty: true]))
    for height in [image.extent.height, 1920, 1280] {
        let scale = height / image.extent.height
        let resized = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let text = try DisplayReader.read(resized)
        #expect(EndGameLayout.result(in: text) == pair, "OCR failed at height \(height): \(text.map(\.text))")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPTRACK_PHOTO_FIXTURES"] != nil))
func handheldPhotos() throws {
    struct Fixture: Decodable { let path: String; let scores: [Int]? }
    let manifest = try #require(ProcessInfo.processInfo.environment["FLIPTRACK_PHOTO_FIXTURES"])
    let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: manifest)))
    for fixture in fixtures {
        let url = URL(fileURLWithPath: fixture.path)
        let image = try #require(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
        for height in [image.extent.height, 1920, 1280] {
            let scale = height / image.extent.height
            let resized = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let text = try DisplayReader.read(resized)
            #expect(!GameDisplayLayout.isNewGame(in: text))
            let actual = EndGameLayout.result(in: text)?.scores
            print("Photo \(url.lastPathComponent) height \(Int(height)): \(String(describing: actual))")
            #expect(actual == fixture.scores, "\(url.lastPathComponent) at \(height): \(text.map(\.text))")
            if height == 1920 || height == 1280 {
                let width = height * 9 / 16
                let crop = CGRect(x: resized.extent.midX - width / 2, y: resized.extent.minY, width: width, height: height)
                let videoText = try DisplayReader.read(resized.cropped(to: crop))
                #expect(EndGameLayout.result(in: videoText)?.scores == fixture.scores,
                        "Portrait video crop \(url.lastPathComponent) at \(height): \(videoText.map(\.text))")
            }
        }
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPTRACK_REFERENCE_PHOTO"] != nil))
func changedMountingAngles() throws {
    let path = try #require(ProcessInfo.processInfo.environment["FLIPTRACK_REFERENCE_PHOTO"])
    let original = try #require(CIImage(contentsOf: URL(fileURLWithPath: path), options: [.applyOrientationProperty: true]))
    let scale = 1920 / original.extent.height
    let image = original.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let transforms = [CGAffineTransform(rotationAngle: .pi / 15),
                      CGAffineTransform(rotationAngle: -.pi / 15),
                      CGAffineTransform(a: 0.8, b: 0.12, c: 0.15, d: 1, tx: 300, ty: 200)]
    for transform in transforms {
        let text = try DisplayReader.read(image.transformed(by: transform))
        #expect(EndGameLayout.result(in: text) == pair, "Changed mount \(transform): \(text.map(\.text))")
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPTRACK_START_PHOTOS"] != nil))
func startScreenPhotos() throws {
    let manifest = try #require(ProcessInfo.processInfo.environment["FLIPTRACK_START_PHOTOS"])
    let paths = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: manifest)))
    for path in paths {
        let image = try #require(CIImage(contentsOf: URL(fileURLWithPath: path), options: [.applyOrientationProperty: true]))
        for height in [image.extent.height, 1920, 1280] {
            let resized = image.transformed(by: CGAffineTransform(scaleX: height / image.extent.height, y: height / image.extent.height))
            let text = try DisplayReader.read(resized)
            print("Start screen \(URL(fileURLWithPath: path).lastPathComponent) at \(Int(height)): \(GameDisplayLayout.isNewGame(in: text))")
            #expect(GameDisplayLayout.isNewGame(in: text))
            #expect(EndGameLayout.result(in: text) == nil)
            if height == 1920 || height == 1280 {
                let width = height * 9 / 16
                let crop = CGRect(x: resized.extent.midX - width / 2, y: resized.extent.minY, width: width, height: height)
                let videoText = try DisplayReader.read(resized.cropped(to: crop))
                #expect(GameDisplayLayout.isNewGame(in: videoText), "Video crop \(path) at \(height): \(videoText.map(\.text))")
                #expect(EndGameLayout.result(in: videoText) == nil)
            }
        }
    }
}
