import CoreImage
import Foundation

/// Compiled only into the separate device-test host. Actual capture callbacks
/// drive controlled observations, or recorded pixels through DisplayReader.
final class CameraFixture {
    private let scenario = ProcessInfo.processInfo.environment["FLIPTRACK_TEST_SCENARIO"] ?? "turn"
    var recoveryStarted: TimeInterval?
    var cameraFrames = 0
    private let imageContext = CIContext()
    private var sample = 0
    private var durations: [Double] = []
    private var thermals: [Int] = []

    func observation(at time: TimeInterval) throws -> DisplayObservation {
        if scenario == "recorded" {
            guard sample < 32 else { return DisplayObservation([]) }
            let url = Bundle.main.resourceURL!.appendingPathComponent("live-fixtures/switch-\(sample % 8).png")
            guard let image = CIImage(contentsOf:url) else { throw CocoaError(.fileReadCorruptFile) }
            let start = ProcessInfo.processInfo.systemUptime
            var observation = try DisplayReader.analyze(image)
            observation.jpeg = imageContext.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB())
            observation.processingMS = (ProcessInfo.processInfo.systemUptime-start)*1000
            durations.append((ProcessInfo.processInfo.systemUptime-start)*1000)
            thermals.append(ProcessInfo.processInfo.thermalState.rawValue)
            sample += 1
            if sample == 32 {
                let sorted = durations.sorted()
                let report: [String:Any] = ["samples":sample,"cameraFrames":cameraFrames,
                    "p50MS":sorted[sorted.count/2],"p95MS":sorted[Int(Double(sorted.count-1)*0.95)],
                    "maxMS":sorted.last!,"thermalStates":Array(Set(thermals)).sorted(),"durationsMS":durations]
                try JSONSerialization.data(withJSONObject:report, options:[.prettyPrinted,.sortedKeys])
                    .write(to:URL.documentsDirectory.appendingPathComponent("reader-performance.json"),options:.atomic)
            }
            return observation
        }
        guard let started = recoveryStarted, time-started > (scenario.hasPrefix("final") ? 5 : 2) else { return DisplayObservation([]) }
        func label(_ text:String,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,_ height:CGFloat) -> DisplayText {
            DisplayText(text:text,confidence:1,bounds:CGRect(x:x,y:y,width:width,height:height),isInsideDisplay:true)
        }
        if scenario == "finalPixels" || scenario == "corrections" {
            let url = Bundle.main.resourceURL!.appendingPathComponent("live-fixtures/final-1.png")
            guard let image = CIImage(contentsOf:url) else { throw CocoaError(.fileReadCorruptFile) }
            var observation = try DisplayReader.analyze(image)
            observation.jpeg = imageContext.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB())
            return observation
        }
        if scenario == "final" {
            return DisplayObservation([label("24,274,100",0.05,0.6,0.35,0.2),label("37,531,870",0.6,0.6,0.35,0.2),label("FREE PLAY",0.4,0.1,0.25,0.1)])
        }
        return DisplayObservation([label("1,234,000",0.05,0.65,0.35,0.15),label("2,345,000",0.5,0.5,0.45,0.3),
                                   label("BALL 2",0.1,0.1,0.2,0.1),label("FREE PLAY",0.5,0.1,0.3,0.1)])
    }
}
