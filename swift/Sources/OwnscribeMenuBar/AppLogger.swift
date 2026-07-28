import Foundation
import OSLog

enum AppLogCategory: String {
    case recording
    case mute
    case pipeline
    case library

    var category: String { rawValue }
}

struct AppLogger {
    static let subsystem = "com.ownscribe.menubar"

    static func logger(for category: AppLogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.category)
    }

    static let recording = logger(for: .recording)
    static let mute = logger(for: .mute)
    static let pipeline = logger(for: .pipeline)
    static let library = logger(for: .library)

    static func timestampPrefix(from directoryName: String) -> String {
        let parts = directoryName.split(separator: "_", maxSplits: 2)
        guard parts.count >= 2 else { return directoryName }
        return "\(parts[0])_\(parts[1])"
    }
}

extension AppState.Phase {
    func logDescription() -> String {
        switch self {
        case .idle:
            return "idle"
        case .recording(let startedAt):
            let timestamp = Int(startedAt.timeIntervalSince1970)
            return "recording(startedAt: \(timestamp))"
        case .processing(let step, let fraction):
            if let frac = fraction {
                return String(format: "processing(step: %@, fraction: %.2f)", step, frac)
            }
            return "processing(step: \(step))"
        case .done(let directory):
            return "done(directory: \(directory.lastPathComponent))"
        case .failed:
            return "failed"
        }
    }
}
