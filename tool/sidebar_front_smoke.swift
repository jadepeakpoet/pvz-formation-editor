import Foundation

// Run the production ordering method in isolated AppKit windows. No product
// application instance or user document is opened by this harness.
let source = try String(contentsOfFile: "macos/Runner/MainFlutterWindow.swift", encoding: .utf8)
let start = source.range(of: "  private func queueVisibleEditorFront() {")!.lowerBound
let end = source.range(of: "\n  private func queueVisibleSidebarFront()", range: start..<source.endIndex)!.lowerBound
let method = String(source[start..<end]).replacingOccurrences(of: "private func", with: "func")
for hook in [
  "panel.onForegroundRequest = { [weak self] in self?.queueVisibleEditorFront() }",
  "else if target === sidebarWindow { queueVisibleEditorFront() }",
  "else if notification.object as? NSWindow === sidebarWindow",
  "if event.type == .leftMouseDown { onForegroundRequest?() }"
] {
  precondition(source.contains(hook), "Missing sidebar foreground hook: \(hook)")
}
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pvz-sidebar-front-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
let report = folder.appendingPathComponent("report.txt")
let fixture = """
import Cocoa
let reportPath = "\(report.path)"
final class Editor: NSWindow {
  var sidebarWindow: NSWindow?
  var editorFrontQueued = false
\(method)
}
func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.15)) }
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() { try? "FAIL: \\(message)".write(toFile: reportPath, atomically: true, encoding: .utf8); exit(1) }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.finishLaunching()
let rect = NSRect(x: 90, y: 90, width: 220, height: 120)
let editor = Editor(contentRect: rect, styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
let panel = NSWindow(contentRect: rect.offsetBy(dx: 240, dy: 0), styleMask: [.titled], backing: .buffered, defer: false)
let blocker = NSWindow(contentRect: rect.offsetBy(dx: 50, dy: 25), styleMask: [.titled], backing: .buffered, defer: false)
for window in [editor, panel, blocker] { window.isReleasedWhenClosed = false }
editor.sidebarWindow = panel
let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 120, height: 24))
panel.contentView!.addSubview(field)
editor.orderFront(nil)
panel.orderFront(nil)
blocker.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
pump()
panel.makeKeyAndOrderFront(nil)
panel.makeFirstResponder(field)
pump()
let responder = panel.firstResponder
editor.queueVisibleEditorFront()
editor.queueVisibleEditorFront()
pump()
check(app.isActive, "Harness application should be active")
check(panel.isKeyWindow, "Editor ordering stole sidebar key focus")
check(panel.firstResponder === responder, "Editor ordering changed sidebar responder")
let order = app.orderedWindows
let p = order.firstIndex(where: { $0 === panel })!
let e = order.firstIndex(where: { $0 === editor })!
let b = order.firstIndex(where: { $0 === blocker })!
check(p < e && e < b, "Editor should be raised immediately behind sidebar")

editor.orderOut(nil)
editor.queueVisibleEditorFront()
pump()
check(!editor.isVisible, "A hidden editor must stay hidden")
editor.orderFront(nil)
editor.miniaturize(nil)
pump()
panel.makeKeyAndOrderFront(nil)
editor.queueVisibleEditorFront()
pump()
check(editor.isMiniaturized, "A minimized editor must stay minimized")
editor.deminiaturize(nil)
pump()
panel.orderOut(nil)
editor.queueVisibleEditorFront()
pump()
check(!panel.isVisible, "A hidden sidebar must not be reopened")
panel.orderFront(nil)
blocker.makeKeyAndOrderFront(nil)
pump()
let previous = app.orderedWindows.map { $0.windowNumber }
editor.queueVisibleEditorFront()
pump()
check(app.orderedWindows.map { $0.windowNumber } == previous,
      "A sidebar without key focus must not reorder its companion")
for window in [editor, panel, blocker] { window.orderOut(nil); window.close() }
try! "PASS actual AppKit companion ordering, retained key/responder, coalescing, hidden/minimized and non-key guards; source click/key/activation hooks present".write(toFile: reportPath, atomically: true, encoding: .utf8)
"""
let script = folder.appendingPathComponent("main.swift")
try fixture.write(to: script, atomically: true, encoding: .utf8)
let app = folder.appendingPathComponent("FrontSmoke.app")
let macOS = app.appendingPathComponent("Contents/MacOS")
try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
let info: [String: Any] = [
  "CFBundleExecutable": "FrontSmoke", "CFBundleName": "PVZ Window Test",
  "CFBundleIdentifier": "org.pvz.front-smoke.\(UUID().uuidString)",
  "CFBundlePackageType": "APPL", "NSHighResolutionCapable": true,
]
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    .write(to: app.appendingPathComponent("Contents/Info.plist"))
let compiler = Process()
compiler.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
#if arch(arm64)
let target = "arm64-apple-macosx13.0"
#else
let target = "x86_64-apple-macosx13.0"
#endif
compiler.arguments = ["-target", target, script.path, "-o", macOS.appendingPathComponent("FrontSmoke").path]
var environment = ProcessInfo.processInfo.environment
environment["SWIFT_MODULE_CACHE_PATH"] = "/tmp/pvz-swift-module-cache"
environment["CLANG_MODULE_CACHE_PATH"] = "/tmp/pvz-clang-module-cache"
compiler.environment = environment
try compiler.run()
compiler.waitUntilExit()
if compiler.terminationStatus != 0 { exit(compiler.terminationStatus) }
let launch = Process()
launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
launch.arguments = ["-W", app.path]
try launch.run()
launch.waitUntilExit()
let result = (try? String(contentsOf: report, encoding: .utf8)) ?? "FAIL: AppKit fixture did not report"
print(result)
exit(result.hasPrefix("PASS") ? 0 : 1)
