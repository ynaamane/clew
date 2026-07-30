import AppKit
import Foundation

@MainActor
public final class UrlOpenHandler: NSObject {
    public static let shared = UrlOpenHandler()

    public var openScene: ((String) -> Void)?

    private var installed = false

    public func install() {
        guard !installed else { return }
        installed = true
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc
    private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string)
        else { return }
        handle(url)
    }

    func handle(_ url: URL) {
        guard let scene = WindowOpenRoute.scene(for: url) else { return }
        AppLogger.recording.info("Opening scene from URL: \(scene, privacy: .public)")

        guard let openScene else {
            AppLogger.recording.error("URL route reached before any scene opener was registered")
            return
        }
        openScene(scene)
    }
}
