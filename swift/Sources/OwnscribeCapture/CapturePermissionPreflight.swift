import AVFoundation
import CoreGraphics
import Foundation

public func preflightScreenCaptureAccess() -> Bool {
    CGPreflightScreenCaptureAccess()
}

public func preflightMicrophoneAccess() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
}

public func runCapturePermissionPreflight(
    needsMic: Bool,
    hasScreenCaptureAccess: Bool = preflightScreenCaptureAccess(),
    hasMicrophoneAccess: Bool = preflightMicrophoneAccess()
) -> Bool {
    var ok = true

    if !hasScreenCaptureAccess {
        ok = false
        fputs("""
        [PERMISSION_MISSING] Screen Recording permission is not granted.
        System audio capture will fail or record silence.
        Fix: open x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture
        Enable your terminal app, then restart it.
        """, stderr)
        fputs("\n", stderr)
    }

    if needsMic && !hasMicrophoneAccess {
        ok = false
        fputs("""
        [PERMISSION_MISSING] Microphone permission is not granted.
        Mic capture will fail or record silence.
        Fix: open x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone
        Enable your terminal app, then restart it.
        """, stderr)
        fputs("\n", stderr)
    }

    return ok
}
