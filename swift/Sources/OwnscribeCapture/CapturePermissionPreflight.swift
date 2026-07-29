import AVFoundation
import CoreGraphics
import Foundation

public func preflightScreenCaptureAccess() -> Bool {
    CGPreflightScreenCaptureAccess()
}

public func microphoneAccessIsAuthorized(status: AVAuthorizationStatus) -> Bool {
    status == .authorized
}

public func microphoneAccessNeedsPrompting(status: AVAuthorizationStatus) -> Bool {
    status == .notDetermined
}

public func preflightMicrophoneAccess() -> Bool {
    microphoneAccessIsAuthorized(status: AVCaptureDevice.authorizationStatus(for: .audio))
}

public func requestMicrophoneAccessIfUnanswered() async -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    guard microphoneAccessNeedsPrompting(status: status) else {
        return microphoneAccessIsAuthorized(status: status)
    }
    return await AVCaptureDevice.requestAccess(for: .audio)
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

public func runCoreAudioTapPermissionPreflight(
    needsMic: Bool,
    hasScreenCaptureAccess: Bool = preflightScreenCaptureAccess(),
    hasMicrophoneAccess: Bool = preflightMicrophoneAccess()
) -> Bool {
    var ok = true

    if !hasScreenCaptureAccess {
        ok = false
        fputs("""
        [PERMISSION_MISSING] System Audio Recording permission is not granted.
        System audio capture will fail or record silence.
        Fix: open x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture
        Enable your terminal app under "System Audio Recording Only", then restart it.
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
