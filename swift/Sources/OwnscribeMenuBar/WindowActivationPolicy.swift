import AppKit

@MainActor
public final class WindowActivationPolicy {
    private var openWindows = 0
    private let applyPolicy: (NSApplication.ActivationPolicy) -> Void

    public static let shared = WindowActivationPolicy()

    public init(applyPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { policy in
        guard NSApplication.shared.activationPolicy() != policy else { return }
        NSApplication.shared.setActivationPolicy(policy)
    }) {
        self.applyPolicy = applyPolicy
    }

    public var desiredPolicy: NSApplication.ActivationPolicy {
        openWindows > 0 ? .regular : .accessory
    }

    public func windowDidOpen() {
        openWindows += 1
        apply()
    }

    public func windowDidClose() {
        openWindows = max(0, openWindows - 1)
        apply()
    }

    private func apply() {
        applyPolicy(desiredPolicy)
    }
}
