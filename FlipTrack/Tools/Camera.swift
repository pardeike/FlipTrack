import AVFoundation
import CoreImage
import Foundation

/// All capture configuration, OCR, and mutable state belong to `queue`.
/// Only the session reference is exposed, for AVFoundation's preview layer.
final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum Event: Sendable {
        case started
        case frame(DisplayObservation, TimeInterval)
        case failed(String)
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "net.pardeike.FlipTrack.camera", qos: .userInitiated)
    private let imageContext = CIContext()
    private var configuration = Configuration()
    private var onEvent: (@MainActor @Sendable (Event) -> Void)?
    private var lastFrame = -Double.infinity
    private var recognizesScores = true
    #if FLIPTRACK_DEVICE_TESTING
    private let fixture = CameraFixture()
    private var fixtureTimer: DispatchSourceTimer?
    func setFixtureRecovery(_ active: Bool) {
        queue.async { self.fixture.recoveryStarted = active ? ProcessInfo.processInfo.systemUptime : nil }
    }
    #endif

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVCaptureSession.wasInterruptedNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(runtimeError), name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func start(configuration: Configuration, recognizesScores: Bool = true, onEvent: @escaping @MainActor @Sendable (Event) -> Void) {
        queue.async {
            self.recognizesScores = recognizesScores
            self.configuration = configuration
            self.onEvent = onEvent
            self.lastFrame = -Double.infinity
            #if FLIPTRACK_DEVICE_TESTING && targetEnvironment(simulator)
            self.fixtureTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 0.5)
            timer.setEventHandler {
                let now = ProcessInfo.processInfo.systemUptime
                do { self.emit(.frame(try self.fixture.observation(at:now),now)) }
                catch { self.fail(error.localizedDescription) }
            }
            self.fixtureTimer = timer
            timer.resume()
            self.emit(.started)
            #else
            do {
                try self.configure()
                self.session.startRunning()
                guard self.session.isRunning else {
                    self.fail("The camera could not start. Try starting monitoring again.")
                    return
                }
                self.emit(.started)
            } catch {
                self.fail(error.localizedDescription)
            }
            #endif
        }
    }

    func stop() {
        queue.async {
            self.onEvent = nil
            #if FLIPTRACK_DEVICE_TESTING
            self.fixtureTimer?.cancel()
            self.fixtureTimer = nil
            #endif
            self.session.stopRunning()
        }
    }

    private func configure() throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw CameraError.message("Allow camera access in Settings to monitor the display.")
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let preset: AVCaptureSession.Preset = configuration.qualityMode ? .hd1920x1080 : .hd1280x720
        if session.canSetSessionPreset(preset) { session.sessionPreset = preset }
        if session.inputs.isEmpty {
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                throw CameraError.message("No rear camera is available.")
            }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CameraError.message("The rear camera is unavailable.") }
            session.addInput(input)
        }
        if let input = session.inputs.first as? AVCaptureDeviceInput {
            let device = input.device
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            let bias = configuration.fstopsDown.isFinite ? configuration.fstopsDown : -1
            device.setExposureTargetBias(min(max(bias, device.minExposureTargetBias), device.maxExposureTargetBias))
            // OCR consumes at most two frames per second. Avoid running the
            // sensor at full video rate while retaining a usable alignment preview.
            if device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
                $0.minFrameRate <= 15 && $0.maxFrameRate >= 15
            }) {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
            }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if device.hasTorch, device.isTorchModeSupported(.off) { device.torchMode = .off }
        }
        if session.outputs.isEmpty {
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else { throw CameraError.message("The camera cannot deliver video frames.") }
            session.addOutput(output)
        }
        // The app and the holder use portrait. Rotate the actual buffers so OCR
        // and the preview see the same upright image.
        if let connection = session.outputs.first?.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard onEvent != nil, recognizesScores else { return }
        #if FLIPTRACK_DEVICE_TESTING
        fixture.cameraFrames += 1
        #endif
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= 0.5, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        #if FLIPTRACK_DEVICE_TESTING
        do { emit(.frame(try fixture.observation(at:now),now)) }
        catch { fail("Test fixture: \(error.localizedDescription)") }
        return
        #else
        autoreleasepool {
            let frame = CIImage(cvPixelBuffer: buffer)
            let raw = configuration.useCenteredScanArea
                ? frame.cropped(to: DisplayReader.centeredScanRect(in: frame.extent)) : frame
            let image = configuration.filterImage ? raw.preprocessImage(
                strength: configuration.filterStrength, contrast: configuration.contrast,
                sharpness: configuration.sharpness) : raw
            do {
                var observation = try DisplayReader.analyze(image)
                observation.processingMS = (ProcessInfo.processInfo.systemUptime - now) * 1000
                if observation.live != nil || observation.final != nil {
                    observation.jpeg = imageContext.jpegRepresentation(of: image, colorSpace: CGColorSpaceCreateDeviceRGB())
                }
                emit(.frame(observation, now))
            } catch {
                fail("The display could not be read: \(error.localizedDescription)")
            }
        }
        #endif
    }

    private func emit(_ event: Event) {
        guard let callback = onEvent else { return }
        Task { @MainActor in callback(event) }
    }

    private func fail(_ message: String) {
        emit(.failed(message))
        onEvent = nil
        session.stopRunning()
    }

    @objc private func interrupted() {
        queue.async { self.fail("Camera interrupted. Start monitoring again when the camera is available.") }
    }

    @objc private func runtimeError() {
        queue.async { self.fail("Camera stopped unexpectedly. Try starting monitoring again.") }
    }

    private enum CameraError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
    }
}
