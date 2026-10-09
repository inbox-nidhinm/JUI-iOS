import XCTest

// Reproduces the page jumping behind an opening sticky: screenshots of the
// page before, while and after a sticky opens and closes.
final class CrumpleJumpTests: XCTestCase {
    private let app = XCUIApplication()

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testPageHoldsStillBehindASticky() {
        continueAfterFailure = false
        app.launch()
        if app.buttons["begin"].waitForExistence(timeout: 3) {
            app.buttons["begin"].tap(); sleep(1)
            if app.buttons["Continue"].waitForExistence(timeout: 1.5) { app.buttons["Continue"].tap() }
            app.typeText("Juilee\n"); sleep(1)
            app.buttons["next"].firstMatch.tap(); sleep(3)
        }
        app.buttons["New note"].firstMatch.tap(); sleep(1)
        let page = app.textViews.firstMatch
        page.typeText("Dear diary,\n\nThe first page of a new notebook always feels like a promise, written in brown ink on cream paper")
        page.doubleTap(); sleep(1) // selects the last word, "paper"
        let make = app.menuItems["Sticky Note"].exists ? app.menuItems["Sticky Note"] : app.buttons["Sticky Note"]
        XCTAssertTrue(make.waitForExistence(timeout: 3))
        make.tap(); sleep(2)
        app.typeText("remember the good paper")
        app.buttons["Done"].firstMatch.tap(); sleep(2)
        shot("j0a-ball-at-end")
        // The sentence carries on after the ball.
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap(); sleep(1)
        page.typeText(" from the shop by the station.\n\nAnd that is enough for today.")
        shot("j0b-typing-after")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap(); sleep(1)
        if app.keyboards.firstMatch.exists { page.swipeDown(velocity: .fast); sleep(1) }
        shot("j0-before")

        let ball = app.buttons["Sticky note"].firstMatch
        XCTAssertTrue(ball.waitForExistence(timeout: 3))
        ball.tap()
        shot("j1-opening")
        Thread.sleep(forTimeInterval: 0.4); shot("j2-opening")
        Thread.sleep(forTimeInterval: 1.2); shot("j3-open")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        shot("j4-closing")
        Thread.sleep(forTimeInterval: 0.4); shot("j5-closing")
        Thread.sleep(forTimeInterval: 1.2); shot("j6-closed")
    }
}
