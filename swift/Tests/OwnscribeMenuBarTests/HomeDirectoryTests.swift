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

    // codePortion strips comments and blanks string-literal contents so that
    // neither can hide real code from the guard below (review findings,
    // 2026-08-10: a same-line comment whitelisted a real call, then a URL's
    // "//" inside a string truncated the scanned code before the call).
    func testCodePortionDropsRealComments() {
        XCTAssertEqual(
            Self.codePortion(of: "let a = b // fallback: fileManager.homeDirectoryForCurrentUser"),
            "let a = b "
        )
    }

    func testCodePortionIgnoresSlashesInsideStrings() {
        XCTAssertEqual(
            Self.codePortion(of: #"let _ = "see https://x.co"; return callSite()"#),
            #"let _ = "                "; return callSite()"#
        )
    }

    func testCodePortionBlanksStringContentsSoTheyNeverTriggerOrWhitelist() {
        let blanked = Self.codePortion(of: #"log("homeDirectoryForCurrentUser \" quoted")"#)
        XCTAssertFalse(blanked.contains("homeDirectoryForCurrentUser"))
        XCTAssertTrue(blanked.hasPrefix("log(\""))
        XCTAssertTrue(blanked.hasSuffix("\")"))
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
                // Match on the code portion only: comments and string
                // contents must never be able to hide or whitelist real code.
                // Known accepted limitation: lines inside multiline string
                // literals are scanned as code, which can only produce a LOUD
                // false positive, never a silent miss.
                let code = Self.codePortion(of: String(line))
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

    /// The line's code, with real comments dropped and string-literal
    /// contents blanked (quotes kept). A "//" inside a string is not a
    /// comment; text inside a string is not code.
    private static func codePortion(of line: String) -> String {
        var out: [Character] = []
        var inString = false
        var escaped = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inString {
                if escaped {
                    escaped = false
                    out.append(" ")
                } else if c == "\\" {
                    escaped = true
                    out.append(" ")
                } else if c == "\"" {
                    inString = false
                    out.append(c)
                } else {
                    out.append(" ")
                }
                i += 1
                continue
            }
            if c == "\"" {
                inString = true
                out.append(c)
                i += 1
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                break
            }
            out.append(c)
            i += 1
        }
        return String(out)
    }
}
