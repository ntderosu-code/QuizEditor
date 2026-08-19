import Cocoa
import ApplicationServices

// A small accessibility + CGEvent driver for exercising the running app from a
// script. Used by Scripts/ui-crash-regression.sh; there is no CI, so the UI
// regressions it covers are checked by running that script by hand.
//
// Needs Accessibility permission for whichever terminal runs it
// (System Settings ▸ Privacy & Security ▸ Accessibility).
//
// Usage:
//   uidriver tree [maxDepth]         dump the front window's accessibility tree
//   uidriver focused                 describe the focused UI element
//   uidriver click X Y               left click at a screen point
//   uidriver rightclick X Y          right click at a screen point
//   uidriver drag X1 Y1 X2 Y2        press, creep past the drag threshold, drag
//   uidriver value <axPath>          print one element, addressed by index path

let appName = "QuizEditorApp"

func pid(of name: String) -> pid_t? {
    NSWorkspace.shared.runningApplications.first { $0.executableURL?.lastPathComponent == name }?.processIdentifier
}

func attr(_ el: AXUIElement, _ key: String) -> CFTypeRef? {
    var out: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, key as CFString, &out) == .success else { return nil }
    return out
}

func str(_ el: AXUIElement, _ key: String) -> String {
    guard let v = attr(el, key) else { return "" }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}

func point(_ el: AXUIElement, _ key: String) -> CGPoint? {
    guard let v = attr(el, key) else { return nil }
    var p = CGPoint.zero
    guard AXValueGetValue(v as! AXValue, .cgPoint, &p) else { return nil }
    return p
}

func size(_ el: AXUIElement, _ key: String) -> CGSize? {
    guard let v = attr(el, key) else { return nil }
    var s = CGSize.zero
    guard AXValueGetValue(v as! AXValue, .cgSize, &s) else { return nil }
    return s
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}

func describe(_ el: AXUIElement, path: String, depth: Int) -> String {
    let pad = String(repeating: "  ", count: depth)
    let role = str(el, kAXRoleAttribute as String)
    let sub = str(el, kAXSubroleAttribute as String)
    let name = str(el, kAXTitleAttribute as String)
    let desc = str(el, kAXDescriptionAttribute as String)
    var val = str(el, kAXValueAttribute as String)
    if val.count > 50 { val = String(val.prefix(50)) + "…" }
    var geo = ""
    if let p = point(el, kAXPositionAttribute as String), let s = size(el, kAXSizeAttribute as String) {
        geo = " @\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height))"
        geo += " ctr=\(Int(p.x + s.width / 2)),\(Int(p.y + s.height / 2))"
    }
    var line = "\(pad)\(role)"
    if !sub.isEmpty { line += "/\(sub)" }
    if !name.isEmpty { line += " title=\"\(name)\"" }
    if !desc.isEmpty { line += " desc=\"\(desc)\"" }
    if !val.isEmpty { line += " val=\"\(val)\"" }
    line += geo + "  <\(path)>"
    return line
}

func walk(_ el: AXUIElement, path: String, depth: Int, maxDepth: Int, into out: inout [String]) {
    out.append(describe(el, path: path, depth: depth))
    guard depth < maxDepth else { return }
    for (i, c) in children(el).enumerated() {
        walk(c, path: "\(path).\(i)", depth: depth + 1, maxDepth: maxDepth, into: &out)
    }
}

func frontWindow(_ app: AXUIElement) -> AXUIElement? {
    if let w = attr(app, kAXFocusedWindowAttribute as String) { return (w as! AXUIElement) }
    return (attr(app, kAXWindowsAttribute as String) as? [AXUIElement])?.first
}

func resolve(_ root: AXUIElement, path: String) -> AXUIElement? {
    var el = root
    for part in path.split(separator: ".").dropFirst() {
        guard let i = Int(part) else { return nil }
        let kids = children(el)
        guard i < kids.count else { return nil }
        el = kids[i]
    }
    return el
}

func post(_ e: CGEvent?) { e?.post(tap: .cghidEventTap) }

func click(_ x: Double, _ y: Double) {
    let p = CGPoint(x: x, y: y)
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left))
    usleep(60_000)
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left))
    usleep(60_000)
    post(CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left))
}

func drag(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
    let src = CGEventSource(stateID: .hidSystemState)
    func move(_ type: CGEventType, _ p: CGPoint) {
        let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)
        e?.setIntegerValueField(.mouseEventClickState, value: 1)
        e?.post(tap: .cghidEventTap)
    }
    let start = CGPoint(x: x1, y: y1)
    move(.mouseMoved, start)
    usleep(400_000)
    move(.leftMouseDown, start)
    usleep(500_000)
    // Creep past the drag threshold first; Finder ignores a drag that jumps.
    for i in 1...8 {
        move(.leftMouseDragged, CGPoint(x: x1 + Double(i) * 2, y: y1 + Double(i) * 2))
        usleep(60_000)
    }
    let steps = 60
    let bx = x1 + 16, by = y1 + 16
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        move(.leftMouseDragged, CGPoint(x: bx + (x2 - bx) * t, y: by + (y2 - by) * t))
        usleep(30_000)
    }
    // Hover over the target so the drop destination highlights before release.
    for _ in 1...10 {
        move(.leftMouseDragged, CGPoint(x: x2, y: y2))
        usleep(60_000)
    }
    move(.leftMouseUp, CGPoint(x: x2, y: y2))
    usleep(200_000)
}

guard let p = pid(of: appName) else { fputs("\(appName) is not running\n", stderr); exit(1) }
let app = AXUIElementCreateApplication(p)
let args = CommandLine.arguments

switch args.count > 1 ? args[1] : "tree" {
case "tree":
    let maxDepth = args.count > 2 ? Int(args[2])! : 20
    guard let w = frontWindow(app) else { fputs("no window\n", stderr); exit(1) }
    var out: [String] = []
    walk(w, path: "w", depth: 0, maxDepth: maxDepth, into: &out)
    print(out.joined(separator: "\n"))
case "focused":
    guard let f = attr(app, kAXFocusedUIElementAttribute as String) else { print("no focused element"); exit(0) }
    let el = f as! AXUIElement
    print(describe(el, path: "focused", depth: 0))
    print("selectedText=\"\(str(el, kAXSelectedTextAttribute as String))\"")
    print("selectedRange=\(str(el, kAXSelectedTextRangeAttribute as String))")
    if let v = attr(el, kAXSelectedTextRangeAttribute as String) {
        var r = CFRange()
        if AXValueGetValue(v as! AXValue, .cfRange, &r) { print("caret loc=\(r.location) len=\(r.length)") }
    }
case "value":
    guard let w = frontWindow(app), let el = resolve(w, path: args[2]) else { fputs("not found\n", stderr); exit(1) }
    print(describe(el, path: args[2], depth: 0))
case "rightclick":
    let p = CGPoint(x: Double(args[2])!, y: Double(args[3])!)
    post(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .right))
    usleep(120_000)
    post(CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: p, mouseButton: .right))
    usleep(120_000)
    post(CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: p, mouseButton: .right))
case "click":
    click(Double(args[2])!, Double(args[3])!)
case "drag":
    drag(Double(args[2])!, Double(args[3])!, Double(args[4])!, Double(args[5])!)
default:
    fputs("unknown command\n", stderr); exit(1)
}
