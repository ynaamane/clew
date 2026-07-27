import AppKit

@MainActor
public struct WindowActivationPolicy {
    private static var openWindows = 0

    public static var desiredPolicy: NSApplication.ActivationPolicy {
        openWindows > 0 ? .regular : .accessory
    }

    public static func windowDidOpen() {
        openWindows += 1
        apply()
    }

    public static func windowDidClose() {
        openWindows = max(0, openWindows - 1)
        apply()
    }

    static func resetForTesting() {
        openWindows = 0
    }

    private static func apply() {
        let policy = desiredPolicy
        guard NSApplication.shared.activationPolicy() != policy else { return }
        NSApplication.shared.setActivationPolicy(policy)
    }
}
