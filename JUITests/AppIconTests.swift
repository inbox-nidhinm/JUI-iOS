import XCTest
@testable import JUI

// Every theme must have an icon that actually shipped in the bundle, or
// switching to it fails quietly and the home screen keeps the old one.
final class AppIconTests: XCTestCase {
    func testEveryThemeMapsToAShippedIcon() throws {
        let icons = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let alternates = (icons["CFBundleAlternateIcons"] as? [String: Any]) ?? [:]
        for theme in Themes.all {
            if let name = AppIcon.name(for: theme) {
                XCTAssertNotNil(alternates[name], "\(theme.id) has no alternate icon \(name)")
            } else {
                XCTAssertEqual(theme.id, Themes.cream.id, "only cream uses the primary icon")
            }
        }
        XCTAssertEqual(alternates.count, Themes.all.count - 1)
    }
}
