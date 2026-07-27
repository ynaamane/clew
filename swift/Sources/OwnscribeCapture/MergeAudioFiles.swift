import AVFAudio
import Foundation

public func writeTrackAlignmentSidecar(outputDir: URL, micStartOffsetSeconds: Double) {
    let sidecarPath = outputDir.appendingPathComponent("track_alignment.json").path
    let json = "{\"mic_start_offset_seconds\": \(micStartOffsetSeconds)}\n"
    try? json.write(toFile: sidecarPath, atomically: true, encoding: .utf8)
}

public func openAudioFileWithFrames(atPath path: String) -> AVAudioFile? {
    guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return nil }
    return file.length > 0 ? file : nil
}

public func computeMicStartOffset(
    systemStartHostTime: UInt64,
    micStartHostTime: UInt64,
    ticksToNanos: Double,
    sampleRate: Double
) -> (offsetSeconds: Double, offsetFrames: Int64) {
    let systemStartNanos = Double(systemStartHostTime) * ticksToNanos
    let micStartNanos = Double(micStartHostTime) * ticksToNanos
    let offsetSeconds = (micStartNanos - systemStartNanos) / 1_000_000_000.0
    let offsetFrames = Int64(offsetSeconds * sampleRate)
    return (offsetSeconds, offsetFrames)
}

