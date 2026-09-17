import CoreImage
import Vision

/// Locate the display frame, correct perspective, then read the layout. No
/// position or size is tied to the original holder photo.
struct DisplayObservation: Sendable {
    let frameID = UUID()
    var jpeg: Data?
    var processingMS: Double?
    var text: [DisplayText]
    var visibleBall: Int?
    var live: LiveScoreboard?
    var final: DisplayResult?
    init(_ text: [DisplayText], activeSlot: Int? = nil) {
        self.text = text
        self.visibleBall = LiveGameLayout.visibleBall(in: text)
        self.live = LiveGameLayout.result(in: text, activeSlot: activeSlot)
        self.final = live == nil && activeSlot == nil ? EndGameLayout.result(in: text) : nil
    }
}

enum DisplayReader {
    /// Largest landscape 4:3 rectangle that fits inside the upright frame.
    static func centeredScanRect(in frame: CGRect) -> CGRect {
        let width = min(frame.width, frame.height * 4 / 3)
        let height = width * 3 / 4
        return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2,
                      width: width, height: height)
    }

    static func read(_ input: CIImage) throws -> [DisplayText] { try analyze(input).text }

    static func analyze(_ input: CIImage) throws -> DisplayObservation {
        let image = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))
        let fullText = try recognize(image)
        // A complete BALL/footer anchor locates the moving display directly.
        // Avoid OCR on unrelated cabinet rectangles before this common path.
        if GameDisplayLayout.isNewGame(in: fullText) { return DisplayObservation(fullText) }
        if fullText.contains(where: { EndGameLayout.score(from: $0.text) == 0 }),
           !fullText.contains(where: { (EndGameLayout.score(from: $0.text) ?? 0) > 0 }),
           fullText.contains(where: { $0.text.uppercased().hasPrefix("BALL") }) {
            let smaller = try recognize(image.transformed(by: CGAffineTransform(scaleX: 2.0/3, y: 2.0/3)))
            if GameDisplayLayout.isNewGame(in: smaller) { return DisplayObservation(smaller) }
        }
        if let anchored = try footerDisplay(image, text: fullText) { return anchored }
        let rectangles = VNDetectRectanglesRequest()
        rectangles.minimumAspectRatio = 0.15
        rectangles.maximumAspectRatio = 0.65
        rectangles.minimumSize = 0.04
        rectangles.minimumConfidence = 0.6
        rectangles.maximumObservations = 4
        rectangles.quadratureTolerance = 35
        try VNImageRequestHandler(ciImage: image).perform([rectangles])
        var matches: [DisplayObservation] = []
        var display = DisplayObservation([])
        for rectangle in rectangles.results ?? [] {
            guard let corrected = correctedDisplay(image, rectangle: rectangle) else { continue }
            let text = try recognize(corrected).map { observation in
                var observation = observation
                observation.isInsideDisplay = true
                return observation
            }
            let observation = DisplayObservation(text, activeSlot: try activeScoreSlot(corrected, text: text))
            if observation.final != nil || (observation.live != nil && (observation.live?.left != nil || observation.live?.right != nil)) || GameDisplayLayout.isNewGame(in: text) ||
                GameDisplayLayout.isBonusScreen(in: text) { matches.append(observation) }
            if EndGameLayout.hasDisplayText(in: text) { display = observation }
        }
        if matches.count == 1 { return matches[0] }
        // Multiple matching displays are ambiguous; never pick one arbitrarily.
        if matches.count > 1 { return DisplayObservation([]) }
        if EndGameLayout.result(in: fullText) != nil || GameDisplayLayout.isNewGame(in: fullText) || GameDisplayLayout.isBonusScreen(in: fullText) { return DisplayObservation(fullText) }
        // Dot-matrix strokes can fragment at one OCR scale. Retry only a
        // potential two-zero screen; the same complete layout must still match.
        let zeroCount = fullText.filter { $0.text.range(of: #"^0{1,2}\s*-?$"#, options: .regularExpression) != nil }.count
        if zeroCount == 2 || (zeroCount == 1 && fullText.contains(where: { $0.text.uppercased().hasPrefix("BALL") })) {
            let smallerText = try recognize(image.transformed(by: CGAffineTransform(scaleX: 2.0 / 3, y: 2.0 / 3)))
            if GameDisplayLayout.isNewGame(in: smallerText) { return DisplayObservation(smallerText) }
        }
        // Glare can hide the frame. A partial FREE PLAY reading may locate a
        // crop, but only a complete, re-read layout can confirm a result.
        for anchor in fullText where anchor.text.uppercased()
            .range(of: #"^[FP]REE ?PLA"#, options: .regularExpression) != nil {
            let a = anchor.bounds
            let region = CGRect(x: a.midX - a.width * 2.4, y: a.minY - a.height,
                                width: a.width * 4.8, height: a.height * 13)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            let crop = CGRect(x: image.extent.minX + region.minX * image.extent.width,
                              y: image.extent.minY + region.minY * image.extent.height,
                              width: region.width * image.extent.width, height: region.height * image.extent.height)
            guard crop.width > 0, crop.height > 0 else { continue }
            let scale = max(1, 1800 / crop.width)
            let aligned = image.cropped(to: crop)
                .transformed(by: CGAffineTransform(rotationAngle: -anchor.rotation))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let text = try recognize(aligned)
            if EndGameLayout.result(in: text) != nil || LiveGameLayout.result(in: text) != nil || GameDisplayLayout.isNewGame(in: text) { return DisplayObservation(text) }
        }
        return display.text.isEmpty ? DisplayObservation(fullText) : display
    }

    private static func footerDisplay(_ image: CIImage, text: [DisplayText]) throws -> DisplayObservation? {
        let anchors = text.filter { $0.confidence >= 0.7 && $0.text.uppercased().filter { !$0.isWhitespace }.trimmingCharacters(in: .punctuationCharacters) == "FREEPLAY" }
        guard anchors.count == 1, let anchor = anchors.first,
              text.contains(where: { $0.text.uppercased().hasPrefix("BALL ") }) else { return nil }
        guard anchor.corners.count == 4 else { return nil }
        func pixel(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x*image.extent.width, y:p.y*image.extent.height) }
        let tl = pixel(anchor.corners[0]), tr = pixel(anchor.corners[1]), bl = pixel(anchor.corners[3])
        // The fixed FREE PLAY lettering supplies an orientation/scale anchor
        // when glare hides the black display border. Use its quadrilateral,
        // not its tilted axis-aligned bounding box, which overstates height.
        let u = CGPoint(x:(tr.x-tl.x)/0.31,y:(tr.y-tl.y)/0.31)
        let v = CGPoint(x:(tl.x-bl.x)/0.18,y:(tl.y-bl.y)/0.18)
        let origin = CGPoint(x:bl.x-u.x*0.48-v.x*0.04,y:bl.y-u.y*0.48-v.y*0.04)
        func corner(_ x: CGFloat, _ y: CGFloat) -> CIVector { CIVector(x:origin.x+u.x*x+v.x*y,y:origin.y+u.y*x+v.y*y) }
        let region = image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft":corner(-0.16,1.3),"inputTopRight":corner(1.10,1.3),"inputBottomLeft":corner(-0.16,-0.03),"inputBottomRight":corner(1.10,-0.03)])
        guard region.extent.width > 0, region.extent.height > 0 else { return nil }
        let resized = region.transformed(by: CGAffineTransform(scaleX: 1400/region.extent.width, y: 440/region.extent.height))
        var words = try recognize(resized).map { item in
            var item = item; item.isInsideDisplay = true; return item
        }
        // Keep a fully read ball digit if rectification fragments that small text.
        if !words.contains(where: { $0.text.range(of: #"^BALL\s*[123]"#, options: .regularExpression) != nil }),
           let originalBall = text.first(where: { $0.text.range(of: #"^BALL\s*[123]$"#, options: .regularExpression) != nil && abs($0.bounds.midY-anchor.bounds.midY) < anchor.bounds.height*1.5 }),
           let index = words.firstIndex(where: { $0.text.uppercased() == "BALL" }) {
            let word = words[index]
            words[index] = DisplayText(text: originalBall.text, confidence: min(word.confidence,originalBall.confidence), bounds: word.bounds, isInsideDisplay: true)
        }
        words = try separatedScores(in: resized, text: words)
        let result = DisplayObservation(words, activeSlot: try activeScoreSlot(resized, text: words))
        // A located BALL screen can be momentarily unreadable while its digits
        // blink. Keep it unknown instead of spending more OCR on cabinet art.
        return words.contains(where: { $0.text.uppercased().hasPrefix("BALL") }) ? result : nil
    }

    private static func separatedScores(in image: CIImage, text: [DisplayText]) throws -> [DisplayText] {
        guard let footer = text.filter({ $0.text.uppercased().contains("FREE") }).first else { return text }
        let bottom = footer.bounds.maxY + footer.bounds.height * 0.2
        let numbers = text.filter { $0.bounds.minY > bottom && EndGameLayout.score(from: $0.text) != nil }
        guard numbers.count != 2,
              text.contains(where: { word in
                  word.bounds.minY > bottom && word.text.filter(\.isNumber).count >= 12
              }) else { return text }
        let geometry = try activeScoreGeometry(image, text: text)
        let split: CGFloat = geometry?.split ?? 0.5
        var recovered: [DisplayText] = []
        for side in 0..<2 {
            let r = CGRect(x: side == 0 ? 0 : split, y: bottom, width: side == 0 ? split : 1-split, height: 1-bottom)
            guard r.height > 0 else { return text }
            let crop = CGRect(x: image.extent.minX+r.minX*image.extent.width, y: image.extent.minY+r.minY*image.extent.height,
                              width: r.width*image.extent.width, height: r.height*image.extent.height)
            // Give OCR a dark margin without importing digits from the other
            // field. The pixel-derived split can sit very close to both scores.
            let paddedBounds = crop.insetBy(dx: -image.extent.width * 0.025, dy: -image.extent.height * 0.025)
            let padded = image.cropped(to: crop).composited(over: CIImage(color: .black).cropped(to: paddedBounds))
            let words = try recognize(padded)
            let valid = words.compactMap { word -> DisplayText? in
                // Vision can insert a space within one digit group. Only remove
                // it inside an isolated score field with explicit separators.
                let value = word.text.contains(",") || word.text.contains(".")
                    ? word.text.replacingOccurrences(of: " ", with: "") : word.text
                let b = word.bounds
                guard EndGameLayout.score(from: value) != nil, b.minX > 0.015, b.maxX < 0.985,
                      b.height * paddedBounds.height / image.extent.height > footer.bounds.height * 0.65 else { return nil }
                return DisplayText(text: value, confidence: word.confidence,
                    bounds: CGRect(x: (paddedBounds.minX + b.minX * paddedBounds.width - image.extent.minX) / image.extent.width,
                                   y: (paddedBounds.minY + b.minY * paddedBounds.height - image.extent.minY) / image.extent.height,
                                   width: b.width * paddedBounds.width / image.extent.width,
                                   height: b.height * paddedBounds.height / image.extent.height).intersection(r), isInsideDisplay: true)
            }
            guard valid.count == 1 else { continue }
            recovered.append(valid[0])
        }
        guard !recovered.isEmpty else { return text }
        return text.filter { $0.bounds.midY < bottom } + recovered
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Ported from the research activeSlot geometry, on a newly located display.
    /// Color ratios reject cabinet art; OCR size evidence supplies a neutral-color fallback.
    private static func activeScoreSlot(_ input: CIImage, text: [DisplayText]) throws -> Int? {
        try activeScoreGeometry(input, text: text)?.slot
    }

    private static func activeScoreGeometry(_ input: CIImage, text: [DisplayText]) throws -> (slot: Int, split: CGFloat)? {
        let normalized = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))
        let image = normalized.transformed(by: CGAffineTransform(scaleX: 640 / normalized.extent.width, y: 160 / normalized.extent.height))
        let w = 640, h = 160
        guard let cg = context.createCGImage(image, from: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()),
              let data = cg.dataProvider?.data else { return nil }
        let pixels = Array(data as Data)
        let stride = cg.bytesPerRow
        var mask = [Bool](repeating: false, count: w*125)
        for y in 5..<125 { for x in 0..<w {
            let i = y*stride+x*4
            let r = Double(pixels[i])/255, g = Double(pixels[i+1])/255, b = Double(pixels[i+2])/255
            mask[y*w+x] = max(r,g) > 0.16 && g > b*1.25 && (r > b*1.08 || g > r*1.3)
        } }
        var glyphs: [(x: Int, height: Int, minX: Int, maxX: Int)] = []
        for start in mask.indices where mask[start] {
            mask[start] = false
            var queue = [start], index = 0, minX = start%w, maxX = start%w, minY = start/w, maxY = start/w
            while index < queue.count {
                let i = queue[index]; index += 1
                let x = i%w, y = i/w
                minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y)
                for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where nx >= 0 && nx < w && ny >= 0 && ny < 125 {
                    let n = ny*w+nx
                    if mask[n] { mask[n] = false; queue.append(n) }
                }
            }
            let height = maxY-minY+1, width = maxX-minX+1
            if height > 16 && height < 90 && queue.count > 45 && width > 4 && width < 125 { glyphs.append(((minX+maxX)/2, height, minX, maxX)) }
        }
        // Glare can extend one component. Use the typical digit height, not
        // the tallest fragment. Adjacent zeros may form one connected component.
        func height(_ range: Range<Int>) -> Int {
            let heights = glyphs.filter { range.contains($0.x) }.map(\.height).sorted()
            guard !heights.isEmpty else { return 0 }
            return heights[(heights.count - 1) / 2]
        }
        let left = height(65..<350), right = height(380..<580)
        let footer = text.filter { $0.text.uppercased().contains("FREE") }.min { $0.bounds.height < $1.bounds.height }
        let footerHeight = footer.map { Double($0.bounds.height)*160 } ?? 14
        let scoreCount = text.filter {
            EndGameLayout.score(from: $0.text) != nil && $0.bounds.midY > (footer?.bounds.maxY ?? 0.3)
        }.count
        // Two readable score fields support relative size evidence. With only
        // one field, require more absolute height so an inactive score cannot
        // become active just because its blinking neighbor has disappeared.
        let minimumRatio = scoreCount == 2 ? 1.7 : 1.8
        guard Double(max(left,right)) >= max(18,footerHeight*minimumRatio) else { return nil }
        let slot: Int
        if Double(left) > Double(right)*1.15 { slot = 1 }
        else if Double(right) > Double(left)*1.15 { slot = 2 }
        else { return nil }
        let activeHeight = slot == 1 ? left : right
        let large = glyphs.filter {
            Double($0.height) >= Double(activeHeight) * 0.8 &&
            (slot == 1 ? (65..<460).contains($0.x) : (250..<580).contains($0.x))
        }
        var split: CGFloat = slot == 1 ? 0.60 : 0.45
        if slot == 1, let edge = large.map(\.maxX).max(),
           let next = glyphs.filter({ $0.minX > edge && $0.x < 580 }).map(\.minX).min() {
            split = CGFloat(edge + next) / CGFloat(w * 2)
        } else if slot == 2, let edge = large.map(\.minX).min(),
                  let previous = glyphs.filter({ $0.maxX < edge && $0.x > 65 }).map(\.maxX).max() {
            split = CGFloat(edge + previous) / CGFloat(w * 2)
        }
        return (slot, split)
    }

    private static func correctedDisplay(_ image: CIImage, rectangle: VNRectangleObservation) -> CIImage? {
        func point(_ p: CGPoint) -> CIVector {
            CIVector(x: image.extent.minX + p.x * image.extent.width,
                     y: image.extent.minY + p.y * image.extent.height)
        }
        let corrected = image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft": point(rectangle.topLeft), "inputTopRight": point(rectangle.topRight),
            "inputBottomLeft": point(rectangle.bottomLeft), "inputBottomRight": point(rectangle.bottomRight)
        ])
        let ratio = corrected.extent.width / corrected.extent.height
        guard ratio >= 2, ratio <= 6 else { return nil }
        // Give Vision a consistent text size even when the screen occupies a
        // small part of a video frame. Upsampling cannot recover hidden digits.
        let scale = max(1, 1400 / corrected.extent.width)
        return corrected.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private static func recognize(_ input: CIImage) throws -> [DisplayText] {
        let image = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.008
        try VNImageRequestHandler(ciImage: image).perform([request])
        return (request.results ?? []).flatMap { observation -> [DisplayText] in
            guard let text = observation.topCandidates(1).first else { return [] }
            let angle = atan2((observation.topRight.y - observation.topLeft.y) * image.extent.height,
                              (observation.topRight.x - observation.topLeft.x) * image.extent.width)
            func item(_ range: Range<String.Index>) -> DisplayText {
                let value = String(text.string[range])
                let bounds = (try? text.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                let height = max(0, bounds.height - abs(tan(angle)) * bounds.width * image.extent.width / image.extent.height)
                return DisplayText(text: value, confidence: text.confidence, bounds: bounds, rotation: angle,
                                   characterHeight: height, corners: [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft])
            }
            // Some Vision versions join both score fields into one OCR line.
            // Split only a complete pair with valid thousands grouping.
            let pattern = #"^([0-9]{1,3}(?:[,\.][0-9]{3}){1,})\s*([0-9]{1,3}(?:[,\.][0-9]{3}){1,})$"#
            if let expression = try? NSRegularExpression(pattern: pattern),
               let match = expression.firstMatch(in: text.string, range: NSRange(text.string.startIndex..., in: text.string)),
               let left = Range(match.range(at: 1), in: text.string), let right = Range(match.range(at: 2), in: text.string) {
                let l = item(left), r = item(right)
                // Some Vision versions return the whole line for both ranges.
                // Keep that line intact so separate pixel crops can establish
                // real field bounds; duplicated bounds must never assign scores.
                if l.bounds.maxX < r.bounds.minX { return [l, r] }
            }
            return [item(text.string.startIndex..<text.string.endIndex)]
        }
    }
}
