import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct WindowTarget {
    let id: CGWindowID
    let pid: pid_t
    let owner: String
    let bounds: CGRect
}

func onScreenWindows(ownedBy owner: String) -> [WindowTarget] {
    guard let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return [] }

    return list.compactMap { entry in
        guard (entry[kCGWindowOwnerName as String] as? String) == owner,
              let id = entry[kCGWindowNumber as String] as? CGWindowID,
              let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
              let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
              bounds.width > 200, bounds.height > 200
        else { return nil }
        return WindowTarget(id: id, pid: pid, owner: owner, bounds: bounds)
    }
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

func frame(of element: AXUIElement) -> CGRect? {
    guard let rawPosition = attribute(element, kAXPositionAttribute),
          let rawSize = attribute(element, kAXSizeAttribute),
          CFGetTypeID(rawPosition) == AXValueGetTypeID(),
          CFGetTypeID(rawSize) == AXValueGetTypeID()
    else { return nil }

    var origin = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(unsafeBitCast(rawPosition, to: AXValue.self), .cgPoint, &origin)
    AXValueGetValue(unsafeBitCast(rawSize, to: AXValue.self), .cgSize, &size)
    return CGRect(origin: origin, size: size)
}

func describe(_ element: AXUIElement, depth: Int, into lines: inout [String], limit: Int) {
    guard depth <= limit else { return }

    let role = stringAttribute(element, kAXRoleAttribute) ?? "?"
    let title = stringAttribute(element, kAXTitleAttribute)
    let value = stringAttribute(element, kAXValueAttribute)
    let identifier = stringAttribute(element, kAXIdentifierAttribute)
    let box = frame(of: element)

    var parts = [String(repeating: "  ", count: depth) + role]
    if let title, !title.isEmpty { parts.append("\"\(title.prefix(90))\"") }
    if let value, !value.isEmpty, value != title { parts.append("=\"\(value.prefix(90))\"") }
    if let identifier, !identifier.isEmpty { parts.append("#\(identifier)") }
    if let box {
        parts.append(String(format: "@%.0f,%.0f %.0fx%.0f", box.minX, box.minY, box.width, box.height))
    }

    let hasContent = !(title ?? "").isEmpty || !(value ?? "").isEmpty || !(identifier ?? "").isEmpty
    if hasContent || depth <= 2 {
        lines.append(parts.joined(separator: " "))
    }

    guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
    for child in children.prefix(80) {
        describe(child, depth: depth + 1, into: &lines, limit: limit)
    }
}

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Clew"
let outputDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/ui-evidence"
let depthLimit = CommandLine.arguments.count > 3 ? (Int(CommandLine.arguments[3]) ?? 12) : 12

try? FileManager.default.createDirectory(
    atPath: outputDir, withIntermediateDirectories: true)

let windows = onScreenWindows(ownedBy: owner)
guard let target = windows.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
else {
    FileHandle.standardError.write(Data("NO_WINDOW owner=\(owner)\n".utf8))
    exit(2)
}

print("WINDOW owner=\(target.owner) id=\(target.id) pid=\(target.pid) "
    + String(format: "%.0fx%.0f at %.0f,%.0f", target.bounds.width, target.bounds.height,
             target.bounds.minX, target.bounds.minY))

let axTrusted = AXIsProcessTrusted()
print("AX_TRUSTED \(axTrusted)")

var lines: [String] = []
if axTrusted {
    let app = AXUIElementCreateApplication(target.pid)
    if let axWindows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] {
        for (index, window) in axWindows.enumerated() {
            lines.append("=== AXWindow \(index) ===")
            describe(window, depth: 0, into: &lines, limit: depthLimit)
        }
    } else {
        lines.append("(no AXWindows returned; the app may expose none while accessory-policy)")
    }
} else {
    lines.append("(Accessibility permission not granted to this process — tree unavailable)")
}

let treePath = outputDir + "/axtree.txt"
try? lines.joined(separator: "\n").write(toFile: treePath, atomically: true, encoding: .utf8)
print("AX_TREE \(treePath) lines=\(lines.count)")
print("WINDOW_ID \(target.id)")
