import XCTest

// Focused checks for the sticky card, the folder-name field and theme
// changes, with a screenshot at each step. Runs from any state: onboarding is
// passed through if it shows.
final class StickyAndFolderTests: XCTestCase {
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

    func testStickyButtonsFolderFieldAndTheme() {
        // A theme first, so a stale colour would show: mint, then back to home.
        tap("Settings"); pause(0.8)
        tap("mint"); pause(0.6)
        tap("Close settings"); pause(1.0)
        shot("a1-home-after-mint")

        // An unnamed folder field goes away when you tap elsewhere.
        tap("New folder"); pause(0.8)
        XCTAssertEqual(app.textFields.count, 1)
        shot("a2-folder-field-open")
        app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'notes'")).firstMatch.tap()
        pause(1.0)
        XCTAssertEqual(app.textFields.count, 0, "unnamed folder field should be gone")
        shot("a3-folder-field-cancelled")

        // An empty folder: the back row and "no notes yet" sit at the left.
        tap("New folder"); pause(0.8)
        app.typeText("empty\n"); pause(1.0)
        tap("empty"); pause(1.0)
        shot("a3b-empty-folder")
        let width = app.windows.firstMatch.frame.width
        let heading = app.staticTexts["empty"].firstMatch
        XCTAssertLessThan(heading.frame.minX, width * 0.25, "the folder's name should start at the left")
        let empty = app.staticTexts["no notes yet"].firstMatch
        XCTAssertTrue(empty.exists)
        XCTAssertLessThan(empty.frame.minX, width * 0.25, "\"no notes yet\" should start at the left")
        tap("Home"); pause(1.0)

        // A note with a long sticky.
        tap("New note"); pause(1.2)
        let page = app.textViews.firstMatch
        page.typeText("A short note for the sticky to sit on.")
        page.doubleTap(); pause(1.2)
        let make = app.menuItems["Sticky Note"].exists ? app.menuItems["Sticky Note"] : app.buttons["Sticky Note"]
        XCTAssertTrue(make.waitForExistence(timeout: 3))
        make.tap(); pause(1.0)
        // New: straight to writing, so the buttons show.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))
        app.typeText("remember to buy more of the good paper, the heavy cream one from the shop by the station.\nand envelopes.\nand a new nib for the blue pen, the fine one.\nask about the green ink too.\nand stamps.")
        pause(2.6)
        shot("a4-sticky-new-editing")
        tap("Done"); pause(0.8)
        if app.keyboards.count > 0 { page.swipeDown(velocity: .fast); pause(0.8) }

        // Reopened to read: whole, no keyboard, no buttons.
        tap("Sticky note"); pause(1.2)
        shot("a5-sticky-reading")
        XCTAssertEqual(app.keyboards.count, 0, "reading a sticky should not raise the keyboard")
        XCTAssertFalse(app.buttons["Done"].exists, "buttons should be hidden while reading")

        // Tap into the text: editing, buttons back.
        app.textViews["sticky-text"].tap(); pause(1.2)
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 2))
        shot("a6-sticky-editing-again")
        tap("Done"); pause(0.8)
    }
}
