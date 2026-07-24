import Foundation

let kMicLoudThreshold: Float = 1e-2
public let kSystemLoudThreshold: Float = 1e-4
public let kSystemAudioSampleRate: Double = 24000

public func computePeakLevel(in channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
                              channels: Int, frames: Int) -> Float {
    var peak: Float = 0
    for ch in 0..<channels {
        for i in 0..<frames {
            let v = abs(channelData[ch][i])
            if v > peak { peak = v }
        }
    }
    return peak
}
