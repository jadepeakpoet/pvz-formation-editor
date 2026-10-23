// Sends one real click for each request from toolbox_tabs_native.dart.
import Cocoa
import ApplicationServices

guard CGPreflightPostEventAccess() else {
  fputs("Native pointer permission unavailable; no events posted\n", stderr)
  exit(2)
}
let expectedPID = ProcessInfo.processInfo.environment["PVZ_QA_PID"].flatMap(Int.init)
let base = URL(fileURLWithPath: "/tmp/pvz-toolbox-tabs-first-click")
let end = Date().addingTimeInterval(100)
var previous = -1
while Date() < end {
  if let data = try? Data(contentsOf: base.appendingPathComponent("report.json")),
     let report = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
     expectedPID == nil || report["pid"] as? Int == expectedPID { exit(0) }
  if let data = try? Data(contentsOf: base.appendingPathComponent("request.json")),
     let request = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
     let id = request["id"] as? Int, id != previous,
     let pid = request["pid"] as? Int,
     expectedPID == nil || pid == expectedPID,
     let app = NSRunningApplication(processIdentifier: pid_t(pid)),
     app.bundleURL?.lastPathComponent == "pvz_formation_editor.app",
     let target = request["target"] as? [String: Double],
     let frame = request["frame"] as? [Double], frame.count == 4,
     let x = target["x"], let y = target["y"], let screen = NSScreen.screens.first {
    var outsideAppActive = false
    if request["operation"] as? String == "outside-app" {
      guard let external = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
        fputs("Finder unavailable for external-app focus test\n", stderr); exit(3)
      }
      external.activate(options: [.activateIgnoringOtherApps])
      Thread.sleep(forTimeInterval: 0.15)
      outsideAppActive = external.isActive
      guard outsideAppActive else { fputs("External app did not activate\n", stderr); exit(4) }
    } else {
      app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
    Thread.sleep(forTimeInterval: 0.15)
    // Flutter targets are points from the content top-left; titlebar is 32pt.
    let point = CGPoint(x: frame[0] + x,
        y: screen.frame.maxY - frame[1] - frame[3] + 32 + y)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
        mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
        mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    if request["operation"] as? String == "drag-main" {
      for step in 1...10 {
        let destination = CGPoint(x: point.x - CGFloat(step) * 4,
                                  y: point.y + CGFloat(step) * 2)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
            mouseCursorPosition: destination, mouseButton: .left)?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.02)
      }
    }
    let released = request["operation"] as? String == "drag-main"
        ? CGPoint(x: point.x - 40, y: point.y + 20) : point
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
        mouseCursorPosition: released, mouseButton: .left)?.post(tap: .cghidEventTap)
    try JSONSerialization.data(withJSONObject: ["id": id, "outsideAppActive": outsideAppActive]).write(
        to: base.appendingPathComponent("click.json"), options: .atomic)
    previous = id
  }
  Thread.sleep(forTimeInterval: 0.05)
}
exit(1)
