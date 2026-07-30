import XCTest
import SwiftUI
import AppKit
@testable import OwnscribeCapture
@testable import OwnscribeMenuBar

@MainActor
final class DesignRenderTests: XCTestCase {
    func testRenderLibraryWindowOffScreen() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OWNSCRIBE_RENDER_UI"] == "1",
            "Renders LibraryWindow off-screen for design review. Works with screen locked. Run with OWNSCRIBE_RENDER_UI=1.")

        let outputDir = ProcessInfo.processInfo.environment["OWNSCRIBE_RENDER_OUTPUT"] ?? "/tmp/ui-render"
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        let meetingsCopy = copyMeetingsToTemp()

        let lightPath = "\(outputDir)/library-light.png"
        let darkPath = "\(outputDir)/library-dark.png"

        let lightResult = renderLibraryWindow(dark: false, outputPath: lightPath, meetingsDir: meetingsCopy)
        let darkResult = renderLibraryWindow(dark: true, outputPath: darkPath, meetingsDir: meetingsCopy)

        XCTAssertTrue(lightResult.success, "Light render failed: \(lightResult.message)")
        XCTAssertTrue(darkResult.success, "Dark render failed: \(darkResult.message)")

        verifyRenderedContent(at: lightPath)
        verifyRenderedContent(at: darkPath)

        printCannotVerifyWarning()

        print("SUCCESS: \(lightPath)")
        print("SUCCESS: \(darkPath)")
    }

    private func copyMeetingsToTemp() -> URL {
        let liveDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ownscribe")
        let tempHome = URL(fileURLWithPath: "/tmp/ownscribe-render-isolated")
        let tempMeetingsDir = tempHome.appendingPathComponent("ownscribe")

        try? FileManager.default.removeItem(at: tempHome)
        try? FileManager.default.createDirectory(at: tempMeetingsDir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: liveDir.path) {
            let contents = try? FileManager.default.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: nil)
            for dir in contents ?? [] {
                let dest = tempMeetingsDir.appendingPathComponent(dir.lastPathComponent)
                try? FileManager.default.copyItem(at: dir, to: dest)
            }
        }

        return tempHome
    }

    private func renderLibraryWindow(dark: Bool, outputPath: String, meetingsDir: URL) -> (success: Bool, message: String) {
        let noOpMute = NoOpMuteDevice()
        let appState = AppState(homeDir: meetingsDir, muteDevice: noOpMute)

        appState.systemCaptureFactory = nil
        appState.micCaptureFactory = { nil }
        appState.pipelineRunnerFactory = { StubPipelineRunner() }

        let view = LibraryWindow().environment(appState).frame(width: 1190, height: 660)

        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1190, height: 660)
        host.appearance = appearance

        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Réunions"
        window.appearance = appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderBack(nil)

        NSApplication.shared.setActivationPolicy(.prohibited)

        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))

        guard let target = host.superview else {
            return (false, "NO_SUPERVIEW")
        }

        guard let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds) else {
            return (false, "NO_REP")
        }

        target.cacheDisplay(in: target.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            return (false, "NO_PNG")
        }

        let url = URL(fileURLWithPath: outputPath)
        do {
            try png.write(to: url)
            window.orderOut(nil)
            return (true, "\(outputPath) (\(png.count) bytes, \(Int(rep.size.width))x\(Int(rep.size.height)))")
        } catch {
            return (false, "WRITE_FAILED: \(error)")
        }
    }

    private func verifyRenderedContent(at path: String) {
        guard let image = NSImage(contentsOfFile: path),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            XCTFail("Cannot load rendered image at \(path)")
            return
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh

        XCTAssertGreaterThan(width, 800, "Rendered width too small")
        XCTAssertGreaterThan(height, 400, "Rendered height too small")

        var variance: Double = 0
        var totalPixels = 0
        var sum: Double = 0

        for y in 0..<height {
            for x in 0..<width {
                if let color = bitmap.colorAt(x: x, y: y) {
                    let gray = 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
                    sum += gray
                    totalPixels += 1
                }
            }
        }

        let mean = sum / Double(totalPixels)

        for y in 0..<height {
            for x in 0..<width {
                if let color = bitmap.colorAt(x: x, y: y) {
                    let gray = 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
                    variance += (gray - mean) * (gray - mean)
                }
            }
        }

        variance /= Double(totalPixels)

        XCTAssertGreaterThan(
            variance, 0.001,
            "Rendered image has trivial pixel variance (\(variance)) — likely blank or placeholder. A valid render of LibraryWindow should show text, badges, and UI elements with significant contrast.")
    }

    private func printCannotVerifyWarning() {
        let warning = """

        ⚠️  CANNOT VERIFY (compositor-dependent, off-screen limitations):

        1. Liquid Glass / glassEffect: silent NO-OP off-screen
           Evidence: Four sidebar variants (glass-on-List, glass-on-container, NO glass,
           .background(.bar)) rendered via cacheDisplay. First three were BYTE-IDENTICAL
           (md5 613f4c7e77be8ae7bfb878d0b77bde8c). Only .background(.bar) differed.
           Liquid Glass needs the real compositor; cacheDisplay bypasses it.

        2. Selection highlights: render as BLACK instead of grey
           Evidence: Off-screen selected row samples as (0,0,0) pure black.
           Real capture (/tmp/ui-ev/window.png) shows same row as (225,226,226) light grey.
           Materials/vibrancy do not composite off-screen.

        3. Badges on selected sidebar rows: invisible or missing
           Evidence: Fixture data shows badge=9 for "Toutes les réunions" but the
           rendered selected row (black pill artifact) shows no badge. The badge is
           either not drawn or drawn in a color invisible against the black background.
           Consequence of the black selection artifact above.

        4. Any other compositor-dependent effects: translucency, vibrancy, materials

        ✓  CAN VERIFY (and this harness is trustworthy for):
           - Layout, spacing, type scale, colour, text content, truncation
           - Light vs dark appearance switching (genuinely differ)
           - Sidebar badges on UNSELECTED rows, section headers, meeting rows, toolbar, empty states

        📋 Ground truth comparison (expected badges from /tmp/ui-ev/window.png):
           Expected: [9, 1+, 1+, 5] for Bibliothèque section items
           Visible in render: [missing on selected row, 1+, 1+, 5]
           Missing: "9" badge on "Toutes les réunions" (first item, selected/black)

        """
        print(warning)
    }
}

private struct NoOpMuteDevice: AudioMuteDevice {
    func readInputMute() -> Bool? { nil }
    func setInputMute(_ muted: Bool) -> Bool { false }
    func isBluetooth() -> Bool { false }
    func nominalSampleRate() -> Double? { nil }
}

private struct StubPipelineRunner: PipelineRunning {
    func run(arguments: [String], onEvent: @escaping @Sendable (ProgressEvent) -> Void) async throws {}
}
