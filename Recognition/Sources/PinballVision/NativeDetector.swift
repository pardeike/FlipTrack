import Foundation
import CoreImage
import Vision
import PinballTracking

public struct DetectedMoment: Codable, Sendable {
    public let id: String
    public let kind: String
    public let sourceTime: Double
    public let confirmedAt: Double
    public let parameters: [String:String]
    public let evidencePath: String
    public let confidence: Double
}

struct TextLine: Codable { let text: String; let x: Double; let y: Double; let width: Double; let height: Double }
struct FrameEvidence: Codable {
    let time: Double; let pose: String; let geometryQuality: Double; let corners: [[Double]]
    let lines: [TextLine]; let slot: Int?; let ball: Int?; let mode: String?
    let modeSimilarity: Double; let runnerUp: Double
    var geometryRefinement: [Double]? = nil
    var geometryHeldOutBefore: Double? = nil
    var geometryHeldOutAfter: Double? = nil
}

/// Serial processor shared by file replay and a future camera actor. No baseline
/// or cached OCR is read. Every observation is derived from the supplied image.
public final class NativeDetector {
    private let work=ImageWork()
    private let locator: DisplayLocator
    private let pack: VisionPack
    private let output: URL
    private let log: FileHandle
    private let encoder=JSONEncoder()
    private var references: [(String,[Float])]=[]
    private var referenceBlue: [Float]=[]
    private var correctionX: Float=0
    private var correctionY: Float=0
    private var correctionPose=""
    private var geometryGate=GeometryRefinement()
    private var events: [DetectedMoment]=[]
    private var tracker: SessionTracker
    private var turnVotes: [(Double,Int,Int,CGImage)]=[]
    private var modeVotes: [(Double,String,Double,CGImage)]=[]
    private var currentTurn: (Int,Int)?
    private var lastModeSeen: [String:Double]=[:]
    private var emittedModeEpisodes: Set<String>=[]
    private var processed=0
    private var lostSince: Double?
    private var reportedLoss=false
    private var lastScoreboardNumbers: Set<Int64>=[]
    private var preLossScores: Set<Int64>=[]
    private var preLossContext: TurnContext?
    private var firstScoreWitness: Double?
    private var scoreWitnessCount=0
    private var lastProgress = -Double.infinity
    private let signatureIndices=(3..<27).flatMap { y in (17..<111).map { y*128+$0 } }

    public init(references folder: URL, output: URL, firstPlayer: String = "person-a", secondPlayer: String = "person-b") throws {
        pack=try JSONDecoder().decode(VisionPack.self,from:Data(contentsOf:folder.appendingPathComponent("references.json")))
        guard pack.version==1,pack.seeds.count>0,pack.modes.count==12 else { throw DetectionError.invalidConfiguration }
        self.output=output
        locator=try DisplayLocator(pack:pack,folder:folder,work:work)
        tracker=try SessionTracker(firstPlayer:firstPlayer,secondPlayer:secondPlayer)
        FileManager.default.createFile(atPath:output.appendingPathComponent("frames.jsonl").path,contents:nil)
        log=try FileHandle(forWritingTo:output.appendingPathComponent("frames.jsonl"))
        encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        geometryGate.minimumHeldOutCorrelation=0.65
        geometryGate.minimumImprovement=0.005
        for mode in pack.modes {
            let image=try work.load(folder.appendingPathComponent(mode.image))
            let pixels=try Pixels(work.cg(image,width:128,height:32))
            references.append((mode.name,smooth(pixels.gray())))
            if referenceBlue.isEmpty { referenceBlue=blue(pixels) }
        }
    }