public func mergeAudioFiles(systemPath: String, micPath: String,
                     systemStartHostTime: UInt64, micStartHostTime: UInt64,
                     outputPath: String) throws {
    let fm = FileManager.default
    let systemFile = openAudioFileWithFrames(atPath: systemPath)
    let micFile = openAudioFileWithFrames(atPath: micPath)

    let outputDir = URL(fileURLWithPath: outputPath).deletingLastPathComponent()
    let systemKeepPath = outputDir.appendingPathComponent("system.wav").path
    let micKeepPath = outputDir.appendingPathComponent("mic.wav").path
    if systemFile != nil {
        try? fm.removeItem(atPath: systemKeepPath)
        try? fm.copyItem(atPath: systemPath, toPath: systemKeepPath)
    }
    if micFile != nil {
        try? fm.removeItem(atPath: micKeepPath)
        try? fm.copyItem(atPath: micPath, toPath: micKeepPath)
    }

    if systemFile == nil && micFile == nil {
        try? fm.removeItem(atPath: systemPath)
        try? fm.removeItem(atPath: micPath)
        return
    }

    guard let micFile else {
        try? fm.removeItem(atPath: micPath)
        try fm.moveItem(atPath: systemPath, toPath: outputPath)
        fputs("Merged audio saved to \(outputPath) (system only, no mic audio)\n", stderr)
        return
    }

    let outputSampleRate: Double = systemFile?.processingFormat.sampleRate
        ?? micFile.processingFormat.sampleRate
    let outputChannels: AVAudioChannelCount = 1

    // Compute offset in seconds between the two start times using mach_timebase_info
    let offsetFrames: Int64
    let micStartOffsetSeconds: Double
    if systemFile != nil {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticksToNanos = Double(timebase.numer) / Double(timebase.denom)
        let offset = computeMicStartOffset(
            systemStartHostTime: systemStartHostTime,
            micStartHostTime: micStartHostTime,
            ticksToNanos: ticksToNanos,
            sampleRate: outputSampleRate)
        offsetFrames = offset.offsetFrames
        micStartOffsetSeconds = offset.offsetSeconds
    } else {
        offsetFrames = 0
        micStartOffsetSeconds = 0
    }
    writeTrackAlignmentSidecar(outputDir: outputDir, micStartOffsetSeconds: micStartOffsetSeconds)
    let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: outputSampleRate,
                                      channels: outputChannels,
                                      interleaved: true)!
    let outputFile = try AVAudioFile(forWriting: URL(fileURLWithPath: outputPath),
                                      settings: outputFormat.settings,
                                      commonFormat: .pcmFormatFloat32,
                                      interleaved: true)

    // Mic converter using callback API (handles sample rate + channel conversion)
    let micFormat = micFile.processingFormat
    let micConverter = AVAudioConverter(from: micFormat, to: outputFormat)!
    let micRate = micFormat.sampleRate

    let chunkSize: AVAudioFrameCount = 8192
    let systemLength = systemFile.map { Int64($0.length) } ?? 0
    // Mic file length converted to output-rate frames
    let micLengthOutput = Int64(Double(micFile.length) * outputSampleRate / micRate)

    // Calculate total output length accounting for offset
    let systemEndFrame = (offsetFrames >= 0) ? systemLength : systemLength + (-offsetFrames)
    let micEndFrame = (offsetFrames >= 0) ? micLengthOutput + offsetFrames : micLengthOutput
    let totalOutputFrames = max(systemEndFrame, micEndFrame)

    // Mic region in output timeline
    let micOutputStart: Int64 = (offsetFrames >= 0) ? offsetFrames : 0
    let micOutputEnd: Int64 = micOutputStart + micLengthOutput
    var micDone = false

    var outputFrame: Int64 = 0

    while outputFrame < totalOutputFrames {
        let framesToProcess = AVAudioFrameCount(min(Int64(chunkSize), totalOutputFrames - outputFrame))
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesToProcess) else { break }
        outBuffer.frameLength = framesToProcess

        // Zero the output buffer
        let outPtr = outBuffer.floatChannelData![0]
        for i in 0..<Int(framesToProcess * outputChannels) {
            outPtr[i] = 0
        }

        // Read and mix system audio (manual interleave from non-interleaved processingFormat)
        if let systemFile = systemFile {
            let sysFrameInFile = (offsetFrames >= 0) ? outputFrame : outputFrame + offsetFrames
            let writeOffset = max(0, -sysFrameInFile)
            let readStart = max(0, sysFrameInFile)
            if readStart < systemLength && writeOffset < Int64(framesToProcess) {
                let maxRead = Int64(framesToProcess) - writeOffset
                let sysReadCount = AVAudioFrameCount(min(maxRead, systemLength - readStart))
                if sysReadCount > 0 {
                    systemFile.framePosition = AVAudioFramePosition(readStart)
                    if let sysBuf = AVAudioPCMBuffer(pcmFormat: systemFile.processingFormat, frameCapacity: sysReadCount) {
                        try systemFile.read(into: sysBuf, frameCount: sysReadCount)
                        let sysData = sysBuf.floatChannelData!
                        let sysCh = Int(sysBuf.format.channelCount)
                        let wo = Int(writeOffset)
                        for i in 0..<Int(sysBuf.frameLength) {
                            var mix: Float = 0
                            for ch in 0..<sysCh { mix += sysData[ch][i] }
                            outPtr[wo + i] += mix / Float(sysCh)
                        }
                    }
                }
            }
        }

        // Read and mix mic audio using callback-based converter
        let chunkEnd = outputFrame + Int64(framesToProcess)
        if !micDone && chunkEnd > micOutputStart && outputFrame < micOutputEnd {
            let overlapStart = max(outputFrame, micOutputStart)
            let overlapEnd = min(chunkEnd, micOutputEnd)
            let micFramesNeeded = AVAudioFrameCount(overlapEnd - overlapStart)

            if micFramesNeeded > 0 {
                guard let micOutBuf = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: micFramesNeeded) else { break }

                var convError: NSError?
                let status = micConverter.convert(to: micOutBuf, error: &convError) { inNumberOfPackets, outStatus in
                    let remaining = AVAudioFrameCount(micFile.length - micFile.framePosition)
                    if remaining == 0 {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    let toRead = min(inNumberOfPackets, remaining)
                    guard let buf = AVAudioPCMBuffer(pcmFormat: micFormat, frameCapacity: toRead) else {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    do {
                        try micFile.read(into: buf, frameCount: toRead)
                        outStatus.pointee = .haveData
                        return buf
                    } catch {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                }

                if status == .endOfStream {
                    micDone = true
                }

                // Mix converted mic audio into output at correct position
                if micOutBuf.frameLength > 0 {
                    let offsetInChunk = Int(overlapStart - outputFrame)
                    let srcPtr = micOutBuf.floatChannelData![0]
                    let count = Int(micOutBuf.frameLength * outputChannels)
                    for i in 0..<count {
                        outPtr[offsetInChunk * Int(outputChannels) + i] += srcPtr[i]
                    }
                }
            }
        }

        // Clamp to [-1, 1]
        let totalSamples = Int(framesToProcess * outputChannels)
        for i in 0..<totalSamples {
            outPtr[i] = max(-1.0, min(1.0, outPtr[i]))
        }

        try outputFile.write(from: outBuffer)
        outputFrame += Int64(framesToProcess)
    }

    // Delete temp files
    try? FileManager.default.removeItem(atPath: systemPath)
    try? FileManager.default.removeItem(atPath: micPath)

    let detail = systemFile == nil ? " (mic only, no system audio)" : ""
    fputs("Merged audio saved to \(outputPath)\(detail)\n", stderr)
}
