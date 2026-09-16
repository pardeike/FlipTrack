import Foundation
import Observation

/// One append-only run. File access is serialized off the camera and main queues.
final class TelemetryWriter: @unchecked Sendable {
    struct Image: Sendable {
        let name: String
        let data: Data
    }
    let directory: URL
    private let queue = DispatchQueue(label: "net.pardeike.FlipTrack.telemetry", qos: .utility)
    private let file: FileHandle
    private var sequence = 0
    private let onError: @Sendable (String) -> Void

    init(root: URL, onError: @escaping @Sendable (String) -> Void = { _ in }) throws {
        self.onError = onError
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        directory = root.appendingPathComponent("\(stamp)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("images"), withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("events.jsonl")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        file = try FileHandle(forWritingTo: url)
    }

    deinit { try? file.close() }

    func record<T: Encodable>( _ event: String, _ payload: T, images: [Image] = []) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let date = ISO8601DateFormatter().string(from: Date())
        let uptime = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            do {
                var paths: [String] = []
                var imageErrors: [String] = []
                for image in images {
                    do {
                        // Caller-supplied names can never escape this run's image directory.
                        guard image.name == URL(fileURLWithPath: image.name).lastPathComponent,
                              image.name.hasSuffix(".jpg") else { throw CocoaError(.fileWriteInvalidFileName) }
                        let relative = "images/\(image.name)"
                        try image.data.write(to: directory.appendingPathComponent(relative), options: .atomic)
                        paths.append(relative)
                    } catch {
                        imageErrors.append("\(image.name): \(error.localizedDescription)")
                        onError("Score image could not be saved: \(error.localizedDescription)")
                    }
                }
                sequence += 1
                let entry: [String: Any] = [
                    "schemaVersion": 1, "sequence": sequence, "time": date, "uptime": uptime,
                    "event": event, "payload": try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
                    "images": paths, "imageErrors": imageErrors
                ]
                var line = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys, .fragmentsAllowed])
                line.append(0x0a)
                try file.write(contentsOf: line)
            } catch { onError("Telemetry could not be saved: \(error.localizedDescription)") }
        }
    }

    func flush() throws { try queue.sync { try file.synchronize() } }
}

/// Disabled until explicitly started by an app host; unit tests never write Documents.
@Observable @MainActor
final class Telemetry {
    static let shared = Telemetry()
    private init() {}
    private(set) var failure: String?
    private(set) var directory: URL?
    @ObservationIgnored private var writer: TelemetryWriter?

    func start(root: URL) {
        guard writer == nil else { return }
        do {
            let writer = try TelemetryWriter(root: root) { message in
                Task { @MainActor in Telemetry.shared.failure = message }
            }
            self.writer = writer
            directory = writer.directory
        } catch { failure = "Telemetry could not start: \(error.localizedDescription)" }
    }

    func log<T: Encodable>(_ event: String, _ payload: T, images: [TelemetryWriter.Image] = []) {
        do { try writer?.record(event, payload, images: images) }
        catch { failure = "Telemetry could not encode \(event): \(error.localizedDescription)" }
    }

    func action(_ name: String, session: Session? = nil, gameID: UUID? = nil) {
        log("action", Action(name: name, session: session.map(SessionSnapshot.init), gameID: gameID))
    }

    func change(_ name: String, before: SessionSnapshot, session: Session) {
        log(name, Change(before: before, after: SessionSnapshot(session)))
    }

    func flush() {
        do { try writer?.flush() }
        catch { failure = "Telemetry could not flush: \(error.localizedDescription)" }
    }

    struct Action: Encodable { let name: String; let session: SessionSnapshot?; let gameID: UUID? }
    struct Change: Encodable { let before: SessionSnapshot; let after: SessionSnapshot }
}
