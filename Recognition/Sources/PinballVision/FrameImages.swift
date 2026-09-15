import Foundation
import CoreImage
import CoreGraphics
import Vision
import simd

public struct VisionPack: Codable, Sendable {
    public struct Seed: Codable, Sendable { public let id: String; public let image: String; public let corners: [[Double]] }
    public struct Mode: Codable, Sendable { public let name: String; public let image: String }
    public let version: Int
    public let seeds: [Seed]
    public let modes: [Mode]
    public let referenceToLegacy: [[Double]]
}

public enum DetectionError: Error { case invalidImage, registrationFailed, invalidConfiguration, missingTrack, readFailed }

struct Pixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]
    let stride: Int
    init(_ image: CGImage) throws {
        guard image.bitsPerPixel == 32, let data = image.dataProvider?.data else { throw DetectionError.invalidImage }
        width = image.width; height = image.height; stride = image.bytesPerRow
        bytes = Array(data as Data)
        guard bytes.count >= stride * height else { throw DetectionError.invalidImage }
    }
    func rgb(_ x: Int, _ y: Int) -> (Float, Float, Float) {
        let i = y * stride + x * 4
        return (Float(bytes[i]) / 255, Float(bytes[i+1]) / 255, Float(bytes[i+2]) / 255)
    }
    func gray() -> [Float] {
        (0..<height).flatMap { y in (0..<width).map { x in
            let (r,g,b) = rgb(x,y); return max(r,g,b)
        } }
    }
}

func correlate(_ a: [Float], _ b: [Float], indices: [Int]) -> Double {
    guard !indices.isEmpty else { return 0 }
    var sx=0.0, sy=0.0, xx=0.0, yy=0.0, xy=0.0
    for i in indices {
        let x=Double(a[i]), y=Double(b[i]); sx += x; sy += y; xx += x*x; yy += y*y; xy += x*y
    }
    let n=Double(indices.count)
    return (xy-sx*sy/n) / max(sqrt(max(0,(xx-sx*sx/n)*(yy-sy*sy/n))),1e-9)
}

func smooth(_ values: [Float]) -> [Float] {
    var result=values
    for y in 1..<31 { for x in 1..<127 {
        var v:Float=0
        for dy in -1...1 { for dx in -1...1 {
            let weight:Float=(dx==0 ? 0.723 : 0.1385)*(dy==0 ? 0.723 : 0.1385)
            v += values[(y+dy)*128+x+dx]*weight
        } }
        result[y*128+x]=v
    } }
    return result
}

func shifted(_ values: [Float], dx: Float, dy: Float) -> [Float] {
    var result=[Float](repeating:0,count:4096)
    for y in 0..<32 { for x in 0..<128 {
        let px=Float(x)+dx,py=Float(y)+dy
        let xx=Int(floor(px)),yy=Int(floor(py))
        guard xx>=0,xx<127,yy>=0,yy<31 else { continue }
        let ax=px-Float(xx),ay=py-Float(yy)
        result[y*128+x]=(values[yy*128+xx]*(1-ax)+values[yy*128+xx+1]*ax)*(1-ay) +
            (values[(yy+1)*128+xx]*(1-ax)+values[(yy+1)*128+xx+1]*ax)*ay
    } }
    return result
}

func agreesWithModeTitle(_ observed: String, mode: String) -> Bool {
    let target=Array(mode.uppercased().filter(\.isLetter))
    let text=Array(observed.uppercased().filter(\.isLetter))
    if String(text).contains(String(target)) { return true }
    guard target.count>=10 else { return false }
    // The pixel matcher already selected this mode with a margin. Permit one
    // OCR glyph error in a long title (for example W read as N), not fuzzy mode
    // discovery over arbitrary text. Only the leading title is compared.
    for length in (target.count-1)...(target.count+1) where text.count>=length {
        let prefix=Array(text.prefix(length));var row=Array(0...prefix.count)
        for (i,a) in target.enumerated() {
            var next=[i+1]
            for (j,b) in prefix.enumerated() { next.append(min(next[j]+1,row[j+1]+1,row[j]+(a==b ? 0 : 1))) }
            row=next
        }
        if row.last!<=1 { return true }
    }
    return false
}

