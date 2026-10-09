import XCTest

// Walks through the app the way someone would on first launch, saving a
// screenshot at each stop so the result can be looked at. It asserts only that
// each place can be reached; whether it looks right is judged from the images.
//
// Run with a fresh install (the walkthrough starts at onboarding) and
// TEST_RUNNER_SHOTS_DIR set to a folder on the host:
//
//   xcrun simctl uninstall booted com.nidhin.jui.ios
//   TEST_RUNNER_SHOTS_DIR=/tmp/shots xcodebuild test -only-testing:JUIUITests ...
final class WalkthroughTests: XCTestCase {
    private let app = XCUIApplication()
    private var shots: URL?

    override func setUp() {
        continueAfterFailure = false
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            shots = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: shots!, withIntermediateDirectories: true)
        }
        app.launch()
    }

    private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        if let shots { try? png.write(to: shots.appendingPathComponent("\(name).png")) }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Taps the button with this label, failing fast — rather than waiting out
    /// XCTest's long default — if it isn't there.
    private func tap(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[label].firstMatch
        guard button.waitForExistence(timeout: 5) else {
            XCTFail("no button labelled \"\(label)\"", file: file, line: line)
            return
        }
        button.tap()
    }

    private func dismissKeyboard() {
        guard app.keyboards.count > 0 else { return }
        app.textViews.firstMatch.swipeDown(velocity: .fast)
        pause(0.8)
    }

    func testWalkthrough() throws {
        // Onboarding
        XCTAssertTrue(app.buttons["begin"].waitForExistence(timeout: 8))
        pause(1)
        tap("begin")
        pause(0.8)
        // The simulator's one-time keyboard tip, if it shows.
        if app.buttons["Continue"].waitForExistence(timeout: 1.5) { app.buttons["Continue"].tap() }
        app.typeText("Juilee")
        pause(0.4)
        app.typeText("\n") // Return submits; the keyboard's own key is also "next"
        pause(0.8)
        tap("next")
        pause(2.4)
        shot("01-home-empty")

        // A new note opens with the keyboard up
        tap("New note")
        pause(1.2)
        let page = app.textViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 4))
        page.typeText("Dear diary\nThe first page of a new notebook always feels like a promise, written in brown ink on cream paper.\n- tea\nletters\na walk\n\nAnd that is enough for today.")
        pause(0.8)
        shot("02-note-writing")

        // A sticky on the last word: opens with the keyboard, being new
        page.doubleTap()
        pause(1.2)
        let sticky = app.menuItems["Sticky Note"].exists ? app.menuItems["Sticky Note"] : app.buttons["Sticky Note"]
        XCTAssertTrue(sticky.waitForExistence(timeout: 3))
        sticky.tap()
        pause(1.0)
        app.typeText("remember to buy more of the good paper, the heavy cream one from the shop by the station.\nand envelopes.\nand a new nib for the blue pen, the fine one.\nask about the green ink too.")
        pause(3.0)
        shot("03-sticky-new-keyboard")
        tap("Done")
        pause(0.8)
        dismissKeyboard()
        pause(0.6)
        shot("04-note-wash-and-stamp")

        // Reopened, it shows whole, with no keyboard
        tap("Sticky note")
        pause(1.2)
        shot("05-sticky-reopened")
        tap("Done")
        pause(0.8)

        // Back home
        tap("Home")
        pause(1.2)
        shot("06-home-with-note")

        // A folder
        tap("New folder")
        pause(0.6)
        app.typeText("letters\n")
        pause(1.0)
        shot("07-home-with-folder")
        tap("letters")
        pause(1.0)
        shot("08-folder-empty")
        tap("letters") // the back row carries the folder's name
        pause(1.0)

        // Search
        tap("Search")
        pause(1.0)
        app.typeText("promise")
        pause(0.8)
        shot("09-search")
        app.typeText("\n") // opens the top hit
        pause(1.6)
        shot("10-search-revealed")
        dismissKeyboard()
        tap("Home")
        pause(1.0)

        // The hidden page
        tap("Settings")
        pause(1.0)
        shot("11-settings")
        tap("mint")
        pause(0.8)
        tap("Close settings")
        pause(1.0)
        shot("12-home-mint")
    }
}
