import Testing
import Foundation
import CoreImage
@testable import FlipTrackCore

/// Opt-in, serial release measurements. Wall time is reported, never used as a
/// correctness assertion. Mac timings do not establish AP11 camera throughput.
@Test(.enabled(if: ProcessInfo.processInfo.environment["FLIPTRACK_PERFORMANCE_ROOT"] != nil))
func recognitionPerformanceProfile() throws {
    struct TextFrame: Decodable { let text: [DisplayText] }
    struct PixelFrame: Decodable { let path: String }
    struct Semantics: Codable, Equatable {
        let live: LiveScoreboard?
        let final: DisplayResult?
        let visibleBall: Int?
        let features: [FeatureReading]
        init(_ observation: DisplayObservation) {
            live = observation.live; final = observation.final
            visibleBall = observation.visibleBall; features = observation.features
        }
    }
    struct Profile: Codable {
        let textFrameCount: Int
        let textPassMS: [Double]
        let textFeatures: [[FeatureReading]]
        let pixelPassMS: [[Double]]
        let jpegPassMS: [[Double]]
        let pixels: [Semantics]
    }
    let environment = ProcessInfo.processInfo.environment
    let root = URL(fileURLWithPath: try #require(environment["FLIPTRACK_PERFORMANCE_ROOT"]))
    let name = environment["FLIPTRACK_PERFORMANCE_NAME"] ?? "profile"
    let text = try String(contentsOf: root.appendingPathComponent("text.jsonl"), encoding: .utf8)
        .split(separator: "\n").map { try JSONDecoder().decode(TextFrame.self, from: Data($0.utf8)).text }
    let inputs = try JSONDecoder().decode([PixelFrame].self, from: Data(contentsOf: root.appendingPathComponent("pixels.json")))
    let reference = text.map { FeatureLayout.readings(in: $0) }
    var textTimes: [Double] = []
    for _ in 0..<5 {
        let start = ProcessInfo.processInfo.systemUptime
        let actual = text.map { FeatureLayout.readings(in: $0) }
        textTimes.append((ProcessInfo.processInfo.systemUptime-start)*1000)
        #expect(actual == reference)
    }
    let context = CIContext()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    // Warm up Vision and Core Image outside the timed passes.
    if let first = inputs.first, let image = CIImage(contentsOf: URL(fileURLWithPath: first.path)) {
        _ = try DisplayReader.analyze(image)
        _ = context.jpegRepresentation(of: image, colorSpace: colorSpace)
    }
    var pixelTimes: [[Double]] = [], jpegTimes: [[Double]] = []
    var semantics: [Semantics] = []
    for pass in 0..<2 {
        var timings: [Double] = [], encodings: [Double] = [], results: [Semantics] = []
        for input in inputs {
            try autoreleasepool {
                let image = try #require(CIImage(contentsOf: URL(fileURLWithPath: input.path)))
                let start = ProcessInfo.processInfo.systemUptime
                let observation = try DisplayReader.analyze(image)
                timings.append((ProcessInfo.processInfo.systemUptime-start)*1000)
                let encodeStart = ProcessInfo.processInfo.systemUptime
                if observation.live != nil || observation.final != nil || !observation.features.isEmpty {
                    #expect(context.jpegRepresentation(of: image, colorSpace: colorSpace) != nil)
                }
                encodings.append((ProcessInfo.processInfo.systemUptime-encodeStart)*1000)
                results.append(Semantics(observation))
            }
        }
        if pass == 0 { semantics = results } else { #expect(results == semantics) }
        pixelTimes.append(timings); jpegTimes.append(encodings)
    }
    let profile = Profile(textFrameCount: text.count, textPassMS: textTimes, textFeatures: reference,
                          pixelPassMS: pixelTimes, jpegPassMS: jpegTimes, pixels: semantics)
    if let referencePath = environment["FLIPTRACK_PERFORMANCE_REFERENCE"] {
        let original = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: URL(fileURLWithPath: referencePath)))
        #expect(profile.textFeatures == original.textFeatures)
        #expect(profile.pixels == original.pixels)
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(profile).write(to: root.appendingPathComponent("\(name).json"))
    print("PERFORMANCE", name, "text passes ms", textTimes, "pixel totals ms", pixelTimes.map { $0.reduce(0,+) })
}
