import Foundation

public struct EnvelopeDocument: Equatable {
    public let buckets: [Double]

    public init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(EnvelopeJSON.self, from: data)
        self.buckets = decoded.envelope
    }

    public static func load(from meetingDirectory: URL) -> EnvelopeDocument? {
        let path = meetingDirectory.appendingPathComponent("envelope.json")
        return try? EnvelopeDocument(contentsOf: path)
    }
}

private struct EnvelopeJSON: Decodable {
    let envelope: [Double]
}
