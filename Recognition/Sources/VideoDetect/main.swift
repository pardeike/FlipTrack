import Foundation
import AVFoundation
import CoreImage
import PinballVision

@main struct VideoDetect {
    static func main() async throws {
        let a=CommandLine.arguments
        guard a.count >= 4 else { throw DetectionError.invalidConfiguration }
        let source=URL(fileURLWithPath:a[1]), references=URL(fileURLWithPath:a[2]), output=URL(fileURLWithPath:a[3])
        let start=a.count>4 ? Double(a[4]) ?? 0 : 0
        let duration=a.count>5 ? Double(a[5]) ?? 0 : 0
        guard !FileManager.default.fileExists(atPath:output.path) else { throw DetectionError.invalidConfiguration }
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:false)
        let detector=try NativeDetector(references:references,output:output)
        let asset=AVURLAsset(url:source)
        guard let track=try await asset.loadTracks(withMediaType:.video).first else { throw DetectionError.missingTrack }
        let transform=try await track.load(.preferredTransform)
        // AV track transforms use top-left video coordinates; Core Image uses
        // bottom-left coordinates. Conjugate the linear part by a vertical flip.
        // Translation is normalized from the resulting extent below.
        let ciTransform=CGAffineTransform(a:transform.a,b:-transform.b,c:-transform.c,d:transform.d,tx:0,ty:0)
        let total=try await asset.load(.duration).seconds
        let reader=try AVAssetReader(asset:asset)
        reader.timeRange=CMTimeRange(start:CMTime(seconds:start,preferredTimescale:600),duration:CMTime(seconds:duration>0 ? duration : total-start,preferredTimescale:600))
        let trackOutput=AVAssetReaderTrackOutput(track:track,outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        trackOutput.alwaysCopiesSampleData=false
        let provider=reader.outputProvider(for:trackOutput)
        try reader.start()
        let begin=Date(); var next=start; var decoded=0
        while let sample=try await provider.next() {
            decoded += 1
            let time=sample.presentationTimeStamp.seconds
            guard time+0.00001>=next else { continue }
            next=time+0.5
            // The CMSampleBuffer is borrowed only within the closure. CIImage retains
            // the image buffer during synchronous processing; no raw pointer escapes.
            try sample.withUnsafeSampleBuffer { buffer in
                guard let pixels=buffer.imageBuffer else { throw DetectionError.invalidImage }
                var image=CIImage(cvPixelBuffer:pixels).transformed(by:ciTransform)
                image=image.transformed(by:CGAffineTransform(translationX:-image.extent.minX,y:-image.extent.minY))
                image=image.transformed(by:CGAffineTransform(scaleX:540/image.extent.width,y:960/image.extent.height))
                try detector.process(image,time:time)
            }
        }
        try detector.finish(source:source.path,start:start,end:min(total,duration>0 ? start+duration : total),wallSeconds:Date().timeIntervalSince(begin),decoded:decoded)
    }
}
