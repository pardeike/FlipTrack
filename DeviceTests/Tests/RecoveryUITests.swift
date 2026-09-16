import XCTest

final class RecoveryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "Camera permission") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            if alert.buttons["OK"].exists { alert.buttons["OK"].tap(); return true }
            return false
        }
    }

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["FLIPTRACK_TEST_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(app.buttons["toggleScanning"].waitForExistence(timeout:10))
        app.buttons["toggleScanning"].tap()
        // A permission sheet can occur on the first installation only.
        let springboard = XCUIApplication(bundleIdentifier:"com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout:2) {
            let alert = springboard.alerts.firstMatch
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap() }
            else if alert.buttons["OK"].exists { alert.buttons["OK"].tap() }
        }
        XCTAssertTrue(app.buttons["resyncTracking"].waitForExistence(timeout:10))
        return app
    }

    private func current(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching:.any)["currentTurn"].firstMatch }
    private func waitLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval = 15) {
        let expectation = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@",text),object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:timeout),.completed)
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testCancelAndLiveTurnRecoveryKeepSameGame() {
        let app = launch("turn")
        waitLabel(current(app),contains:"Fredrik turn")
        screenshot("iPhone11Pro-scanning-controls")
        app.buttons["resyncTracking"].tap()
        XCTAssertTrue(app.buttons["cancelResync"].waitForExistence(timeout:3))
        screenshot("iPhone11Pro-resync-blocker")
        app.buttons["cancelResync"].tap()
        waitLabel(current(app),contains:"Game 3. Fredrik turn")
        XCTAssertFalse(app.buttons["cancelResync"].exists)
        app.buttons["resyncTracking"].tap()
        waitLabel(current(app),contains:"Game 3. Andreas turn")
        XCTAssertFalse(app.buttons["cancelResync"].exists)
        XCTAssertTrue(app.buttons["pauseMonitoring"].isEnabled)
        screenshot("iPhone11Pro-turn-restored")
    }

    func testWaitsThroughEndAnimationAndSavesOnlyOnce() {
        let app = launch("final")
        app.buttons["resyncTracking"].tap()
        XCTAssertTrue(app.buttons["cancelResync"].waitForExistence(timeout:3))
        waitLabel(current(app),contains:"Game 4. Andreas turn",timeout:20)
        XCTAssertFalse(app.buttons["cancelResync"].exists)
        // The camera continues presenting the same final pair for several seconds.
        let unchanged = XCTNSPredicateExpectation(predicate:NSPredicate(format:"label CONTAINS %@","Game 5."),object:current(app))
        unchanged.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for:[unchanged],timeout:5),.completed)
        screenshot("iPhone11Pro-final-saved-once")
    }

    func testManualAdditionPausesAndResumesUsingNewGame() {
        let app = launch("turn")
        app.buttons["Add scores"].tap()
        XCTAssertTrue(app.textFields["leftScore"].waitForExistence(timeout:5))
        app.textFields["leftScore"].tap()
        app.textFields["leftScore"].typeText("777000")
        app.textFields["rightScore"].tap()
        app.textFields["rightScore"].typeText("888000")
        app.buttons["saveGame"].tap()
        waitLabel(current(app),contains:"Game 4. Andreas turn")
        XCTAssertEqual(app.buttons["pauseMonitoring"].label,"Resume scanning")
        app.buttons["pauseMonitoring"].tap()
        app.buttons["resyncTracking"].tap()
        waitLabel(current(app),contains:"Game 4. Fredrik turn")
        XCTAssertFalse(app.buttons["cancelResync"].exists)
        screenshot("iPhone11Pro-manual-add-resume")
    }

    func testRecordedSwitchWithCameraRunning() {
        let app = launch("recorded")
        waitLabel(current(app),contains:"Game 3. Andreas turn",timeout:25)
        XCTAssertTrue(app.staticTexts["fixtureReplayComplete"].waitForExistence(timeout:45))
        screenshot("iPhone11Pro-recorded-reader-performance")
        XCTAssertFalse(app.buttons["cancelResync"].exists)
    }
}
