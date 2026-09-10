struct Configuration: Codable, Sendable {
    var requiredScanCount = 4
    var historyLimit = 10
    var fstopsDown = Float(-1)
    var qualityMode = true
    // Optional storage keeps settings saved by older versions decodable.
    var centeredScanArea: Bool?
    var useCenteredScanArea: Bool {
        get { centeredScanArea ?? false }
        set { centeredScanArea = newValue }
    }
    var filterImage = false
    var filterStrength = Float(0.5)
    var contrast = Float(1.5)
    var sharpness = Float(0.5)
}
