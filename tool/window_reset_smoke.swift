import Foundation

// Compile the production geometry method into isolated AppKit windows.
let source = try String(contentsOfFile: "macos/Runner/MainFlutterWindow.swift", encoding: .utf8)
let start = source.range(of: "  private func resetWindowPositions(")!.lowerBound
let end = source.range(of: "\n  private func positionSidebarOnce()", range: start..<source.endIndex)!.lowerBound
let method = String(source[start..<end]).replacingOccurrences(of: "private func", with: "func")
precondition(source.components(separatedBy: "case \"resetWindowPositions\":").count == 4,
             "Reset action must be exposed by main, toolbox and library channels")
let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pvz-window-reset-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
let report = folder.appendingPathComponent("report.txt")
let fixture = """
import Cocoa
let reportPath = "\(report.path)"
final class Editor: NSWindow {
  var sidebarWindow: NSWindow?
  var sidebarInitiallyPositioned = false
  var sidebarPlacement = ""
\(method)
}
func pump() { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() { try? "FAIL: \\(message)".write(toFile: reportPath, atomically: true, encoding: .utf8); exit(1) }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.finishLaunching()
let editor = Editor(contentRect: NSRect(x: -1000, y: -1000, width: 810, height: 695), styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
let panel = NSWindow(contentRect: NSRect(x: 9000, y: 9000, width: 410, height: 695), styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
for window in [editor, panel] { window.isReleasedWhenClosed = false }
editor.sidebarWindow = panel
let editorSize = editor.frame.size, panelSize = panel.frame.size
let available = NSRect(x: -1600, y: 80, width: 1600, height: 1000)
check(editor.resetWindowPositions(in: available), "Reset should succeed")
check(!editor.isVisible && !panel.isVisible, "Reset must not show hidden windows")
check(editor.frame.size == editorSize && panel.frame.size == panelSize, "Reset must preserve fixed sizes")
check(available.contains(editor.frame) && available.contains(panel.frame), "Frames must stay inside selected screen")
check(abs(panel.frame.minX - editor.frame.maxX - 8) < 0.01, "Initial pair should have eight-pixel gap")
check(abs(panel.frame.maxY - editor.frame.maxY) < 0.01, "Initial pair should align at top")
check(editor.sidebarInitiallyPositioned && editor.sidebarPlacement == "independent", "Automatic placement must not undo reset")
editor.orderFront(nil)
panel.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
pump()
let key = app.keyWindow
let visibleEditor = editor.isVisible, visiblePanel = panel.isVisible
let small = NSRect(x: 40, y: 30, width: 900, height: 600)
check(editor.resetWindowPositions(in: small), "Small-screen reset should succeed")
pump()
check(app.keyWindow === key, "Reset must not change keyboard focus")
check(editor.isVisible == visibleEditor && panel.isVisible == visiblePanel, "Reset must preserve visible state")
check(editor.frame.maxY <= small.maxY && panel.frame.maxY <= small.maxY, "Small screens must retain visible title bars")
check(editor.frame.minX >= small.minX && panel.frame.minX >= small.minX, "Small-screen left edges must stay visible")
editor.miniaturize(nil)
for _ in 0..<20 {
  pump()
  if editor.isMiniaturized { break }
}
panel.miniaturize(nil)
for _ in 0..<20 {
  pump()
  if panel.isMiniaturized { break }
}
check(editor.isMiniaturized && panel.isMiniaturized, "Fixture minimization failed")
check(editor.resetWindowPositions(in: available), "Minimized reset should succeed")
pump()
check(editor.isMiniaturized && panel.isMiniaturized, "Reset must preserve minimized state")
editor.sidebarWindow = nil
check(editor.resetWindowPositions(in: available), "Editor-only reset should succeed")
for window in [editor, panel] { window.orderOut(nil); window.close() }
try! "PASS window position reset: screen bounds, initial pairing, fixed sizes, hidden/minimized state, focus and three channel hooks".write(toFile: reportPath, atomically: true, encoding: .utf8)
"""
let script = folder.appendingPathComponent("main.swift")
try fixture.write(to: script, atomically: true, encoding: .utf8)
let app = folder.appendingPathComponent("ResetSmoke.app")
let macOS = app.appendingPathComponent("Contents/MacOS")
try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
let info: [String: Any] = [
  "CFBundleExecutable": "ResetSmoke", "CFBundleName": "PVZ Reset Test",
  "CFBundleIdentifier": "org.pvz.reset-smoke.\(UUID().uuidString)",
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
compiler.arguments = ["-target", target, script.path, "-o", macOS.appendingPathComponent("ResetSmoke").path]
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
