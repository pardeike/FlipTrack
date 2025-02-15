import AVFoundation
import SwiftUI

class Camera {
    
    let session: AVCaptureSession
    var photoOutput: AVCapturePhotoOutput?
    
    typealias ImageCompletion = (UIImage) -> Void
    var myDelegate: Delegate?
    
    init() {
        session = AVCaptureSession()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) else { return }
        try! device.lockForConfiguration()
        device.exposureMode = .continuousAutoExposure
        device.torchMode = .off
        device.activeColorSpace = .sRGB
        device.autoFocusRangeRestriction = .none
        device.focusMode = .continuousAutoFocus
        device.isSubjectAreaChangeMonitoringEnabled = true
        device.unlockForConfiguration()
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        photoOutput = AVCapturePhotoOutput()
        photoOutput?.maxPhotoQualityPrioritization = .quality
        guard session.canAddOutput(photoOutput!) else { return }
        session.addOutput(photoOutput!)
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
        }
    }
    
    class Delegate: NSObject, AVCapturePhotoCaptureDelegate {
        let imageComletion: (UIImage) -> Void
        public init(_ imageComletion: @escaping ImageCompletion) { self.imageComletion = imageComletion }
        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
            if let normalizedImage = image.fixedOrientation().croppedBy(2.0) {
                imageComletion(normalizedImage)
            }
        }
    }
    
    func takePhoto(_ imageCompletion: @escaping ImageCompletion) {
        myDelegate = Delegate(imageCompletion)
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        settings.embedsDepthDataInPhoto = false
        settings.embedsPortraitEffectsMatteInPhoto = false
        settings.embedsSemanticSegmentationMattesInPhoto = false
        settings.isAutoRedEyeReductionEnabled = false
        settings.isShutterSoundSuppressionEnabled = false
        settings.photoQualityPrioritization = .quality
        photoOutput?.capturePhoto(with: settings, delegate: myDelegate!)
    }
}

struct CameraPreview: UIViewRepresentable {
    
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = DotMatrixReader.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.videoPreviewLayer.connection?.videoRotationAngle = 90
        return view
    }
    
    public func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
    
    class VideoPreviewView: UIView {
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(deviceOrientationDidChange),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(subjectAreaDidChangeNotification),
                name: AVCaptureDevice.subjectAreaDidChangeNotification,
                object: nil
            )
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }
        
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
        
        @objc private func deviceOrientationDidChange() {
            switch UIDevice.current.orientation {
                case .portrait:
                    videoPreviewLayer.connection?.videoRotationAngle = 90
                case .portraitUpsideDown:
                    videoPreviewLayer.connection?.videoRotationAngle = 270
                case .landscapeLeft:
                    videoPreviewLayer.connection?.videoRotationAngle = 0
                case .landscapeRight:
                    videoPreviewLayer.connection?.videoRotationAngle = 180
                default: break
            }
        }
        
        @objc private func subjectAreaDidChangeNotification() {
        }
    }
}
