import XCTest

@MainActor
final class PlaygroundUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRunReplayAndTrace() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["run-button"].tap()
        let replay = app.buttons["replay-button"]
        waitUntilEnabled(replay)
        app.swipeUp()
        let output = app.staticTexts["output-0"]
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        XCTAssertEqual(output.label, "The computer would like more context. Relatable.")
        let original = output.label
        if !replay.isHittable { app.swipeDown() }
        replay.tap()
        XCTAssertTrue(app.staticTexts["run-status"].waitForExistence(timeout: 5))
        let replayStatus = NSPredicate(format: "label == %@", "Replayed · no model calls")
        expectation(for: replayStatus, evaluatedWith: app.staticTexts["run-status"])
        waitForExpectations(timeout: 5)
        XCTAssertEqual(output.label, original)
        app.swipeUp()
        app.descendants(matching: .any)["trace-disclosure"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Simulated scores · not calibrated probabilities"].waitForExistence(timeout: 5))
        attachScreenshot("Replay and simulated trace", app: app)
    }

    func testStopPreventsLateOutput() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-slow-provider"]
        app.launch()
        app.buttons["run-button"].tap()
        app.buttons["run-button"].tap()
        app.swipeUp()
        XCTAssertEqual(app.staticTexts["run-status"].label, "Stopped")
        XCTAssertFalse(app.buttons["replay-button"].isEnabled)
        XCTAssertFalse(app.staticTexts["output-0"].exists)
        attachScreenshot("Cancelled run", app: app)
    }

    func testParserErrorIsReadable() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-invalid-source"]
        app.launch()
        app.buttons["run-button"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["run-error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["replay-button"].isEnabled)
        attachScreenshot("Parser error", app: app)
    }

    func testLargeTextCanRun() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let run = app.buttons["run-button"]
        for _ in 0..<5 where !run.isHittable { app.swipeUp() }
        XCTAssertTrue(run.isHittable)
        run.tap()
        waitUntilEnabled(app.buttons["replay-button"])
        let output = app.staticTexts["output-0"]
        // Native List creates offscreen rows lazily. At accessibility sizes,
        // scroll until the result is reachable rather than assuming one swipe.
        for _ in 0..<8 where !output.isHittable { app.swipeUp() }
        XCTAssertTrue(output.isHittable)
        // Verify the output remains reachable while revealing the following actions.
        app.swipeUp()
        XCTAssertTrue(output.isHittable)
        attachScreenshot("Accessibility large text", app: app)
    }

    func testNativeSourceEditor() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Maybe"].exists)
        attachScreenshot("Native light appearance", app: app)
        app.buttons["source-disclosure"].tap()
        XCTAssertTrue(app.textViews["source-editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["inbox.prob"].exists)
        attachScreenshot("Native source editor", app: app)
        let done = app.buttons["source-done"]
        XCTAssertTrue(done.isHittable)
        // iOS 27 XCTest may try to scroll this button after its first tap already
        // dismisses the sheet. Tap its observed center without that scroll retry.
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["run-button"].isHittable)
    }

    func testDarkAppearanceCanRun() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-dark"]
        app.launch()
        attachScreenshot("Native dark appearance", app: app)
        app.buttons["run-button"].tap()
        waitUntilEnabled(app.buttons["replay-button"])
        app.swipeUp()
        XCTAssertEqual(app.staticTexts["output-0"].label, "The computer would like more context. Relatable.")
        attachScreenshot("Native dark result", app: app)
    }

    func testJevKeySetupAndForgetWithoutNetworking() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["model-settings"].tap()
        XCTAssertTrue(app.buttons["use-jev"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["use-jev"].isEnabled)
        attachScreenshot("JEV connection settings", app: app)
        let key = app.secureTextFields["jev-api-key"]
        key.tap()
        key.typeText("ui-test-placeholder-not-a-real-key")
        app.buttons["use-jev"].tap()
        XCTAssertTrue(app.buttons["model-settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["JEV"].exists)
        app.buttons["model-settings"].tap()
        // Existing credentials are never copied back into the editor.
        XCTAssertEqual(app.secureTextFields["jev-api-key"].value as? String, "TypeSafe API key")
        app.buttons["forget-jev-key"].tap()
        XCTAssertTrue(app.staticTexts["Demo"].exists)
        app.buttons["run-button"].tap()
        waitUntilEnabled(app.buttons["replay-button"])
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["output-0"].exists)
    }

    private func waitUntilEnabled(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: element)
        waitForExpectations(timeout: 10)
    }

    private func attachScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
