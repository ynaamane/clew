import XCTest
@testable import OwnscribeMenuBar

final class WindowOpenRouteTests: XCTestCase {
    func testTheLibraryURLOpensTheLibraryScene() {
        let route = WindowOpenRoute.scene(for: URL(string: "ownscribe://library")!)

        XCTAssertEqual(
            route, LibraryWindow.sceneID,
            "the window is otherwise reachable only by clicking the menu bar extra: SwiftUI's "
                + "MenuBarExtra(.window) popover exposes nothing to accessibility, so a keyboard "
                + "user and an automated design review are equally locked out")
    }

    func testTheHostIsMatchedCaseInsensitivelyBecauseURLsGetTyped() {
        XCTAssertEqual(WindowOpenRoute.scene(for: URL(string: "ownscribe://Library")!), LibraryWindow.sceneID)
        XCTAssertEqual(WindowOpenRoute.scene(for: URL(string: "OWNSCRIBE://LIBRARY")!), LibraryWindow.sceneID)
    }

    func testAPathFormIsAcceptedToo() {
        XCTAssertEqual(
            WindowOpenRoute.scene(for: URL(string: "ownscribe:///library")!), LibraryWindow.sceneID,
            "a triple slash puts 'library' in the path rather than the host; both spellings are "
                + "things a person actually types")
    }

    func testAnotherAppsSchemeIsRefused() {
        XCTAssertNil(
            WindowOpenRoute.scene(for: URL(string: "http://library")!),
            "handling a foreign scheme would let any web page open this window")
        XCTAssertNil(WindowOpenRoute.scene(for: URL(string: "otherapp://library")!))
    }

    func testAnUnknownDestinationIsRefusedRatherThanFallingBackToTheLibrary() {
        XCTAssertNil(
            WindowOpenRoute.scene(for: URL(string: "ownscribe://record")!),
            "silently opening the library for any unknown URL would make a typo look like it worked, "
                + "and would open a window on a URL that might one day mean something else")
        XCTAssertNil(WindowOpenRoute.scene(for: URL(string: "ownscribe://")!))
    }
}
