// Tiny cursor helper for record-app-tour.sh.
//   demo-mouse pos          -> prints "x y"
//   demo-mouse x y          -> left click at (x, y)
//   demo-mouse x y move     -> move the cursor only, never a click (used to
//                              restore the user's cursor position)
import CoreGraphics
import Foundation

let args = CommandLine.arguments
if args.count == 2 && args[1] == "pos" {
    let loc = CGEvent(source: nil)!.location
    print("\(loc.x) \(loc.y)")
    exit(0)
}
guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else {
    FileHandle.standardError.write("usage: demo-mouse pos | demo-mouse x y [move]\n".data(using: .utf8)!)
    exit(1)
}
let pt = CGPoint(x: x, y: y)
if args.count > 3 && args[3] == "move" {
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)!
        .post(tap: .cghidEventTap)
    exit(0)
}
for type in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pt, mouseButton: .left)!
        .post(tap: .cghidEventTap)
    usleep(60_000)
}
