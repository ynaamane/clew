import Testing
import Foundation
@testable import OwnscribeMenuBar

@Suite struct AudioTracksPresenceTests {
    @Test func detectsSystemWav() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let systemPath = tempDir.appendingPathComponent("system.wav")
        try Data().write(to: systemPath)

        let tracks = AudioTracksPresence.checkTracks(in: tempDir)
        let system = tracks.first { $0.filename == "system.wav" }
        #expect(system?.isPresent == true)
    }

    @Test func detectsMicWav() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let micPath = tempDir.appendingPathComponent("mic.wav")
        try Data().write(to: micPath)

        let tracks = AudioTracksPresence.checkTracks(in: tempDir)
        let mic = tracks.first { $0.filename == "mic.wav" }
        #expect(mic?.isPresent == true)
    }

    @Test func absenceIsFalseNotCheckmark() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tracks = AudioTracksPresence.checkTracks(in: tempDir)
        for track in tracks {
            #expect(track.isPresent == false)
        }
    }

    @Test func returnsAllThreeCandidates() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tracks = AudioTracksPresence.checkTracks(in: tempDir)
        #expect(tracks.count == 3)
        #expect(tracks.contains { $0.filename == "system.wav" })
        #expect(tracks.contains { $0.filename == "mic.wav" })
        #expect(tracks.contains { $0.filename == "recording.wav" })
    }
}
