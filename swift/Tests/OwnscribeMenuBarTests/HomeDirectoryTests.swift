import XCTest
@testable import OwnscribeMenuBar

final class HomeDirectoryTests: XCTestCase {
    private let fallback = URL(fileURLWithPath: "/tmp/home-directory-tests-fallback", isDirectory: true)

    func testOverrideWinsWhenSet() {
        let resolved = HomeDirectory.resolve(
            environment: ["CLEW_HOME": "/tmp/home-directory-tests-override"],
            fallback: fallback
        )
        XCTAssertEqual(resolved.path, "/tmp/home-directory-tests-override")
    }

    func testFallbackWhenUnset() {
        let resolved = HomeDirectory.resolve(environment: [:], fallback: fallback)
        XCTAssertEqual(resolved, fallback)
    }

    func testFallbackWhenEmpty() {
        let resolved = HomeDirectory.resolve(environment: ["CLEW_HOME": ""], fallback: fallback)
        XCTAssertEqual(resolved, fallback)
    }

    func testOverrideIsTreatedAsDirectory() {
        let resolved = HomeDirectory.resolve(
            environment: ["CLEW_HOME": "/tmp/home-directory-tests-override"],
            fallback: fallback
        )
        XCTAssertTrue(resolved.hasDirectoryPath)
    }
}
