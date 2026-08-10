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

    // activeOverride feeds the startup log: honoring CLEW_HOME must never be
    // silent (review finding, 2026-08-10).
    func testActiveOverrideReportsThePathWhenSet() {
        XCTAssertEqual(
            HomeDirectory.activeOverride(environment: ["CLEW_HOME": "/tmp/home-directory-tests-override"]),
            "/tmp/home-directory-tests-override"
        )
    }

    func testActiveOverrideIsNilWhenUnsetOrEmpty() {
        XCTAssertNil(HomeDirectory.activeOverride(environment: [:]))
        XCTAssertNil(HomeDirectory.activeOverride(environment: ["CLEW_HOME": ""]))
    }

    // Source-scan guard: every home resolution in the app target must go
    // through HomeDirectory.resolve() so CLEW_HOME isolation cannot silently
    // regress when a new call site is added.
    func testNoDirectHomeResolutionOutsideHomeDirectory() throws {
        let sourcesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OwnscribeMenuBarTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // swift
            .appendingPathComponent("Sources")

        let enumerator = try XCTUnwrap(FileManager.default.enumerator(
            at: sourcesDir, includingPropertiesForKeys: nil))

        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let content = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in content.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // Match on the code portion only: a comment on the same line
                // must never be able to whitelist real code (review finding,
                // 2026-08-10: `call() // fallback: ...` slipped through).
                let code = line.components(separatedBy: "//").first ?? ""
                guard code.contains("homeDirectoryForCurrentUser") || code.contains("NSHomeDirectory(") else { continue }
                let isDefinition = url.lastPathComponent == "HomeDirectory.swift"
                let isExplicitFallback = code.contains("fallback: fileManager.homeDirectoryForCurrentUser")
                if !isDefinition && !isExplicitFallback {
                    violations.append("\(url.lastPathComponent):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Direct home resolution bypasses the CLEW_HOME override and can read real user data "
                + "in isolated runs. Route it through HomeDirectory.resolve(). Violations:\n"
                + violations.joined(separator: "\n"))
    }
}
