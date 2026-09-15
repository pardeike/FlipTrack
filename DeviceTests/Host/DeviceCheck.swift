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
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output,options:.atomic)
    }
}
