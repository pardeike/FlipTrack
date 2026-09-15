import AVFoundation
import CoreImage
import Foundation
import PinballVision

struct BenchmarkSummary: Codable {
    var completed = false
    var error: String?
    var cameraLoad = false
    var cameraFrames = 0
    var cameraMaxGapMS = 0.0
    var decodedFrames = 0
    var analyzedFrames = 0
    var targetSeconds = 0.0
    var lastSourceTime = 0.0
    var wallSeconds = 0.0
    var processingP50MS = 0.0
    var processingP95MS = 0.0
    var processingMaxMS = 0.0
    var schedulingLagP95MS = 0.0
    var schedulingLagMaxMS = 0.0
    var thermalStates: [String] = []
    var outputDirectory = ""
    var samplingHz = 2
    var sourceSHA256 = ""
    var sourceBytes: Int64 = 0
    var systemVersion = ProcessInfo.processInfo.operatingSystemVersionString
    var display: String {
        "Frames: \(analyzedFrames) analyzed / \(cameraFrames) camera\n" +
        String(format: "Processing p50 / p95 / max: %.0f / %.0f / %.0f ms\n", processingP50MS, processingP95MS, processingMaxMS) +
        String(format: "Lag p95 / max: %.0f / %.0f ms\n", schedulingLagP95MS, schedulingLagMaxMS) +
        "Thermal: \(thermalStates.joined(separator: ", "))\n" +
        (error.map { "Error: \($0)\n" } ?? "") + outputDirectory
    }
}

enum BenchmarkError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

