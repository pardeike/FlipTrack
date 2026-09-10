import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var showsScanArea = false

    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: VideoPreviewView, context: Context) {
        view.showsScanArea = showsScanArea
        view.setNeedsLayout()
        if let connection = view.videoPreviewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    final class VideoPreviewView: UIView {
        var showsScanArea = false
        private let scanShade = CAShapeLayer()
        private let scanBorder = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            scanShade.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
            scanShade.fillRule = .evenOdd
            scanBorder.fillColor = UIColor.clear.cgColor
            scanBorder.strokeColor = UIColor.systemYellow.cgColor
            scanBorder.lineWidth = 2
            layer.addSublayer(scanShade)
            layer.addSublayer(scanBorder)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layoutSubviews() {
            super.layoutSubviews()
            scanShade.isHidden = !showsScanArea
            scanBorder.isHidden = !showsScanArea
            guard showsScanArea else { return }
            // Convert the complete video frame to view coordinates so letterbox
            // margins never alter the guide's correspondence with the OCR crop.
            let videoRect = videoPreviewLayer.layerRectConverted(
                fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            let guide = DisplayReader.centeredScanRect(in: videoRect)
            let shade = UIBezierPath(rect: bounds)
            shade.append(UIBezierPath(rect: guide))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            scanShade.path = shade.cgPath
            scanBorder.path = UIBezierPath(rect: guide).cgPath
            CATransaction.commit()
        }

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
