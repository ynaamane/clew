// Prints the CGWindowID of the on-screen library window owned by the given
// pid (with `--bounds`: "id x y"), or exits 2 if absent. Used by
// record-app-tour.sh to make sure only the demo instance's own window is ever
// captured.
import CoreGraphics
import Foundation

var arguments = Array(CommandLine.arguments.dropFirst())
let wantBounds = arguments.first == "--bounds"
if wantBounds { arguments.removeFirst() }
guard let pidArg = arguments.first, let target = Int(pidArg) else {
    FileHandle.standardError.write("usage: find_demo_window.swift [--bounds] <pid>\n".data(using: .utf8)!)
    exit(1)
}
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list {
    guard (w["kCGWindowOwnerPID"] as? Int) == target,
          let bounds = w["kCGWindowBounds"] as? [String: Any],
          let width = bounds["Width"] as? Double, width > 400,
          let height = bounds["Height"] as? Double, height > 300,
          let x = bounds["X"] as? Double,
          let y = bounds["Y"] as? Double,
          let num = w["kCGWindowNumber"] as? Int
    else { continue }
    print(wantBounds ? "\(num) \(Int(x)) \(Int(y))" : "\(num)")
    exit(0)
}
exit(2)
