struct Configuration: Codable {
    var requiredScanCount = 3
    var historyLimit = 10
    var fstopsDown = Float(-1)
    var qualityMode = true
    var filterImage = false
    var filterStrength = Float(0.5)
}
