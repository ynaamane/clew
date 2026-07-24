import XCTest
@testable import OwnscribeMenuBar

final class HotKeyComboTests: XCTestCase {
    func testDefaultIsCommandShiftM() {
        let combo = HotKeyCombo.defaultMuteToggle

        XCTAssertEqual(combo.keyCode, 0x2E) // kVK_ANSI_M
        XCTAssertTrue(combo.modifiers.contains(.command))
        XCTAssertTrue(combo.modifiers.contains(.shift))
        XCTAssertFalse(combo.modifiers.contains(.option))
        XCTAssertFalse(combo.modifiers.contains(.control))
    }

    func testCarbonModifierMaskCombinesCommandAndShift() {
        let combo = HotKeyCombo.defaultMuteToggle
        XCTAssertEqual(combo.carbonModifierMask, HotKeyModifiers.commandCarbonFlag | HotKeyModifiers.shiftCarbonFlag)
    }

    func testEquatableComparesKeyCodeAndModifiers() {
        let a = HotKeyCombo(keyCode: 0x2E, modifiers: [.command, .shift])
        let b = HotKeyCombo(keyCode: 0x2E, modifiers: [.shift, .command])
        let c = HotKeyCombo(keyCode: 0x2E, modifiers: [.command])

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