/// A single worker processes replay frames. The real camera delivers and discards
/// its frames concurrently, adding capture cost without running a second detector.
final class BenchmarkRunner: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var captured = 0
    private var lastCameraFrame = 0.0
    private var cameraMaxGap = 0.0
    private var cameraFailure: String?
    private let camera = AVCaptureSession()
    private let cameraQueue = DispatchQueue(label: "benchmark.camera")
    private var notifications: [NSObjectProtocol] = []

    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    private var frameCount: Int { lock.lock(); defer { lock.unlock() }; return captured }
    private var failure: String? { lock.lock(); defer { lock.unlock() }; return cameraFailure }
    private var cameraAge: Double { lock.lock(); defer { lock.unlock() }; return ProcessInfo.processInfo.systemUptime - lastCameraFrame }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        if lastCameraFrame > 0 { cameraMaxGap = max(cameraMaxGap, now - lastCameraFrame) }
        lastCameraFrame = now
        captured += 1
        lock.unlock()
    }

    func run(seconds: Double?, cameraLoad: Bool, progress: @escaping @Sendable (Double) -> Void) async -> BenchmarkSummary {
        var summary = BenchmarkSummary()
        summary.cameraLoad = cameraLoad
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let output = documents.appendingPathComponent("run-\(UUID().uuidString)")
        summary.outputDirectory = output.lastPathComponent
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            summary.error = "Run started but has not finished; app exit or interruption may prevent a final report"
            let initial = try JSONEncoder().encode(summary)
            try initial.write(to: output.appendingPathComponent("benchmark.json"), options: .atomic)
            try initial.write(to: documents.appendingPathComponent("latest-benchmark.json"), options: .atomic)
            summary.error = nil
            guard let source = Bundle.main.url(forResource: "source-original", withExtension: "mov"),
                  let references = Bundle.main.url(forResource: "References", withExtension: nil),
                  let provenance = Bundle.main.url(forResource: "provenance", withExtension: "json") else {
                throw BenchmarkError.message("Bundled recording or references missing")
            }
            struct Provenance: Decodable { struct Video: Decodable { let sha256: String; let bytes: Int64 }; let video: Video }
            let input = try JSONDecoder().decode(Provenance.self, from: Data(contentsOf: provenance))
            summary.sourceSHA256 = input.video.sha256
            summary.sourceBytes = input.video.bytes
            let actualBytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard actualBytes.map(Int64.init) == input.video.bytes else { throw BenchmarkError.message("Bundled video size mismatch") }
            try Data(contentsOf: provenance).write(to: output.appendingPathComponent("provenance.json"))
            let asset = AVURLAsset(url: source)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw BenchmarkError.message("No video track") }
            let duration = try await asset.load(.duration).seconds
            let transform = try await track.load(.preferredTransform)
            summary.targetSeconds = min(seconds ?? duration, duration)
            if cameraLoad {
                guard await AVCaptureDevice.requestAccess(for: .video) else { throw BenchmarkError.message("Camera permission denied") }
            }
            try replay(asset: asset, track: track, transform: transform, references: references, output: output, summary: &summary, progress: progress)
        } catch {
            summary.completed = false
            summary.error = error.localizedDescription
        }
        stopCamera()
        summary.cameraFrames = frameCount
        summary.cameraMaxGapMS = cameraMaxGap * 1000
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(summary).write(to: output.appendingPathComponent("benchmark.json"), options: .atomic)
            try encoder.encode(summary).write(to: documents.appendingPathComponent("latest-benchmark.json"), options: .atomic)
        } catch {
            summary.completed = false
            summary.error = "Could not save benchmark: \(error.localizedDescription)"
        }
        return summary
    }

    private func startCamera() throws {
        camera.beginConfiguration()
        defer { camera.commitConfiguration() }
        camera.sessionPreset = .hd1280x720
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw BenchmarkError.message("No back camera") }
        let input = try AVCaptureDeviceInput(device: device)
        guard camera.canAddInput(input) else { throw BenchmarkError.message("Camera input unavailable") }
        camera.addInput(input)
        try device.lockForConfiguration()
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 15 && $0.maxFrameRate >= 15 }) {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
        }
        device.unlockForConfiguration()
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: cameraQueue)
        guard camera.canAddOutput(output) else { throw BenchmarkError.message("Camera output unavailable") }
        camera.addOutput(output)
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: camera, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.lock.lock(); self.cameraFailure = "Physical camera interrupted"; self.lock.unlock()
            })
        }
    }

    private func stopCamera() {
        if camera.isRunning { camera.stopRunning() }
        cameraQueue.sync {} // Drain any final delegate callback before reading its counters.
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications = []
    }

    private func replay(asset: AVAsset, track: AVAssetTrack, transform: CGAffineTransform, references: URL, output: URL,
                        summary: inout BenchmarkSummary, progress: @escaping @Sendable (Double) -> Void) throws {
        if summary.cameraLoad {
            try startCamera()
            camera.startRunning()
            let deadline = ProcessInfo.processInfo.systemUptime + 10
            while frameCount == 0 && ProcessInfo.processInfo.systemUptime < deadline && !isCancelled { Thread.sleep(forTimeInterval: 0.05) }
            guard frameCount > 0 else { throw BenchmarkError.message("Camera delivered no frames") }
        }
        let detector = try NativeDetector(references: references, output: output)
        let timingURL = output.appendingPathComponent("timing.jsonl")
        FileManager.default.createFile(atPath: timingURL.path, contents: nil)
        let timing = try FileHandle(forWritingTo: timingURL)
        defer { try? timing.close() }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: summary.targetSeconds, preferredTimescale: 600))
        let video = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        video.alwaysCopiesSampleData = false
        guard reader.canAdd(video) else { throw BenchmarkError.message("Video decoder unavailable") }
        reader.add(video)
        guard reader.startReading() else { throw reader.error ?? BenchmarkError.message("Video decode failed") }
        defer { reader.cancelReading() }
        let clock = ProcessInfo.processInfo.systemUptime
        var next = 0.0
        var costs: [Double] = [], lags: [Double] = []
        var lastProgress = -1.0
        var replayError: Error?
        let orientation = CGAffineTransform(a: transform.a, b: -transform.b, c: -transform.c, d: transform.d, tx: 0, ty: 0)
        do {
            while let sample = video.copyNextSampleBuffer() {
                if isCancelled { throw BenchmarkError.message("Run cancelled or backgrounded") }
                if let failure { throw BenchmarkError.message(failure) }
                if summary.cameraLoad && cameraAge > 3 { throw BenchmarkError.message("Physical camera stalled for more than three seconds") }
                summary.decodedFrames += 1
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard time + 0.00001 >= next else { continue }
                next = time + 0.5
                let wait = clock + time - ProcessInfo.processInfo.systemUptime
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                if isCancelled { throw BenchmarkError.message("Run cancelled or backgrounded") }
                let start = ProcessInfo.processInfo.systemUptime
                lags.append(max(0, start - clock - time) * 1000)
                try autoreleasepool {
                    guard let pixels = CMSampleBufferGetImageBuffer(sample) else { throw BenchmarkError.message("Missing video pixels") }
                    var image = CIImage(cvPixelBuffer: pixels).transformed(by: orientation)
                    image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
                    image = image.transformed(by: CGAffineTransform(scaleX: 540 / image.extent.width, y: 960 / image.extent.height))
                    try detector.process(image, time: time)
                }
                costs.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                summary.analyzedFrames += 1
                summary.lastSourceTime = time
                let thermal = String(describing: ProcessInfo.processInfo.thermalState)
                if summary.thermalStates.last != thermal { summary.thermalStates.append(thermal) }
                let row: [String: Any] = ["sourceSeconds": time, "wallSeconds": ProcessInfo.processInfo.systemUptime - clock,
                    "processingMS": costs.last!, "lagMS": lags.last!, "cameraFrames": frameCount, "thermal": thermal]
                try timing.write(contentsOf: JSONSerialization.data(withJSONObject: row, options: .sortedKeys))
                try timing.write(contentsOf: Data([10]))
                if time - lastProgress >= 1 { progress(time / summary.targetSeconds); lastProgress = time }
            }
            guard reader.status == .completed else { throw reader.error ?? BenchmarkError.message("Replay ended before completion") }
            if let failure { throw BenchmarkError.message(failure) }
            summary.completed = !isCancelled
        } catch { replayError = error }
        summary.wallSeconds = ProcessInfo.processInfo.systemUptime - clock
        costs.sort(); lags.sort()
        func percentile(_ values: [Double], _ p: Double) -> Double {
            guard !values.isEmpty else { return 0 }
            return values[min(values.count - 1, Int((Double(values.count - 1) * p).rounded(.up)))]
        }
        summary.processingP50MS = percentile(costs, 0.5)
        summary.processingP95MS = percentile(costs, 0.95)
        summary.processingMaxMS = costs.last ?? 0
        summary.schedulingLagP95MS = percentile(lags, 0.95)
        summary.schedulingLagMaxMS = lags.last ?? 0
        try detector.finish(source: "bundled source-original.mov", start: 0, end: summary.completed ? summary.targetSeconds : summary.lastSourceTime,
                            wallSeconds: summary.wallSeconds, decoded: summary.decodedFrames)
        if let replayError { throw replayError }
    }
}
