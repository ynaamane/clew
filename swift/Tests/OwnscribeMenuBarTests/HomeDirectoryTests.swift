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

    // Raw strings interpolate with \#(...) and close with "#: both must be
    // understood or a raw-string call is a silent miss (review finding,
    // 2026-08-10, round 4 — the codebase already uses #"..."# for TOML/JSON
    // fixtures, so this is ordinary future code, not an adversarial case).
    func testCodePortionKeepsRawStringInterpolatedCodeVisible() {
        let scanned = Self.codePortion(of: ##"print(#"path: \#(FileManager.default.homeDirectoryForCurrentUser)"#)"##)
        XCTAssertTrue(scanned.contains("homeDirectoryForCurrentUser"))
    }

    func testCodePortionBlanksRawStringTextIncludingSlashesAndQuotes() {
        let scanned = Self.codePortion(of: ##"let s = #"see https://x.co "quoted" homeDirectoryForCurrentUser"#; f()"##)
        XCTAssertFalse(scanned.contains("https"))
        XCTAssertFalse(scanned.contains("homeDirectoryForCurrentUser"))
        XCTAssertTrue(scanned.contains("f()"))
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
    /// blanked (delimiters kept). A "//" inside a string is not a comment;
    /// text inside a string is not code; but interpolation (\( ... ) in plain
    /// strings, \#( ... ) in raw #"..."# strings, pound count respected)
    /// REOPENS a code context, recursively, and its content stays visible.
    private static func codePortion(of line: String) -> String {
        enum ScanMode {
            case string(pounds: Int)
            case interpolation(parenDepth: Int)
        }
        var out: [Character] = []
        var stack: [ScanMode] = []
        let chars = Array(line)
        var i = 0

        func run(of char: Character, from index: Int) -> Int {
            var n = 0
            while index + n < chars.count, chars[index + n] == char { n += 1 }
            return n
        }

        while i < chars.count {
            let c = chars[i]
            switch stack.last {
            case .string(let pounds):
                if c == "\\" {
                    // Interpolation opener: backslash + `pounds` pounds + "(".
                    if run(of: "#", from: i + 1) >= pounds, i + 1 + pounds < chars.count, chars[i + 1 + pounds] == "(" {
                        stack.append(.interpolation(parenDepth: 1))
                        out.append(contentsOf: String(repeating: " ", count: 1 + pounds) + "(")
                        i += 2 + pounds
                    } else if pounds == 0, i + 1 < chars.count {
                        out.append(contentsOf: "  ")  // escape pair, e.g. \" or \\
                        i += 2
                    } else {
                        out.append(" ")  // literal backslash in a raw string
                        i += 1
                    }
                } else if c == "\"", run(of: "#", from: i + 1) >= pounds {
                    stack.removeLast()
                    out.append(contentsOf: "\"" + String(repeating: "#", count: pounds))
                    i += 1 + pounds
                } else {
                    out.append(" ")
                    i += 1
                }
            case .interpolation(let depth):
                if let opened = openStringIfDelimiter(at: i) {
                    stack.append(.string(pounds: opened.pounds))
                    out.append(contentsOf: opened.delimiter)
                    i += opened.delimiter.count
                } else if c == "(" {
                    stack[stack.count - 1] = .interpolation(parenDepth: depth + 1)
                    out.append(c)
                    i += 1
                } else if c == ")" {
                    if depth == 1 {
                        stack.removeLast()
                    } else {
                        stack[stack.count - 1] = .interpolation(parenDepth: depth - 1)
                    }
                    out.append(c)
                    i += 1
                } else {
                    out.append(c)
                    i += 1
                }
            case nil:
                if let opened = openStringIfDelimiter(at: i) {
                    stack.append(.string(pounds: opened.pounds))
                    out.append(contentsOf: opened.delimiter)
                    i += opened.delimiter.count
                } else if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    return String(out)
                } else {
                    out.append(c)
                    i += 1
                }
            }
        }
        return String(out)

        // A string opener at `index`: either a bare quote or pounds + quote.
        func openStringIfDelimiter(at index: Int) -> (pounds: Int, delimiter: String)? {
            if chars[index] == "\"" { return (0, "\"") }
            guard chars[index] == "#" else { return nil }
            let pounds = run(of: "#", from: index)
            guard index + pounds < chars.count, chars[index + pounds] == "\"" else { return nil }
            return (pounds, String(repeating: "#", count: pounds) + "\"")
        }
    }
}
