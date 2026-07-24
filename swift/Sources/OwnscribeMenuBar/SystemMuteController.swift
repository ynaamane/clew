import CoreAudio
import Foundation

public protocol AudioMuteDevice {
    func isBluetooth() -> Bool
    func setInputMute(_ muted: Bool) -> Bool
    func readInputMute() -> Bool?
    func nominalSampleRate() -> Double?
}

private let a2dpSampleRateThreshold: Double = 44100

public func waitForBluetoothHFPSettling(
    device: AudioMuteDevice,
    maxPolls: Int = 30,
    sleep: () -> Void
) {
    guard device.isBluetooth() else { return }

    for _ in 0..<maxPolls {
        if let rate = device.nominalSampleRate(), rate < a2dpSampleRateThreshold {
            return
        }
        sleep()
    }
}

public struct SystemMuteResult: Equatable {
    public let requestedMuted: Bool
    public let succeeded: Bool
    public let verifiedMuted: Bool
    public let isBluetoothDevice: Bool

    public init(requestedMuted: Bool, succeeded: Bool, verifiedMuted: Bool, isBluetoothDevice: Bool) {
        self.requestedMuted = requestedMuted
        self.succeeded = succeeded
        self.verifiedMuted = verifiedMuted
        self.isBluetoothDevice = isBluetoothDevice
    }
}

public func setSystemMuteVerified(_ muted: Bool, device: AudioMuteDevice) -> SystemMuteResult {
    let isBluetoothDevice = device.isBluetooth()
    let setCallSucceeded = device.setInputMute(muted)
    let readBack = device.readInputMute()

    let verified = setCallSucceeded && readBack == muted
    return SystemMuteResult(
        requestedMuted: muted,
        succeeded: verified,
        verifiedMuted: verified ? muted : false,
        isBluetoothDevice: isBluetoothDevice
    )
}

public struct MasterMuteOutcome: Equatable {
    public let displayMuted: Bool
    public let usedLocalFallback: Bool
    public let warning: String?

    public init(displayMuted: Bool, usedLocalFallback: Bool, warning: String?) {
        self.displayMuted = displayMuted
        self.usedLocalFallback = usedLocalFallback
        self.warning = warning
    }
}

public func applyMasterMute(
    _ muted: Bool,
    device: AudioMuteDevice,
    settle: (AudioMuteDevice) -> Void = { waitForBluetoothHFPSettling(device: $0) { Thread.sleep(forTimeInterval: 0.1) } },
    localFallback: (Bool) -> Void
) -> MasterMuteOutcome {
    settle(device)
    let systemResult = setSystemMuteVerified(muted, device: device)

    guard systemResult.succeeded else {
        localFallback(muted)
        let bluetoothNote = systemResult.isBluetoothDevice
            ? " (Bluetooth mic mute is known to be unreliable on some macOS versions)"
            : ""
        let warning = muted
            ? "Couldn't mute the microphone system-wide\(bluetoothNote) — the recording is muted, but the call itself may not be. Mute manually in your call app too."
            : "Couldn't unmute the microphone system-wide\(bluetoothNote) — check your call app's mute state manually."
        return MasterMuteOutcome(displayMuted: muted, usedLocalFallback: true, warning: warning)
    }

    return MasterMuteOutcome(displayMuted: systemResult.verifiedMuted, usedLocalFallback: false, warning: nil)
}

public final class DefaultInputAudioMuteDevice: AudioMuteDevice {
    public init() {}

    private func resolveDefaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return (status == noErr && deviceID != kAudioObjectUnknown) ? deviceID : nil
    }

    public func isBluetooth() -> Bool {
        guard let deviceID = resolveDefaultInputDeviceID() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transportType)
        guard status == noErr else { return false }
        return transportType == kAudioDeviceTransportTypeBluetooth
            || transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    public func setInputMute(_ muted: Bool) -> Bool {
        guard let deviceID = resolveDefaultInputDeviceID() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)

        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(deviceID, &address, &isSettable) == noErr, isSettable.boolValue else {
            return false
        }

        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        return status == noErr
    }

    public func readInputMute() -> Bool? {
        guard let deviceID = resolveDefaultInputDeviceID() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value != 0
    }

    public func nominalSampleRate() -> Double? {
        guard let deviceID = resolveDefaultInputDeviceID() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &rate)
        guard status == noErr else { return nil }
        return rate
    }
}
