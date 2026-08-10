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

    // Interpolation reopens a real code context inside a string: a call in
    // \( ... ) must stay visible to the guard (review finding, 2026-08-10:
    // print("... \(FileManager.default.homeDirectoryForCurrentUser)") was
    // blanked as text and slipped through).
    func testCodePortionKeepsInterpolatedCodeVisible() {
        let scanned = Self.codePortion(of: #"print("home resolved as \(FileManager.default.homeDirectoryForCurrentUser)")"#)
        XCTAssertTrue(scanned.contains("homeDirectoryForCurrentUser"))
    }

    func testCodePortionBlanksNestedStringInsideInterpolation() {
        let scanned = Self.codePortion(of: #"log("\(f("https://x.co")) tail")"#)
        XCTAssertTrue(scanned.contains("f("))
        XCTAssertFalse(scanned.contains("https"))
        XCTAssertFalse(scanned.contains("tail"))
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

    /// The line's code, with real comments dropped and string-literal TEXT
    /// blanked (quotes kept). A "//" inside a string is not a comment; text
    /// inside a string is not code; but a \( ... ) interpolation REOPENS a
    /// code context, recursively, and its content stays visible.
    private static func codePortion(of line: String) -> String {
        enum ScanMode {
            case string
            case interpolation(parenDepth: Int)
        }
        var out: [Character] = []
        var stack: [ScanMode] = []
        var escaped = false
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch stack.last {
            case .string:
                if escaped {
                    escaped = false
                    if c == "(" {
                        stack.append(.interpolation(parenDepth: 1))
                        out.append(c)
                    } else {
                        out.append(" ")
                    }
                } else if c == "\\" {
                    escaped = true
                    out.append(" ")
                } else if c == "\"" {
                    stack.removeLast()
                    out.append(c)
                } else {
                    out.append(" ")
                }
            case .interpolation(let depth):
                if c == "\"" {
                    stack.append(.string)
                    out.append(c)
                } else if c == "(" {
                    stack[stack.count - 1] = .interpolation(parenDepth: depth + 1)
                    out.append(c)
                } else if c == ")" {
                    if depth == 1 {
                        stack.removeLast()
                    } else {
                        stack[stack.count - 1] = .interpolation(parenDepth: depth - 1)
                    }
                    out.append(c)
                } else {
                    out.append(c)
                }
            case nil:
                if c == "\"" {
                    stack.append(.string)
                    out.append(c)
                } else if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    return String(out)
                } else {
                    out.append(c)
                }
            }
            i += 1
        }
        return String(out)
    }
}
