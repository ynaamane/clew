import AppKit
import Foundation

@MainActor
public protocol TerminationSignalSource {
    func setHandler(_ handler: @escaping () -> Void)
    func begin()
}

@MainActor
public final class DispatchTerminationSignalSource: TerminationSignalSource {
    private let source: DispatchSourceSignal

    public init(signalNumber: Int32) {
        source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    }

    public func setHandler(_ handler: @escaping () -> Void) {
        source.setEventHandler(handler: handler)
    }

    public func begin() {
        source.resume()
    }
}

@MainActor
public final class TerminationSignalHandlers {
    public static let terminationSignals: [Int32] = [SIGTERM, SIGINT]

    private let makeSource: (Int32) -> TerminationSignalSource
    private let ignoreDefaultDisposition: (Int32) -> Void
    private let onTerminate: () -> Void
    private var sources: [TerminationSignalSource] = []

    public init(
        makeSource: ((Int32) -> TerminationSignalSource)? = nil,
        ignoreDefaultDisposition: ((Int32) -> Void)? = nil,
        onTerminate: (() -> Void)? = nil
    ) {
        self.makeSource = makeSource ?? { DispatchTerminationSignalSource(signalNumber: $0) }
        self.ignoreDefaultDisposition = ignoreDefaultDisposition ?? { signal($0, SIG_IGN) }
        self.onTerminate = onTerminate ?? { NSApplication.shared.terminate(nil) }
    }

    public func register(restoreUnmuted: @escaping () -> Void) {
        for signalNumber in Self.terminationSignals {
            ignoreDefaultDisposition(signalNumber)

            let source = makeSource(signalNumber)
            source.setHandler { [onTerminate] in
                restoreUnmuted()
                onTerminate()
            }
            source.begin()
            sources.append(source)
        }
    }
}
