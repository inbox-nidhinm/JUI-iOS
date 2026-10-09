import XCTest
@testable import JUI

// The smooth caret depends on UIKit exposing the text view's display
// interaction. If a future iOS stops doing that, the app quietly falls back to
// the system caret — so this is the test that notices.
final class SmoothCaretTests: XCTestCase {
    private var window: UIWindow!

    override func setUp() {
        super.setUp()
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
    }

    override func tearDown() {
        window.isHidden = true
        window = nil
        super.tearDown()
    }

    private func makeEditor(_ text: String) -> CaretTextView {
        let tv = CaretTextView(frame: window.bounds)
        tv.attributedText = NSAttributedString(string: text, attributes: Style.base)
        window.rootViewController!.view.addSubview(tv)
        tv.becomeFirstResponder()
        // let the focus settle and the async caret update run
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return tv
    }

    func testSystemCaretIsReplacedAndHouseCaretShows() {
        let tv = makeEditor("hello there")
        XCTAssertTrue(tv.isFirstResponder)
        XCTAssertTrue(tv.smoothCaret.isActive, "system caret was not swapped out")
        XCTAssertFalse(tv.smoothCaret.layer.isHidden)
        XCTAssertEqual(tv.smoothCaret.layer.frame.width, 2)
    }

    func testMovingTheCaretGlidesRatherThanJumps() {
        let tv = makeEditor("hello there")
        tv.selectedRange = NSRange(location: 0, length: 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let before = tv.smoothCaret.layer.frame
        tv.selectedRange = NSRange(location: 5, length: 0)
        let keys = tv.smoothCaret.layer.animationKeys() ?? []
        XCTAssertTrue(keys.contains("position"), "expected a glide, got \(keys)")
        XCTAssertGreaterThan(tv.smoothCaret.layer.frame.minX, before.minX)
    }

    func testCaretHidesForARangeSelectionAndWhenNotFocused() {
        let tv = makeEditor("hello there")
        tv.selectedRange = NSRange(location: 0, length: 5)
        XCTAssertTrue(tv.smoothCaret.layer.isHidden)
        tv.selectedRange = NSRange(location: 2, length: 0)
        XCTAssertFalse(tv.smoothCaret.layer.isHidden)
        tv.resignFirstResponder()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(tv.smoothCaret.layer.isHidden)
    }

    func testNoteEditorCaretIsSizedOffTheInk() {
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(lm)
        lm.addTextContainer(container)
        let tv = RuledTextView(frame: window.bounds, textContainer: container)
        tv.textContainerInset = UIEdgeInsets(top: Style.topInset, left: Style.sideMargin,
                                             bottom: 0, right: Style.sideMargin)
        storage.setAttributedString(NSAttributedString(string: "one\ntwo", attributes: Style.base))
        window.rootViewController!.view.addSubview(tv)
        tv.becomeFirstResponder()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(tv.smoothCaret.layer.frame.height,
                       Style.inkHeight + Style.caretOvershoot * 2, accuracy: 0.5)
    }
}
