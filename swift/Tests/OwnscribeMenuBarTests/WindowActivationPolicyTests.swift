import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class WindowActivationPolicyTests: XCTestCase {
    override func setUp() {
        WindowActivationPolicy.resetForTesting()
    }

    override func tearDown() {
        WindowActivationPolicy.resetForTesting()
    }

    func testOpeningAWindowLeavesAccessoryModeSoItCanTakeFocus() {
        WindowActivationPolicy.windowDidOpen()

        XCTAssertEqual(
            WindowActivationPolicy.desiredPolicy, .regular,
            "An LSUIElement app stays .accessory, where a window cannot take keyboard focus properly; opening one must switch to .regular")
    }

    func testClosingTheLastWindowReturnsToAccessory() {
        WindowActivationPolicy.windowDidOpen()
        WindowActivationPolicy.windowDidClose()

        XCTAssertEqual(
            WindowActivationPolicy.desiredPolicy, .accessory,
            "With no window left the app must go back to being a menu bar extra with no Dock icon")
    }

    func testClosingOneOfSeveralWindowsStaysRegular() {
        WindowActivationPolicy.windowDidOpen()
        WindowActivationPolicy.windowDidOpen()

        WindowActivationPolicy.windowDidClose()

        XCTAssertEqual(WindowActivationPolicy.desiredPolicy, .regular)
    }

    func testCloseWithoutOpenNeverDrivesTheCountNegative() {
        WindowActivationPolicy.windowDidClose()
        WindowActivationPolicy.windowDidClose()
        WindowActivationPolicy.windowDidOpen()

        XCTAssertEqual(
            WindowActivationPolicy.desiredPolicy, .regular,
            "A stray close must not leave the counter negative, or a later open would fail to switch to .regular")
    }
}
