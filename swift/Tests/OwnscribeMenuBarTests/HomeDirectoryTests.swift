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

    // codeText strips comments and blanks string-literal text so that neither
    // can hide real code from the guard below (review findings, 2026-08-10:
    // a same-line comment whitelisted a real call, then a URL's "//" inside a
    // string truncated the scanned code before the call).
    func testCodeTextDropsRealComments() {
        XCTAssertEqual(
            Self.codeText(of: "let a = b // fallback: fileManager.homeDirectoryForCurrentUser"),
            "let a = b "
        )
    }

    func testCodeTextIgnoresSlashesInsideStrings() {
        XCTAssertEqual(
            Self.codeText(of: #"let _ = "see https://x.co"; return callSite()"#),
            #"let _ = "                "; return callSite()"#
        )
    }

    func testCodeTextBlanksStringContentsSoTheyNeverTriggerOrWhitelist() {
        let blanked = Self.codeText(of: #"log("homeDirectoryForCurrentUser \" quoted")"#)
        XCTAssertFalse(blanked.contains("homeDirectoryForCurrentUser"))
        XCTAssertTrue(blanked.hasPrefix("log(\""))
        XCTAssertTrue(blanked.hasSuffix("\")"))
    }

    // Interpolation reopens a real code context inside a string: a call in
    // \( ... ) must stay visible to the guard (review finding, 2026-08-10:
    // print("... \(FileManager.default.homeDirectoryForCurrentUser)") was
    // blanked as text and slipped through).
    func testCodeTextKeepsInterpolatedCodeVisible() {
        let scanned = Self.codeText(of: #"print("home resolved as \(FileManager.default.homeDirectoryForCurrentUser)")"#)
        XCTAssertTrue(scanned.contains("homeDirectoryForCurrentUser"))
    }

    func testCodeTextBlanksNestedStringInsideInterpolation() {
        let scanned = Self.codeText(of: #"log("\(f("https://x.co")) tail")"#)
        XCTAssertTrue(scanned.contains("f("))
        XCTAssertFalse(scanned.contains("https"))
        XCTAssertFalse(scanned.contains("tail"))
    }

    // Raw strings interpolate with \#(...) and close with "#: both must be
    // understood or a raw-string call is a silent miss (review finding,
    // 2026-08-10, round 4 — the codebase already uses #"..."# for TOML/JSON
    // fixtures, so this is ordinary future code, not an adversarial case).
    func testCodeTextKeepsRawStringInterpolatedCodeVisible() {
        let scanned = Self.codeText(of: ##"print(#"path: \#(FileManager.default.homeDirectoryForCurrentUser)"#)"##)
        XCTAssertTrue(scanned.contains("homeDirectoryForCurrentUser"))
    }

    func testCodeTextBlanksRawStringTextIncludingSlashesAndQuotes() {
        let scanned = Self.codeText(of: ##"let s = #"see https://x.co "quoted" homeDirectoryForCurrentUser"#; f()"##)
        XCTAssertFalse(scanned.contains("https"))
        XCTAssertFalse(scanned.contains("homeDirectoryForCurrentUser"))
        XCTAssertTrue(scanned.contains("f()"))
    }

    // The scan is file-level: string state crosses physical lines. Round-5
    // review disproved the "multiline strings fail loud" prediction with a
    // stray unbalanced quote inside a multiline raw string hiding a real
    // interpolated call on the next line (silent miss, user-arbitrated
    // 2026-08-10: fix, do not document away).
    func testCodeTextTracksMultilineRawStringAcrossLines() {
        let source = """
        static let doc = #\"\"\"
        say "hi then \\#(FileManager.default.homeDirectoryForCurrentUser)
        \"\"\"#
        """
        let scanned = Self.codeText(of: source)
        XCTAssertTrue(scanned.contains("homeDirectoryForCurrentUser"))
        XCTAssertFalse(scanned.contains("say"))
        XCTAssertFalse(scanned.contains("hi"))
    }

    func testCodeTextBlanksClassicMultilineStringTextWithoutFalsePositive() {
        let source = """
        let d = \"\"\"
        prose with a stray " quote and homeDirectoryForCurrentUser in text
        \"\"\"
        """
        let scanned = Self.codeText(of: source)
        XCTAssertFalse(scanned.contains("homeDirectoryForCurrentUser"))
        XCTAssertFalse(scanned.contains("prose"))
    }

    func testCodeTextClosesUnterminatedPlainStringAtLineEnd() {
        let scanned = Self.codeText(of: "let s = \"oops\ncallSite()")
        XCTAssertTrue(scanned.contains("callSite()"))
    }

    // Block comments are skipped with nesting, newlines preserved. Round-6
    // review found a regression: a /* */ containing an odd number of triple
    // quotes opened a phantom multiline string and silently blanked the rest
    // of the file. Skipping block comments also means their text can neither
    // trigger the guard nor carry its whitelist phrase.
    func testCodeTextSkipsBlockCommentTextIncludingTripleQuotes() {
        let source = """
        /* Note: use \"\"\" for multiline literals. */
        callSite()
        """
        let scanned = Self.codeText(of: source)
        XCTAssertTrue(scanned.contains("callSite()"))
        XCTAssertFalse(scanned.contains("Note"))
    }

    func testCodeTextBlockCommentCannotWhitelistSameLineCode() {
        let scanned = Self.codeText(of: "realCall() /* fallback: fileManager.homeDirectoryForCurrentUser */")
        XCTAssertTrue(scanned.contains("realCall()"))
        XCTAssertFalse(scanned.contains("fallback:"))
    }

    func testCodeTextHandlesNestedBlockCommentsAndKeepsNewlines() {
        let scanned = Self.codeText(of: "/* a /* b\n c */ d */ after()\nnext()")
        XCTAssertTrue(scanned.contains("after()"))
        XCTAssertTrue(scanned.contains("\n"))
        XCTAssertTrue(scanned.contains("next()"))
        XCTAssertFalse(scanned.contains("b"))
        XCTAssertFalse(scanned.contains("d"))
    }

    // Interpolations are code, so block comments inside them are skipped too
    // (round-7 review: a /* */ inside \( ... ) was scanned as code, letting
    // it carry the whitelist phrase or reopen the round-6 blackout).
    func testCodeTextSkipsBlockCommentsInsideInterpolation() {
        let whitelisted = Self.codeText(of: #"print("x \(realCall() /* fallback: fileManager.homeDirectoryForCurrentUser */)")"#)
        XCTAssertTrue(whitelisted.contains("realCall()"))
        XCTAssertFalse(whitelisted.contains("fallback:"))

        let blackout = Self.codeText(of: "let a = \"x \\(1 /* \"\"\" */)\"\nafter()")
        XCTAssertTrue(blackout.contains("after()"))
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
            // Scan the whole file at once (newlines preserved), so string
            // state carries across lines and neither comments nor any string
            // form can hide or whitelist real code.
            let scanned = Self.codeText(of: content)
            let originalLines = content.split(separator: "\n", omittingEmptySubsequences: false)
            // Every API that reaches the real home, not just the two the app
            // once used: URL.homeDirectory and urls(for:in:) resolve the
            // account home too and would bypass CLEW_HOME just as silently
            // (review finding, 2026-08-10).
            let triggers = [
                "homeDirectoryForCurrentUser", "NSHomeDirectory(", "URL.homeDirectory",
                "urls(for:", "NSSearchPathForDirectoriesInDomains", "homeDirectory(forUser",
            ]
            for (index, code) in scanned.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                guard triggers.contains(where: code.contains) else { continue }
                let isDefinition = url.lastPathComponent == "HomeDirectory.swift"
                let isExplicitFallback = code.contains("fallback: fileManager.homeDirectoryForCurrentUser")
                if !isDefinition && !isExplicitFallback {
                    let original = index < originalLines.count ? originalLines[index] : code
                    violations.append("\(url.lastPathComponent):\(index + 1): \(original.trimmingCharacters(in: .whitespaces))")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Direct home resolution bypasses the CLEW_HOME override and can read real user data "
                + "in isolated runs. Route it through HomeDirectory.resolve(). Violations:\n"
                + violations.joined(separator: "\n"))
    }

    /// The source's code, with comments dropped and string-literal TEXT
    /// blanked (delimiters and newlines kept, so line numbers survive).
    /// A "//" inside a string is not a comment; text inside a string is not
    /// code; interpolation (\( ... ), or \#( ... ) at the matching pound
    /// count) REOPENS a code context, recursively. String state crosses
    /// newlines for multiline literals (\"\"\" and #\"\"\"), while an
    /// unterminated single-line string closes at end of line, as in Swift.
    private static func codeText(of source: String) -> String {
        enum ScanMode {
            case string(pounds: Int, multiline: Bool)
            case interpolation(parenDepth: Int)
        }
        var out: [Character] = []
        var stack: [ScanMode] = []
        let chars = Array(source)
        var i = 0

        func run(of char: Character, from index: Int) -> Int {
            var n = 0
            while index + n < chars.count, chars[index + n] == char { n += 1 }
            return n
        }

        // A string opener at `index`: optional pounds, then one quote
        // (single-line) or three (multiline).
        func openStringIfDelimiter(at index: Int) -> (pounds: Int, multiline: Bool, delimiter: String)? {
            let pounds = chars[index] == "#" ? run(of: "#", from: index) : 0
            guard index + pounds < chars.count, chars[index + pounds] == "\"" else { return nil }
            let quotes = run(of: "\"", from: index + pounds)
            let multiline = quotes >= 3
            let delimiter = String(repeating: "#", count: pounds) + String(repeating: "\"", count: multiline ? 3 : 1)
            return (pounds, multiline, delimiter)
        }

        while i < chars.count {
            let c = chars[i]
            switch stack.last {
            case .string(let pounds, let multiline):
                if c == "\n" {
                    if !multiline { stack.removeLast() }
                    out.append("\n")
                    i += 1
                } else if c == "\\" {
                    // Interpolation opener: backslash + `pounds` pounds + "(".
                    if run(of: "#", from: i + 1) >= pounds, i + 1 + pounds < chars.count, chars[i + 1 + pounds] == "(" {
                        stack.append(.interpolation(parenDepth: 1))
                        out.append(contentsOf: String(repeating: " ", count: 1 + pounds) + "(")
                        i += 2 + pounds
                    } else if pounds == 0, i + 1 < chars.count, chars[i + 1] != "\n" {
                        out.append(contentsOf: "  ")  // escape pair, e.g. \" or \\
                        i += 2
                    } else {
                        out.append(" ")  // literal backslash in a raw string
                        i += 1
                    }
                } else if c == "\"" {
                    let quotes = run(of: "\"", from: i)
                    if multiline, quotes >= 3, run(of: "#", from: i + 3) >= pounds {
                        stack.removeLast()
                        out.append(contentsOf: "\"\"\"" + String(repeating: "#", count: pounds))
                        i += 3 + pounds
                    } else if !multiline, run(of: "#", from: i + 1) >= pounds {
                        stack.removeLast()
                        out.append(contentsOf: "\"" + String(repeating: "#", count: pounds))
                        i += 1 + pounds
                    } else {
                        out.append(" ")  // a stray quote is just text
                        i += 1
                    }
                } else {
                    out.append(" ")
                    i += 1
                }
            case .interpolation(let depth):
                if let opened = openStringIfDelimiter(at: i) {
                    stack.append(.string(pounds: opened.pounds, multiline: opened.multiline))
                    out.append(contentsOf: opened.delimiter)
                    i += opened.delimiter.count
                } else if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                    skipBlockComment()
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
                    stack.append(.string(pounds: opened.pounds, multiline: opened.multiline))
                    out.append(contentsOf: opened.delimiter)
                    i += opened.delimiter.count
                } else if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                    while i < chars.count, chars[i] != "\n" { i += 1 }
                } else if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                    skipBlockComment()
                } else {
                    out.append(c)
                    i += 1
                }
            }
        }
        return String(out)

        // Swift block comments nest. Their text is dropped entirely (so a
        // stray \"\"\" or the whitelist phrase inside one is inert), but
        // newlines are kept so line numbers stay aligned. An unterminated
        // /* cannot occur in code that compiles.
        func skipBlockComment() {
            var depth = 1
            i += 2
            while i < chars.count, depth > 0 {
                if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                    depth += 1
                    i += 2
                } else if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "/" {
                    depth -= 1
                    i += 2
                } else {
                    if chars[i] == "\n" { out.append("\n") }
                    i += 1
                }
            }
        }
    }
}
