import Carbon.HIToolbox
import Foundation

public struct HotKeyModifiers: OptionSet, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = HotKeyModifiers(rawValue: 1 << 0)
    public static let shift = HotKeyModifiers(rawValue: 1 << 1)
    public static let option = HotKeyModifiers(rawValue: 1 << 2)
    public static let control = HotKeyModifiers(rawValue: 1 << 3)

    static let commandCarbonFlag: UInt32 = 0x0100
    static let shiftCarbonFlag: UInt32 = 0x0200
    static let optionCarbonFlag: UInt32 = 0x0800
    static let controlCarbonFlag: UInt32 = 0x1000
}

public struct HotKeyCombo: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: HotKeyModifiers

    public init(keyCode: UInt32, modifiers: HotKeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let defaultMuteToggle = HotKeyCombo(keyCode: 0x2E, modifiers: [.command, .shift]) // kVK_ANSI_M

    public var carbonModifierMask: UInt32 {
        var mask: UInt32 = 0
        if modifiers.contains(.command) { mask |= HotKeyModifiers.commandCarbonFlag }
        if modifiers.contains(.shift) { mask |= HotKeyModifiers.shiftCarbonFlag }
        if modifiers.contains(.option) { mask |= HotKeyModifiers.optionCarbonFlag }
        if modifiers.contains(.control) { mask |= HotKeyModifiers.controlCarbonFlag }
        return mask
    }
}

@MainActor
public final class GlobalHotKeyRegistration {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onPress: (() -> Void)?

    public init() {}

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    public func register(_ combo: HotKeyCombo, onPress: @escaping () -> Void) -> Bool {
        self.onPress = onPress

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData, let eventRef else { return noErr }
                let registration = Unmanaged<GlobalHotKeyRegistration>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                registration.onPress?()
                return noErr
            },
            1, &eventType, selfPointer, &eventHandler)

        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x6F776D75), id: 1) // 'owmu'
        let registerStatus = RegisterEventHotKey(
            combo.keyCode, combo.carbonModifierMask, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef)

        return registerStatus == noErr
    }

    public func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        onPress = nil
    }
}
