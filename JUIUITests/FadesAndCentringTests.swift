import XCTest

// Screenshots for the scroll fades on a long note and a long sticky, and for
// where a sticky sits when it is opened to read.
final class FadesAndCentringTests: XCTestCase {
    private let app = XCUIApplication()
    private var shots: URL?

    override func setUp() {
        continueAfterFailure = false
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            shots = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: shots!, withIntermediateDirectories: true)
        }
        app.launch()
        if app.buttons["begin"].waitForExistence(timeout: 3) {
            app.buttons["begin"].tap()
            Thread.sleep(forTimeInterval: 0.8)
            if app.buttons["Continue"].waitForExistence(timeout: 1.5) { app.buttons["Continue"].tap() }
            app.typeText("Juilee\n")
            Thread.sleep(forTimeInterval: 0.8)
            app.buttons["next"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 2.4)
        }
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        if let shots { try? png.write(to: shots.appendingPathComponent("\(name).png")) }
    }

    private func pause(_ s: TimeInterval) { Thread.sleep(forTimeInterval: s) }

    private func tap(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let b = app.buttons[label].firstMatch
        guard b.waitForExistence(timeout: 5) else {
            XCTFail("no button \"\(label)\"", file: file, line: line); return
        }
        b.tap()
    }

    func testFadesAndCentring() {
        tap("New note"); pause(1.2)
        let page = app.textViews.firstMatch
        let lines = (1...24).map { "Line \($0) of a long letter." }.joined(separator: "\n")
        page.typeText("A long letter\n" + lines)
        pause(0.6)

        // A sticky on the last word, with more on it than the screen holds.
        page.doubleTap(); pause(1.2)
        let make = app.menuItems["Sticky Note"].exists ? app.menuItems["Sticky Note"] : app.buttons["Sticky Note"]
        XCTAssertTrue(make.waitForExistence(timeout: 3))
        make.tap(); pause(1.0)
        app.typeText((1...40).map { "thought \($0)" }.joined(separator: "\n"))
        pause(1.0)
        tap("Done"); pause(0.8)
        if app.keyboards.count > 0 { page.swipeDown(velocity: .fast); pause(0.8) }

        // The note at its end: a fade at the top only.
        shot("f1-note-at-end")
        // Into the middle: fades at both ends.
        page.swipeDown(velocity: .slow); pause(1.0)
        shot("f2-note-middle")
        // At its start: a fade at the foot only.
        for _ in 0..<4 { page.swipeDown(velocity: .fast) }
        pause(1.0)
        shot("f3-note-at-start")

        // Back to the sticky: opened to read, centred, scrolling inside.
        for _ in 0..<4 { page.swipeUp(velocity: .fast) }
        pause(1.0)
        tap("Sticky note"); pause(1.2)
        shot("f4-sticky-reading-long")
        let sticky = app.textViews["sticky-text"]
        XCTAssertTrue(sticky.waitForExistence(timeout: 3))
        // Below the status bar — 59pt on the test's iPhone 15 Pro; tests
        // can't query it. The text sits 18pt into the stamp, which sits at
        // least 20pt below the bar.
        let statusBar: CGFloat = 59
        XCTAssertGreaterThan(sticky.frame.minY, max(statusBar, 47) + 20,
                             "a tall sticky reached up under the status bar")
        sticky.swipeUp(velocity: .slow); pause(1.0)
        shot("f5-sticky-scrolled")

        // Tapped to edit: keyboard up, the whole stamp between it and the bar.
        sticky.tap(); pause(1.5)
        shot("f5b-sticky-editing-long")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let keyboardTop = app.keyboards.firstMatch.frame.minY
        XCTAssertGreaterThan(sticky.frame.minY, max(statusBar, 47) + 20,
                             "editing pushed the sticky up under the status bar")
        XCTAssertLessThan(sticky.frame.maxY, keyboardTop,
                          "editing left the sticky under the keyboard")
        XCTAssertTrue(app.buttons["Done"].isHittable, "done should be reachable above the keyboard")
        tap("Done"); pause(0.8)
        if app.keyboards.count > 0 { page.swipeDown(velocity: .fast); pause(0.8) }

        // A short sticky, opened to read: should sit in the middle.
        page.doubleTap(); pause(1.2)
        let again = app.menuItems["Sticky Note"].exists ? app.menuItems["Sticky Note"] : app.buttons["Sticky Note"]
        if again.waitForExistence(timeout: 3) {
            again.tap(); pause(1.0)
            app.typeText("a short one")
            tap("Done"); pause(0.8)
            if app.keyboards.count > 0 { page.swipeDown(velocity: .fast); pause(0.8) }
            app.buttons.matching(identifier: "Sticky note").element(boundBy: 1).tap()
            pause(1.2)
            shot("f6-sticky-short-reading")
        }
    }
}
