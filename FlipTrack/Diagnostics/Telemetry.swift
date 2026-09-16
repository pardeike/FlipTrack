import Foundation
import Observation

/// One append-only run. File access is serialized off the camera and main queues.
final class TelemetryWriter: @unchecked Sendable {
    struct Image: Sendable {
        let name: String
        let data: Data
    }
    let directory: URL
    private let queue: DispatchQueue
    private let file: FileHandle
    private let fileNumber: UInt64
    private let maxPendingBytes: Int
    private let pendingLock = NSLock()
    private var pendingBytes = 0
    private var droppedEvents = 0
    private var sequence = 0
    private let onError: @Sendable (String) -> Void

    init(root: URL, queue: DispatchQueue = DispatchQueue(label: "net.pardeike.FlipTrack.telemetry", qos: .utility), maxPendingBytes: Int = 16 * 1024 * 1024, onError: @escaping @Sendable (String) -> Void = { _ in }) throws {
        self.maxPendingBytes = maxPendingBytes
        self.queue = queue
        self.onError = onError
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        directory = root.appendingPathComponent("\(stamp)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("images"), withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("events.jsonl")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        file = try FileHandle(forWritingTo: url)
        guard let number = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? NSNumber else {
            throw CocoaError(.fileReadUnknown)
        }
        fileNumber = number.uint64Value
    }

    deinit { try? file.close() }

    func record<T: Encodable>( _ event: String, _ payload: T, images: [Image] = []) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let bytes = data.count + images.reduce(0) { $0 + $1.data.count }
        pendingLock.lock()
        guard bytes <= maxPendingBytes - pendingBytes else {
            droppedEvents += 1
            pendingLock.unlock()
            throw StorageError.backlog
        }
        pendingBytes += bytes
        let droppedBefore = droppedEvents
        droppedEvents = 0
        pendingLock.unlock()
        let date = ISO8601DateFormatter().string(from: Date())
        let uptime = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            defer {
                pendingLock.lock()
                pendingBytes -= bytes
                pendingLock.unlock()
            }
            do {
                // Finder can remove a run while this handle remains open. A write
                // to that unlinked file would otherwise succeed and disappear.
                let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("events.jsonl").path)
                guard (attributes[.systemFileNumber] as? NSNumber)?.uint64Value == fileNumber else {
                    throw StorageError.replaced
                }
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
                    "images": paths, "imageErrors": imageErrors, "droppedEventsBefore": droppedBefore
                ]
                var line = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys, .fragmentsAllowed])
                line.append(0x0a)
                try file.write(contentsOf: line)
            } catch { onError("Telemetry could not be saved: \(error.localizedDescription)") }
        }
    }

    func flush() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do { try file.synchronize(); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private enum StorageError: LocalizedError {
        case backlog, replaced
        var errorDescription: String? {
            switch self {
            case .backlog: "Telemetry storage is falling behind. Some events were not logged."
            case .replaced: "The active telemetry file was replaced. Restart FlipTrack to start a new log."
            }
        }
    }
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
        catch { failure = "Telemetry could not log \(event): \(error.localizedDescription)" }
    }

    func action(_ name: String, session: Session? = nil, gameID: UUID? = nil) {
        log("action", Action(name: name, session: session.map(SessionSnapshot.init), gameID: gameID))
    }

    func change(_ name: String, before: SessionSnapshot, session: Session) {
        log(name, Change(before: before, after: SessionSnapshot(session)))
    }

    func flush() async {
        do { try await writer?.flush() }
        catch { failure = "Telemetry could not flush: \(error.localizedDescription)" }
    }

    struct Action: Encodable { let name: String; let session: SessionSnapshot?; let gameID: UUID? }
    struct Change: Encodable { let before: SessionSnapshot; let after: SessionSnapshot }
}
