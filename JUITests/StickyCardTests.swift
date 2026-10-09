import XCTest
@testable import JUI

// The sticky card sizes itself from this measurement, so it has to grow with
// the text: more lines, more height, at 140% leading.
final class StickyCardTests: XCTestCase {
    func testHeightGrowsWithWrappedLines() {
        let line = (StickyTextView.textSize * StickyTextView.leading).rounded()
        let pad = StickyTextView.inset.top + StickyTextView.inset.bottom
        let one = StickyTextView.height(of: "short", width: 240)
        XCTAssertEqual(one, line + pad, accuracy: 1)
        let long = String(repeating: "remember to buy more of the good paper ", count: 4)
        let wrapped = StickyTextView.height(of: long, width: 240)
        XCTAssertGreaterThan(wrapped, line * 4 + pad - 1)
        let lines = StickyTextView.height(of: "a\nb\nc", width: 240)
        XCTAssertEqual(lines, line * 3 + pad, accuracy: 1)
    }
}
