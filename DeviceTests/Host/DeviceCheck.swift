import Foundation
import SwiftData

@MainActor
enum DeviceCheck {
    struct Failure: LocalizedError { let message:String; var errorDescription:String? { message } }
    static func require(_ condition:Bool,_ message:String) throws {
        if !condition { throw Failure(message:message) }
    }
    static func wait(_ predicate:() -> Bool, timeout:Double = 25) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime+timeout
        while !predicate() {
            if ProcessInfo.processInfo.systemUptime > deadline { throw Failure(message:"Timed out waiting for device assertion") }
            try await Task.sleep(for:.milliseconds(100))
        }
    }
    static func run(scanner:Scanner, session:Session, context:ModelContext, start:() -> Void) async {
        guard ProcessInfo.processInfo.environment["FLIPTRACK_AUTOCHECK"] == "1" else { return }
        let scenario = ProcessInfo.processInfo.environment["FLIPTRACK_TEST_SCENARIO"] ?? "turn"
        let output = URL.documentsDirectory.appendingPathComponent("autocheck-\(scenario).json")
        try? FileManager.default.removeItem(at:output)
        var report:[String:Any] = ["scenario":scenario,"passed":false,"runID":ProcessInfo.processInfo.environment["FLIPTRACK_CHECK_ID"] ?? "manual"]
        do {
            start()
            try await wait { scanner.camera.session.isRunning || scanner.error != nil }
            try require(scanner.error == nil, scanner.error ?? "Camera failed")
            try require(scanner.camera.session.isRunning,"Camera must be running")
            let initial = session.progress
            if scenario == "turn" {
                scanner.resync()
                try require(scanner.isResyncing,"Recovery must start")
                try await Task.sleep(for:.seconds(1))
                try require(scanner.camera.session.isRunning,"Recovery stopped camera")
                scanner.cancelResync()
                try require(session.progress == initial,"Cancel changed durable progress")
                scanner.resync()
                try await wait { !scanner.isResyncing || scanner.error != nil }
                try require(scanner.error == nil,scanner.error ?? "Recovery failed")
                try require(session.progress.turn == MachineTurn(slot:2,ball:2),"Wrong recovered turn")
                try require(session.progress.left == 1_234_000,"Outgoing score not captured")
                try require(session.games?.count == 2,"Live recovery saved a game")
            } else if scenario == "corrections" {
                let oldID = session.currentGameID
                guard let firstGame = session.games?.min(by: { $0.nr < $1.nr }) else { throw Failure(message: "Missing fixture game") }
                firstGame.scores = [9_000_000, 8_000_000]
                session.startingPlayerOverride = 0
                session.currentGameNumberOverride = 7
                try context.save()
                // Mutate while callbacks continue, without relying on editor pause.
                try session.updateProgress(GameProgress(turn: .init(slot: 1, ball: 2), left: 777_000, observedStart: true), for: oldID, in: context)
                try await wait { scanner.progress.left == 777_000 }
                try session.record(DisplayResult(left: 777_000, right: 888_000), for: oldID, in: context)
                try await wait { scanner.progress == session.progress }
                try require(session.currentGameID != oldID, "Manual addition did not advance identity")
                try require(session.awaitingNextStart, "Manual addition did not guard old finals")
                try require(session.games?.first(where: { $0.nr == 7 })?.scores == [777_000,888_000], "Manual game used stale order")
                scanner.resync()
                try await Task.sleep(for: .seconds(3))
                session.startingPlayerOverride = 0
                try context.save()
                try await wait { !scanner.isResyncing }
                try require(session.games?.count == 3, "Queued pre-correction readings saved a game")
                scanner.resync()
                try await wait { !scanner.isResyncing || scanner.error != nil }
                try require(scanner.error == nil, scanner.error ?? "Corrected recovery failed")
                try require(session.games?.count == 4, "Resync after manual addition did not save exactly one game")
                try require(session.games?.first(where: { $0.nr == 8 })?.scores == [33_970_770,215_172_210], "Final used stale person mapping")
                try require(firstGame.scores == [9_000_000,8_000_000], "Scanner overwrote historical correction")
                // Undo creates a draft. It must suspend saves even if invoked outside the editor.
                try session.undoLastGame(in: context)
                try await wait { scanner.isPaused }
                try require(session.games?.count == 3 && session.pendingCaptureScores.count == 2, "Undo lost its draft")
                try session.discardPendingCapture(in: context)
                start()
                scanner.resync()
                try await Task.sleep(for: .seconds(6))
                try require(session.games?.count == 3, "Discarded pair was accepted from stale rejection cache")
                scanner.cancelResync()
                try require(firstGame.scores == [9_000_000,8_000_000], "Correction lost after undo/resume")
            } else if scenario.hasPrefix("final") {
                scanner.resync()
                try await Task.sleep(for:.seconds(4))
                try require(scanner.isResyncing,"End animation ended recovery prematurely")
                try require(session.games?.count == 2,"End animation saved a game")
                try require(scanner.camera.session.isRunning,"Waiting for finals stopped camera")
                try await wait { session.games?.count == 3 || scanner.error != nil }
                try require(scanner.error == nil,scanner.error ?? "Final save failed")
                try require(!scanner.isResyncing,"Successful final save left blocker open")
                let expected = scenario == "finalPixels" ? [33_970_770,215_172_210] : [24_274_100,37_531_870]
                try require(session.lastCapturedScores == expected,"Wrong final scores")
                try await Task.sleep(for:.seconds(5))
                try require(session.games?.count == 3,"Repeated final screen duplicated game")
            } else if scenario == "recorded" {
                try await wait { session.progress.turn == MachineTurn(slot:2,ball:1) || scanner.error != nil }
                try require(scanner.error == nil,scanner.error ?? "Recorded recognition failed")
                try await wait { session.progress.left == 5_539_000 || scanner.error != nil }
                try await wait({ FileManager.default.fileExists(atPath:URL.documentsDirectory.appendingPathComponent("reader-performance.json").path) },timeout:45)
                try require(session.games?.count == 2,"Recorded live frames saved a game")
            }
            try require(scanner.camera.session.isRunning,"Camera stopped during recovery")
            let stored = try ModelContext(context.container).fetch(FetchDescriptor<Session>()).first
            try require(stored?.progress == session.progress,"Accepted progress did not persist")
            Telemetry.shared.flush()
            try require(Telemetry.shared.failure == nil, Telemetry.shared.failure ?? "Telemetry failed")
            guard let directory = Telemetry.shared.directory else { throw Failure(message: "Telemetry never started") }
            let log = try String(contentsOf: directory.appendingPathComponent("events.jsonl"), encoding: .utf8)
            let entries = try log.split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String:Any] }
            try require(entries.contains { $0["event"] as? String == "frame" }, "No frame telemetry")
            let images = entries.flatMap { $0["images"] as? [String] ?? [] }
            if scenario != "turn" {
                try require(!images.isEmpty, "Accepted pixel scores did not save images")
                for image in images {
                    let data = try Data(contentsOf: directory.appendingPathComponent(image))
                    try require(data.starts(with: [0xff,0xd8]), "Evidence is not a JPEG")
                }
            }
            report["telemetryDirectory"] = directory.lastPathComponent
            report["telemetryEvents"] = entries.count
            report["scoreImages"] = images.count
            report["passed"] = true
            report["cameraRunning"] = true
            report["gameCount"] = session.games?.count ?? 0
            report["turnSlot"] = session.progress.turn?.slot
            report["turnBall"] = session.progress.turn?.ball
        } catch {
            report["error"] = error.localizedDescription
            report["left"] = session.progress.left
            report["right"] = session.progress.right
            report["slot"] = session.progress.turn?.slot
        }
        Telemetry.shared.flush()
        report["telemetryDirectory"] = Telemetry.shared.directory?.lastPathComponent
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output,options:.atomic)
    }
}