    public func process(_ full: CIImage, time: Double) throws {
        processed += 1
        if processed == 1 { try work.write(work.cg(full,width:540,height:960),to:output.appendingPathComponent("first-frame.png")) }
        if time-lastProgress>=30 {
            FileHandle.standardError.write(Data("Processed \(Int(time))s, \(processed) analysed frames, \(events.count) events\n".utf8));lastProgress=time
        }
        guard let corners=try locator.locate(full,time:time) else {
            if lostSince == nil {
                lostSince=time;preLossContext=tracker.turns.last;preLossScores=lastScoreboardNumbers
                firstScoreWitness=nil;scoreWitnessCount=0
            }
            if !reportedLoss, let lostSince, time-lostSince>=5 {
                _ = try tracker.consume(TrackingObservation(id:"tracking-loss-\(Int(time*600))",kind:.continuityLost,
                    sourceTime:lostSince,observedTime:time))
                reportedLoss=true
            }
            try writeFrame(FrameEvidence(time:time,pose:"lost",geometryQuality:locator.quality,corners:[],lines:[],slot:nil,ball:nil,mode:nil,modeSimilarity:0,runnerUp:0))
            turnVotes=[]; modeVotes=[];return
        }
        lostSince=nil;reportedLoss=false
        let crop=try work.rectified(full,corners:corners)
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.usesLanguageCorrection=false
        request.recognitionLanguages=["en-US"];request.minimumTextHeight=0.055
        if try hasScoreboardFooter(crop) { try VNImageRequestHandler(cgImage:crop).perform([request]) }
        var lines=(request.results ?? []).compactMap { observation -> TextLine? in
            guard let candidate=observation.topCandidates(1).first else { return nil }
            let b=observation.boundingBox
            return TextLine(text:candidate.string.uppercased(),x:b.minX,y:1-b.maxY,width:b.width,height:b.height)
        }
        let text=lines.map(\.text).joined(separator:" ")
        let ball=readBall(text)
        let isScoreboard=ball != nil && !["LOCK","JACK","HIT","SHOOT","SAVED","SAVE","CAPTIVE"].contains(where:text.contains)
        let slot=isScoreboard ? try activeSlot(crop) : nil
        // Apply the LED-plane prior to the old crop. No event timestamp enters this mapping.
        let h=pack.referenceToLegacy
        let square=[CGPoint(x:0,y:0),CGPoint(x:1,y:0),CGPoint(x:1,y:1),CGPoint(x:0,y:1)]
        let alignedCorners=square.map { p -> CGPoint in
            let z=h[2][0]*p.x+h[2][1]*p.y+h[2][2]
            return CGPoint(x:(h[0][0]*p.x+h[0][1]*p.y+h[0][2])/z*540,
                           y:(h[1][0]*p.x+h[1][1]*p.y+h[1][2])/z*960)
        }
        let canvas=CIImage(cgImage:crop).transformed(by:CGAffineTransform(scaleX:540.0/640,y:960.0/160))
        let aligned=try work.rectified(canvas,corners:alignedCorners,width:128,height:32)
        let pixels=try Pixels(aligned)
        if correctionPose != locator.pose { correctionX=0;correctionY=0;correctionPose=locator.pose;geometryGate.acquisitionConfirmed() }
        let refinement=refine(blue(pixels))
        let dx=refinement.dx,dy=refinement.dy
        let gray=smooth(shifted(pixels.gray(),dx:dx,dy:dy))
        let ranking=references.map { ($0.0,correlate(gray,$0.1,indices:signatureIndices)) }.sorted { $0.1>$1.1 }
        let best=ranking[0], runner=ranking[1].1
        // Whole title+instructions exclude generic scoreboard/results. Margin
        // separates similar instruction text; temporal confirmation follows below.
        var mode=best.1>=0.68 && best.1-runner>=0.08 ? best.0 : nil
        // Ambiguous pixel fits can request targeted title corroboration. OCR does
        // not invent a mode: the reference must already win with clear separation
        // and independently fitted frame support, then the title must agree (at most one glyph error for long titles).
        if mode == nil, best.1>=0.55, best.1-runner>=0.12, refinement.after>=0.45 {
            if request.results == nil {
                try VNImageRequestHandler(cgImage:crop).perform([request])
                lines=(request.results ?? []).compactMap { observation in
                    guard let candidate=observation.topCandidates(1).first else { return nil }
                    let b=observation.boundingBox
                    return TextLine(text:candidate.string.uppercased(),x:b.minX,y:1-b.maxY,width:b.width,height:b.height)
                }
            }
            let title=lines.filter{$0.y<0.6}.sorted{$0.y<$1.y}.map(\.text).joined().filter(\.isLetter)
            if agreesWithModeTitle(title,mode:best.0) { mode=best.0 }
        }
        if let mode, best.1>=0.78, best.1-runner>=0.12 {
            let decision=geometryGate.evaluate(GeometryEvidence(time:time,referenceID:mode,trustedStaticReference:true,
                staticRegionsCovered:2,heldOutBefore:refinement.before,heldOutAfter:refinement.after,
                maxCornerShiftDots:Double(hypot(dx-correctionX,dy-correctionY)),
                homography:[1,0,Double(dx),0,1,Double(dy),0,0,1]))
            if decision == .accepted { correctionX=dx;correctionY=dy }
        }
        var evidence=FrameEvidence(time:time,pose:locator.pose,geometryQuality:locator.quality,
            corners:corners.map{[$0.x,$0.y]},lines:lines,slot:slot,ball:ball,mode:mode,
            modeSimilarity:best.1,runnerUp:runner)
        evidence.geometryRefinement=[Double(dx),Double(dy)]
        evidence.geometryHeldOutBefore=refinement.before;evidence.geometryHeldOutAfter=refinement.after
        try writeFrame(evidence)
        if let ball, isScoreboard {
            // At a zero-score BALL 1 presentation the large active glyph can be
            // absent. This is a first-turn cue only initially or after P2/B3.
            let numbers=lines.filter{$0.y<0.65}.map{$0.text.filter(\.isNumber)}.filter{!$0.isEmpty}
            let zeroStart=ball==1 && !numbers.isEmpty && numbers.allSatisfy{$0.allSatisfy{$0=="0"}}
            let resolved=zeroStart && (currentTurn == nil || currentTurn?.0==2 && currentTurn?.1==3) ? 1 : slot
            let scores=scoreNumbers(lines.filter{$0.y<0.65}.map(\.text).joined(separator:" "))
            if let resolved {
                try recoverIdentity(time:time,slot:resolved,ball:ball,scores:scores)
                try voteTurn(time,slot:resolved,ball:ball,crop:crop)
            }
            if !scores.isEmpty { lastScoreboardNumbers=scores }
        }
        if let mode {
            let shiftedCorners=square.map { p -> CGPoint in
                let x=p.x+Double(dx)/128,y=p.y+Double(dy)/32
                let z=h[2][0]*x+h[2][1]*y+h[2][2]
                return CGPoint(x:(h[0][0]*x+h[0][1]*y+h[0][2])/z*540,
                               y:(h[1][0]*x+h[1][1]*y+h[1][2])/z*960)
            }
            let evidenceCrop=try work.rectified(canvas,corners:shiftedCorners)
            try voteMode(time,name:mode,similarity:best.1,crop:evidenceCrop)
        }
        else { modeVotes=modeVotes.filter { time-$0.0<=1 } }
        if processed<=3 || processed%240==0 { try work.write(crop,to:output.appendingPathComponent("sample-\(Int(time*1000)).png")) }
    }

