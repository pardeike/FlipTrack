import Foundation

enum ScanState: Equatable, Sendable {
    enum PauseReason: String, Sendable {
        case user, editing, background, restored

        var message: String {
            switch self {
            case .user: "Paused · Resume when the phone is in position."
            case .editing: "Paused for editing · Resume when ready."
            case .background: "Paused while away · Resume when ready."
            case .restored: "Session restored · Resume scanning when ready."
            }
        }
    }

    case off
    case starting
    case scanning
    case paused(PauseReason)
    case failed(String)

    var isMonitoring: Bool {
        switch self {
        case .starting, .scanning, .paused: true
        case .off, .failed: false
        }
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    var error: String? {
        if case .failed(let message) = self { return message }
        return nil
    }

    var title: String {
        switch self {
        case .off: "Scanner off"
        case .starting: "Starting camera"
        case .scanning: "Scanning"
        case .paused: "Scan paused"
        case .failed: "Needs attention"
        }
    }
}
