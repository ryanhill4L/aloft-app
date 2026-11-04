import XCTest
@testable import Aloft

/// Window sizes the Duo and a normal iPhone actually present. The keyboard
/// inset is not one of these: feeding that shorter height to `PaneSplit` turns
/// an unfolded portrait window into `.single` and dismisses the keyboard.
final class PaneSplitTests: XCTestCase {
    func testFoldedDuoAndPhonePortraitAreOneColumn() {
        XCTAssertEqual(PaneSplit(CGSize(width: 466, height: 678)), .single)
        XCTAssertEqual(PaneSplit(CGSize(width: 402, height: 874)), .single)
    }

    func testUnfoldedLandscapeIsSideBySide() {
        XCTAssertEqual(PaneSplit(CGSize(width: 951, height: 669)), .sideBySide)
    }

    func testUnfoldedPortraitIsStacked() {
        XCTAssertEqual(PaneSplit(CGSize(width: 669, height: 951)), .stacked)
    }

    func testKeyboardShrunkUnfoldedPortraitIsNotTheWindowSize() {
        XCTAssertEqual(PaneSplit(CGSize(width: 669, height: 580)), .single)
    }
}
