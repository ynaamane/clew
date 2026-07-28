import Testing
import Foundation
@testable import OwnscribeMenuBar

@Suite struct AudioTracksPresenceRealSilentTests {
    @Test func silentRecordingDoesNotRenderAsCheckmark() throws {
        let silentDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("ownscribe/2026-07-27_1352")

        guard FileManager.default.fileExists(atPath: silentDir.path) else {
            Issue.record("Test directory not found: \(silentDir.path)")
            return
        }

        let tracks = AudioTracksPresence.checkTracks(in: silentDir)
        let recording = tracks.first { $0.filename == "recording.wav" }

        #expect(recording != nil)
        #expect(recording?.isPresent == true)

        if let duration = recording?.duration, duration > 0 {
            let hasContent = recording?.hasContent ?? false
            #expect(hasContent == false, "33.5s of silence should not render as having content")
        }
    }

    @Test func zeroBytesFileDoesNotRenderAsCheckmark() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let zeroPath = tempDir.appendingPathComponent("system.wav")
        try Data().write(to: zeroPath)

        let tracks = AudioTracksPresence.checkTracks(in: tempDir)
        let system = tracks.first { $0.filename == "system.wav" }

        #expect(system?.isPresent == true)
        #expect(system?.hasContent == false)
    }
}