final class ImageWork {
    let context = CIContext(options: [.cacheIntermediates: false])
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    func cg(_ image: CIImage, width: Int, height: Int) throws -> CGImage {
        let extent=image.extent
        let normalized=image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: Double(width)/extent.width, y: Double(height)/extent.height))
        guard let cg=context.createCGImage(normalized, from: CGRect(x:0,y:0,width:width,height:height), format:.RGBA8, colorSpace:colorSpace) else { throw DetectionError.invalidImage }
        return cg
    }
    func load(_ url: URL) throws -> CIImage {
        guard let image=CIImage(contentsOf:url) else { throw DetectionError.invalidImage }; return image
    }
    func rectified(_ full: CIImage, corners: [CGPoint], width: Int = 640, height: Int = 160) throws -> CGImage {
        guard corners.count == 4 else { throw DetectionError.invalidConfiguration }
        let keys=["inputTopLeft","inputTopRight","inputBottomRight","inputBottomLeft"]
        var values: [String:Any]=[:]
        for (key,p) in zip(keys,corners) { values[key]=CIVector(x:p.x,y:960-p.y) }
        let warped=full.applyingFilter("CIPerspectiveCorrection", parameters:values)
        return try cg(warped,width:width,height:height)
    }
    func write(_ image: CGImage, to url: URL) throws {
        try context.writePNGRepresentation(of:CIImage(cgImage:image),to:url,format:.RGBA8,colorSpace:colorSpace)
    }
}

/// Full centred guide registered against setup pictures. No timestamp-based pose
/// lookup or baseline crop CSV. Periodic fresh registration avoids accumulated drift.
final class DisplayLocator {
    struct Seed { let id: String; let image: CGImage; let corners: [CGPoint] }
    let work: ImageWork
    let seeds: [Seed]
    var preferred = 0
    var lastCorners: [CGPoint]?
    var lastMeasured = -Double.infinity
    var quality = 0.0
    var pose = "unacquired"
    let guide = CGRect(x:0,y:277.5,width:540,height:405)
    init(pack: VisionPack, folder: URL, work: ImageWork) throws {
        self.work=work
        let guide=CGRect(x:0,y:277.5,width:540,height:405)
        seeds=try pack.seeds.map { seed in
            let im=try work.load(folder.appendingPathComponent(seed.image))
            let crop=im.cropped(to:guide).transformed(by:CGAffineTransform(translationX:0,y:-guide.minY))
            return Seed(id:seed.id,image:try work.cg(crop,width:540,height:405),corners:seed.corners.map { CGPoint(x:$0[0],y:$0[1]) })
        }
    }
    func locate(_ full: CIImage, time: Double) throws -> [CGPoint]? {
        if time-lastMeasured < 0.5, let lastCorners { return lastCorners }
        let crop=full.cropped(to:guide).transformed(by:CGAffineTransform(translationX:0,y:-guide.minY))
        let image=try work.cg(crop,width:540,height:405)
        var best: (Double,Int,[CGPoint])?
        for index in [preferred] + seeds.indices.filter({ $0 != preferred }) {
            let seed=seeds[index]
            // Floating seed -> current reference, coordinates in lower-left pixels.
            let request=VNHomographicImageRegistrationRequest(targetedCGImage:seed.image)
            do { try VNImageRequestHandler(cgImage:image).perform([request]) } catch { continue }
            guard let result=request.results?.first else { continue }
            let matrix=result.warpTransform
            let q=seed.corners.map { p -> CGPoint in
                let v=matrix * SIMD3<Float>(Float(p.x),Float(960-p.y-guide.minY),1)
                return CGPoint(x:Double(v.x/v.z),y:960-(Double(v.y/v.z)+guide.minY))
            }
            guard q.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.x >= 0 && $0.x < 540 && $0.y > 277 && $0.y < 683 }),
                  q[1].x-q[0].x > 250, q[2].y-q[1].y > 50 else { continue }
            // Verify held-out cabinet image patches outside the display, using the
            // returned transform. Correlation is photometric evidence, not VN confidence.
            let current=try Pixels(image), reference=try Pixels(seed.image)
            var a:[Float]=[], b:[Float]=[]
            for y in stride(from:20,to:385,by:8) {
                for x in stride(from:24,to:520,by:8) {
                    let worldY=277.5+Double(y)
                    if x > 85 && x < 460 && worldY > 405 && worldY < 580 { continue }
                    let v=matrix * SIMD3<Float>(Float(x),Float(405-y),1)
                    let px=Int((v.x/v.z).rounded()), py=405-Int((v.y/v.z).rounded())
                    if px<0 || px>=540 || py<0 || py>=405 { continue }
                    let (r,g,bv)=reference.rgb(x,y), (rr,gg,bb)=current.rgb(px,py)
                    a.append((r+g+bv)/3); b.append((rr+gg+bb)/3)
                }
            }
            let score=correlate(a,b,indices:Array(a.indices))
            if best == nil || score > best!.0 { best=(score,index,q) }
            if score > 0.92 { break }
        }
        if let (score,index,q)=best, score > 0.70 {
            quality=score; preferred=index; pose=seeds[index].id; lastCorners=q; lastMeasured=time
            return q
        }
        quality=best?.0 ?? 0
        // A short hold survives one failed registration; longer failures produce no
        // high-confidence observations until reference registration succeeds again.
        if time-lastMeasured < 1 { return lastCorners }
        return nil
    }
}
