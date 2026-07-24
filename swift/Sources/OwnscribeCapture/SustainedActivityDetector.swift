import Foundation

public class SustainedActivityDetector {
    private let sustainedSeconds: Double
    private var activeSince: Date?

    public init(sustainedSeconds: Double) {
        self.sustainedSeconds = sustainedSeconds
    }

    public func observe(running: Bool, now: Date) -> Bool {
        if running {
            if activeSince == nil {
                activeSince = now
            }
            return now.timeIntervalSince(activeSince!) >= sustainedSeconds
        }
        activeSince = nil
        return false
    }
}

public func combinedCallSignal(mic: Bool?, output: Bool?) -> Bool? {
    guard let mic, let output else { return nil }
    return mic && output
}
