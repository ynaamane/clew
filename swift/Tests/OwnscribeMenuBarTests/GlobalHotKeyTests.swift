import XCTest
@testable import OwnscribeMenuBar

final class HotKeyComboTests: XCTestCase {
    func testDefaultIsCommandShiftM() {
        let combo = HotKeyCombo.defaultMuteToggle

        XCTAssertEqual(combo.keyCode, HotKeyCombo.kVK_ANSI_M)
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
        let a = HotKeyCombo(keyCode: HotKeyCombo.kVK_ANSI_M, modifiers: [.command, .shift])
        let b = HotKeyCombo(keyCode: HotKeyCombo.kVK_ANSI_M, modifiers: [.shift, .command])
        let c = HotKeyCombo(keyCode: HotKeyCombo.kVK_ANSI_M, modifiers: [.command])

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