    private func readBall(_ text: String) -> Int? {
        guard let range=text.range(of:#"\bBALL\s*([123])\b"#,options:.regularExpression) else { return nil }
        return text[range].last.flatMap { Int(String($0)) }
    }
    private func scoreNumbers(_ text: String) -> Set<Int64> {
        let compact=text.replacingOccurrences(of:" ",with:"")
        // Comma groups also separate OCR-merged adjacent scores such as
        // 28,841,440173,594,990. Ignore tiny/zero values as continuity witnesses.
        let regex=try? NSRegularExpression(pattern:#"[0-9]{1,3}(?:[,\.][0-9]{3}){2,}"#)
        let ns=compact as NSString
        return Set((regex?.matches(in:compact,range:NSRange(location:0,length:ns.length)) ?? []).compactMap { match in
            Int64(ns.substring(with:match.range).filter(\.isNumber))
        }.filter{$0>=1_000_000})
    }
    private func recoverIdentity(time:Double,slot:Int,ball:Int,scores:Set<Int64>) throws {
        guard tracker.needsIdentityAnchor,let previous=preLossContext else { return }
        let same=slot==previous.slot && ball==previous.ball
        let next=previous.slot==1 ? slot==2 && ball==previous.ball : slot==1 && ball==previous.ball+1
        guard same || next, !preLossScores.intersection(scores).isEmpty else { return }
        if firstScoreWitness == nil { firstScoreWitness=time }
        scoreWitnessCount += 1
        guard scoreWitnessCount>=2,let firstScoreWitness,time-firstScoreWitness>=0.4 else { return }
        let earliest=turnVotes.filter{$0.1==slot && $0.2==ball}.map{$0.0}.min() ?? firstScoreWitness
        let anchorTime=min(firstScoreWitness,earliest)
        _ = try tracker.consume(TrackingObservation(id:"score-continuity-\(Int(anchorTime*600))",kind:.identityAnchor,
            sourceTime:anchorTime,observedTime:time,slot:previous.slot,ball:previous.ball,
            anchorGame:previous.game,anchorPlayerOne:previous.playerOne))
        let record:[String:String]=["sourceTime":String(anchorTime),"confirmedAt":String(time),
            "reason":"Repeated unchanged nonzero scoreboard value plus same/next turn across geometry loss", "game":String(previous.game)]
        try encoder.encode(record).write(to:output.appendingPathComponent("identity-recovery-\(Int(anchorTime*600)).json"))
        preLossContext=nil;preLossScores=[]
    }
    private func blue(_ p: Pixels) -> [Float] {
        (0..<32).flatMap { y in (0..<128).map { x in
            let (r,g,b)=p.rgb(x,y);return max(0,b-max(r,g)*1.08)
        } }
    }
    private func refine(_ current: [Float]) -> (dx:Float,dy:Float,before:Double,after:Double) {
        let indices=(3..<29).flatMap { y in (3..<125).filter{$0<17 || $0>111}.map{y*128+$0} }
        let train=indices.filter{($0%128)%2==0},heldOut=indices.filter{($0%128)%2==1}
        let before=correlate(shifted(current,dx:correctionX,dy:correctionY),referenceBlue,indices:heldOut)
        // Only attempt local acquisition when the expected blue frame has support.
        guard current.reduce(0,+)>12 else { return(correctionX,correctionY,before,before) }
        var best=(-Double.infinity,correctionX,correctionY)
        for yi in -4...4 { for xi in -4...4 {
            let x=correctionX+Float(xi)*0.5,y=correctionY+Float(yi)*0.5
            guard abs(x)<=4,abs(y)<=4 else { continue }
            let candidate=shifted(current,dx:x,dy:y)
            let score=correlate(candidate,referenceBlue,indices:train)
            if score>best.0 { best=(score,x,y) }
        } }
        let after=correlate(shifted(current,dx:best.1,dy:best.2),referenceBlue,indices:heldOut)
        // A local candidate may be tested by the independent title classifier
        // before it is trusted as persistent calibration. The stricter gate above
        // still controls persistence; identity/margin/temporal gates control events.
        if after>=0.45 && after>=before+0.005 { return(best.1,best.2,before,after) }
        return(correctionX,correctionY,before,before)
    }
    private func hasScoreboardFooter(_ image: CGImage) throws -> Bool {
        let p=try Pixels(image);var green=0,total=0
        for y in stride(from:118,to:156,by:2) { for x in stride(from:75,to:620,by:2) {
            let (r,g,b)=p.rgb(x,y);total += 1
            if g>0.25 && g>r*1.25 && g>b*1.1 { green += 1 }
        } }
        return Double(green)/Double(total)>0.025
    }
    private func activeSlot(_ image: CGImage) throws -> Int? {
        let p=try Pixels(image);let w=p.width,h=min(95,p.height)
        var mask=[Bool](repeating:false,count:w*h)
        for y in 5..<h { for x in 0..<w {
            let (r,g,b)=p.rgb(x,y);mask[y*w+x]=r>0.33 && g>0.29 && r>b*1.1 && g>b*1.08
        } }
        var centers:[Int]=[]
        for start in mask.indices where mask[start] {
            mask[start]=false;var queue=[start],index=0,minX=start%w,maxX=minX,minY=start/w,maxY=minY
            while index<queue.count {
                let i=queue[index];index += 1;let x=i%w,y=i/w
                minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
                for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where nx>=0 && nx<w && ny>=0 && ny<h {
                    let n=ny*w+nx;if mask[n] {mask[n]=false;queue.append(n)}
                }
            }
            let height=maxY-minY+1,width=maxX-minX+1
            if height>40 && height<78 && minY<20 && queue.count>160 && width>7 && width<125 { centers.append((minX+maxX)/2) }
        }
        guard !centers.isEmpty else { return nil };centers.sort()
        let middle=centers.count/2
        let median=centers.count%2==0 ? (centers[middle-1]+centers[middle])/2 : centers[middle]
        return median<325 ? 1 : median>345 ? 2 : nil
    }
    private func voteTurn(_ time: Double,slot:Int,ball:Int,crop:CGImage) throws {
        turnVotes=turnVotes.filter { time-$0.0<=3 }
        turnVotes.append((time,slot,ball,crop))
        let matching=turnVotes.filter{$0.1==slot && $0.2==ball}
        guard matching.count>=3,Double(matching.count)/Double(turnVotes.count)>=0.75,
              currentTurn?.0 != slot || currentTurn?.1 != ball else { return }
        let start=matching[0].0
        let newGame=currentTurn?.0==2 && currentTurn?.1==3 && slot==1 && ball==1
        let id="turn-\(Int((start*600).rounded()))"
        let observation=TrackingObservation(id:id,kind:.turn,sourceTime:start,observedTime:time,slot:slot,ball:ball,newGame:newGame)
        let interpreted=try tracker.consume(observation)
        currentTurn=(slot,ball);turnVotes=[]
        var params=["machine_slot":String(slot),"ball":String(ball),"new_game":String(newGame)]
        if let context=interpreted.first?.context { params["person"]=context.player;params["game"]=String(context.game) }
        else { params["person"]="unknown";params["game"]="unknown" }
        try emit(id:id,kind:"player_turn",start:start,time:time,parameters:params,crop:matching[0].3,confidence:locator.quality)
    }
    private func voteMode(_ time:Double,name:String,similarity:Double,crop:CGImage) throws {
        if time-(lastModeSeen[name] ?? -.infinity)>5 { emittedModeEpisodes.remove(name) }
        lastModeSeen[name]=time
        modeVotes=modeVotes.filter{time-$0.0<=1.5};modeVotes.append((time,name,similarity,crop))
        let matching=modeVotes.filter{$0.1==name}
        guard matching.count>=2,!emittedModeEpisodes.contains(name) else { return }
        let start=matching[0].0;emittedModeEpisodes.insert(name)
        let id="mode-\(Int((start*600).rounded()))"
        let interpreted=try tracker.consume(TrackingObservation(id:id,kind:.modeStart,sourceTime:start,observedTime:time,mode:name))
        var params=["mode":name,"person":"unknown","game":"unknown"]
        if let context=interpreted.first?.context {
            params["game"]=String(context.game);params["machine_slot"]=String(context.slot);params["ball"]=String(context.ball);params["person"]=context.player
        }
        try emit(id:id,kind:"mode_started",start:start,time:time,parameters:params,crop:matching[0].3,confidence:similarity)
    }
    private func emit(id:String,kind:String,start:Double,time:Double,parameters:[String:String],crop:CGImage,confidence:Double) throws {
        let path="\(id).png";try work.write(crop,to:output.appendingPathComponent(path))
        let event=DetectedMoment(id:id,kind:kind,sourceTime:start,confirmedAt:time,parameters:parameters,evidencePath:path,confidence:confidence)
        events.append(event)
        print(String(decoding:try encoder.encode(event),as:UTF8.self))
    }
    private func writeFrame(_ frame:FrameEvidence) throws {
        try log.write(contentsOf:encoder.encode(frame));try log.write(contentsOf:Data([10]))
    }
    public func finish(source:String,start:Double,end:Double,wallSeconds:Double,decoded:Int) throws {
        try log.close()
        struct Result:Codable {
            let version:Int;let detector:String;let source:String;let start:Double;let end:Double
            let wallSeconds:Double;let speed:Double;let decodedFrames:Int;let analysedFrames:Int
            let events:[DetectedMoment]
        }
        let result=Result(version:1,detector:"native-0.2",source:source,start:start,end:end,
            wallSeconds:wallSeconds,speed:(end-start)/wallSeconds,decodedFrames:decoded,analysedFrames:processed,events:events)
        try encoder.encode(result).write(to:output.appendingPathComponent("run.json"),options:.atomic)
    }
}
