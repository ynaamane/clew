import Foundation

public protocol SystemAudioCapturing: AnyObject {
    var silenceTimeout: TimeInterval { get set }
    var onSilenceTimeout: (() -> Void)? { get set }
    var micCapture: MicCapture? { get set }
    var startHostTime: UInt64 { get }

    func start() async throws
    func stop()
}
