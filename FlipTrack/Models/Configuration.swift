struct Configuration: Codable {
    var requiredScanCount = 3
    var historyLimit = 10
    var fstopsDown = Float(-1)
    var qualityMode = true
    var filterImage = false
    var filterStrength = Float(0.5)
    var contrast = Float(1.5)
    var sharpness = Float(0.5)
}
