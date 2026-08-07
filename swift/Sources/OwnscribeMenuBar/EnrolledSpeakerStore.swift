import Foundation

public struct EnrolledSpeakerStore {
    private struct Database: Decodable {
        struct Entry: Decodable {
            let name: String
        }
        let voiceprints: [Entry]
    }

    public static func names(in homeDir: URL) -> [String] {
        let path = homeDir.appendingPathComponent(".config/clew/voiceprints/voiceprints.json")
        guard let data = try? Data(contentsOf: path),
              let database = try? JSONDecoder().decode(Database.self, from: data)
        else {
            return []
        }
        return database.voiceprints.map(\.name)
    }
}
