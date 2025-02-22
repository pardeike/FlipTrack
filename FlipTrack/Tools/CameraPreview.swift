import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = Scanner.camera.session
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
