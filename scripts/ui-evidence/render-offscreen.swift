// Off-screen renderer for LibraryWindow — works with screen locked.
// Based on spike at /tmp/win-spike/nav.swift.
// Compiled together with OwnscribeCapture + OwnscribeMenuBar sources.
import SwiftUI
import AppKit
import Foundation

@MainActor
func renderLibraryWindow(dark: Bool, outputPath: String, meetingsDir: URL) -> (success: Bool, message: String) {
    // Create isolated AppState pointing at a copy of meetings, never the live data
    let appState = AppState(homeDir: meetingsDir, muteDevice: NoOpMuteDevice())

    // Build the real LibraryWindow view with environment
    let view = LibraryWindow()
        .environment(appState)
        .frame(width: 1190, height: 660)

    let ap = NSAppearance(named: dark ? .darkAqua : .aqua)
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 1190, height: 660)
    host.appearance = ap

    let win = NSWindow(
        contentRect: host.frame,
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    win.appearance = ap
    win.contentView = host
    win.setFrameOrigin(NSPoint(x: -20000, y: -20000))  // off-screen: never visible
    win.orderBack(nil)

    host.layoutSubtreeIfNeeded()
    // Glass effect + List need a real runloop turn to settle
    RunLoop.main.run(until: Date().addingTimeInterval(1.2))

    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        return (false, "NO_REP")
    }
    host.cacheDisplay(in: host.bounds, to: rep)

    guard let png = rep.representation(using: .png, properties: [:]) else {
        return (false, "NO_PNG")
    }

    let url = URL(fileURLWithPath: outputPath)
    do {
        try png.write(to: url)
        win.orderOut(nil)
        return (true, "\(outputPath) (\(png.count) bytes)")
    } catch {
        return (false, "WRITE_FAILED: \(error)")
    }
}

// No-op mute device for isolation
struct NoOpMuteDevice: AudioMuteDevice {
    func readInputMute() -> Bool? { nil }
    func setInputMute(_ muted: Bool) -> Bool { false }
    func isBluetooth() -> Bool { false }
    func nominalSampleRate() -> Double? { nil }
}

var standardError = FileHandle.standardError
extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        let data = Data(string.utf8)
        self.write(data)
    }
}

@main
@MainActor
struct RenderOffscreenMain {
    static func main() {
        guard CommandLine.arguments.count == 3 else {
            print("Usage: render-offscreen <output-dir> <meetings-home-dir>")
            exit(1)
        }

        let outputDir = CommandLine.arguments[1]
        let meetingsHome = URL(fileURLWithPath: CommandLine.arguments[2])

        // Create output dir
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        NSApplication.shared.setActivationPolicy(.prohibited)  // Never appear in Dock/on screen

        let lightPath = "\(outputDir)/library-light.png"
        let darkPath = "\(outputDir)/library-dark.png"

        let lightResult = renderLibraryWindow(dark: false, outputPath: lightPath, meetingsDir: meetingsHome)
        let darkResult = renderLibraryWindow(dark: true, outputPath: darkPath, meetingsDir: meetingsHome)

        if lightResult.success {
            print("LIGHT: \(lightResult.message)")
        } else {
            print("LIGHT_FAILED: \(lightResult.message)", to: &standardError)
        }

        if darkResult.success {
            print("DARK: \(darkResult.message)")
        } else {
            print("DARK_FAILED: \(darkResult.message)", to: &standardError)
        }

        exit((lightResult.success && darkResult.success) ? 0 : 2)
    }
}
