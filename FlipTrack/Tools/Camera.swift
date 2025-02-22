import AVFoundation
import SwiftUI

class Camera {
    let store = ConfigStore()
    let session: AVCaptureSession
    
    init() {
        session = AVCaptureSession()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) else { return }
        try! device.lockForConfiguration()
        device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.25)
        device.exposureMode = .continuousAutoExposure
        let clampedBias = max(min(store.config.fstopsDown, device.maxExposureTargetBias), device.minExposureTargetBias)
        device.setExposureTargetBias(clampedBias) { _ in }
        device.torchMode = .off
        device.activeColorSpace = .sRGB
        device.autoFocusRangeRestriction = .none
        device.focusMode = .continuousAutoFocus
        device.isSubjectAreaChangeMonitoringEnabled = true
        device.unlockForConfiguration()
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
        }
    }
}
