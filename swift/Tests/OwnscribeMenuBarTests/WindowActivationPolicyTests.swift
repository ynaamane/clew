import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class WindowActivationPolicyTests: XCTestCase {
    func testOpeningAWindowLeavesAccessoryModeSoItCanTakeFocus() {
        let policy = WindowActivationPolicy(applyPolicy: { _ in })
        policy.windowDidOpen()

        XCTAssertEqual(
            policy.desiredPolicy, .regular,
            "An LSUIElement app stays .accessory, where a window cannot take keyboard focus properly; opening one must switch to .regular")
    }

    func testClosingTheLastWindowReturnsToAccessory() {
        let policy = WindowActivationPolicy(applyPolicy: { _ in })
        policy.windowDidOpen()
        policy.windowDidClose()

        XCTAssertEqual(
            policy.desiredPolicy, .accessory,
            "With no window left the app must go back to being a menu bar extra with no Dock icon")
    }

    func testClosingOneOfSeveralWindowsStaysRegular() {
        let policy = WindowActivationPolicy(applyPolicy: { _ in })
        policy.windowDidOpen()
        policy.windowDidOpen()

        policy.windowDidClose()

        XCTAssertEqual(policy.desiredPolicy, .regular)
    }

    func testCloseWithoutOpenNeverDrivesTheCountNegative() {
        let policy = WindowActivationPolicy(applyPolicy: { _ in })
        policy.windowDidClose()
        policy.windowDidClose()
        policy.windowDidOpen()

        XCTAssertEqual(
            policy.desiredPolicy, .regular,
            "A stray close must not leave the counter negative, or a later open would fail to switch to .regular")
    }
}
