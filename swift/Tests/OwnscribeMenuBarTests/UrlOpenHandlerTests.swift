import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class UrlOpenHandlerTests: XCTestCase {
    override func tearDown() {
        UrlOpenHandler.shared.openScene = nil
        super.tearDown()
    }

    func testTheLibraryUrlReachesTheSceneOpener() {
        var opened: [String] = []
        UrlOpenHandler.shared.openScene = { opened.append($0) }

        UrlOpenHandler.shared.handle(URL(string: "ownscribe://library")!)

        XCTAssertEqual(
            opened, [LibraryWindow.sceneID],
            "the URL must reach the opener, not merely parse: the window is otherwise reachable only "
                + "by a mouse click on an accessibility-opaque popover")
    }

    func testAnUnknownUrlOpensNothing() {
        var opened: [String] = []
        UrlOpenHandler.shared.openScene = { opened.append($0) }

        UrlOpenHandler.shared.handle(URL(string: "ownscribe://nope")!)
        UrlOpenHandler.shared.handle(URL(string: "http://library")!)

        XCTAssertTrue(
            opened.isEmpty,
            "opening a window for any URL would let a web page pop this app to the foreground")
    }

    func testTheBundleDeclaresTheSchemeItHandles() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/MenuBarApp-Info.plist")

        let contents = try XCTUnwrap(
            NSDictionary(contentsOf: plist) as? [String: Any],
            "the shipped Info.plist must be readable; build-app.sh copies this exact file")

        let schemes = (contents["CFBundleURLTypes"] as? [[String: Any]])?
            .compactMap { $0["CFBundleURLSchemes"] as? [String] }
            .flatMap { $0 } ?? []

        XCTAssertTrue(
            schemes.contains(WindowOpenRoute.scheme),
            "the handler is inert without the declaration: macOS routes ownscribe:// only to a bundle "
                + "that claims the scheme, so shipping the code alone changes nothing")
    }
}
