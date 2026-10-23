// External trusted-pointer companion for tool/sidebar_windows.dart.
// Run after opening its QA app:
// xcrun swift -module-cache-path /tmp/pvz-sidebar-swift-cache tool/sidebar_pointer_driver.swift
// macOS gives GUI-child processes different event permissions; never replace
// a denied pointer with a method-channel mode change and call it a click.
import Cocoa
import CoreGraphics
import Foundation

guard CGPreflightPostEventAccess() else {
  fputs("The current CLI process has no native-pointer permission. No events posted.\n", stderr)
  exit(1)
}
let base = URL(fileURLWithPath: "/tmp/pvz-sidebar-native", isDirectory: true)
let meta = try JSONSerialization.jsonObject(with: Data(contentsOf: base.appendingPathComponent("meta.json"))) as! [String: Any]
let run = meta["run"] as! String
let pid = meta["pid"] as! Int
let validRun = run.range(of: #"^[0-9]+-[0-9]+$"#, options: .regularExpression) != nil
guard validRun, let app = NSRunningApplication(processIdentifier: pid_t(pid)),
      let bundle = app.bundleURL?.path, bundle.contains("/pvz-native-sidebar-qa/") else {
  fatalError("Not the expected temporary QA application")
}
let folder = base.appendingPathComponent(run, isDirectory: true)
let request = folder.appendingPathComponent("header-request.json")
let reply = folder.appendingPathComponent("header-ack.json")
let deadline = Date().addingTimeInterval(90)
var previous = -1
while Date() < deadline {
  if FileManager.default.fileExists(atPath: folder.appendingPathComponent("done.json").path) {
    print("Native sidebar QA finished")
    exit(0)
  }
  if let data = try? Data(contentsOf: request),
     let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
     let id = value["id"] as? Int, id != previous {
    guard value["pid"] as? Int == pid, let x = value["x"] as? Double,
          let y = value["y"] as? Double, x.isFinite, y.isFinite else {
      fatalError("Invalid QA pointer request")
    }
    app.activate(options: [])
    Thread.sleep(forTimeInterval: 0.12)
    let point = CGPoint(x: x, y: y)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    let ack: [String: Any] = ["id": id, "pointerClick": true,
                              "driver": "tool/sidebar_pointer_driver.swift"]
    try JSONSerialization.data(withJSONObject: ack).write(to: reply, options: .atomic)
    previous = id
    print("Clicked native segment request \(id) at \(x),\(y)")
  }
  Thread.sleep(forTimeInterval: 0.08)
}
fputs("Timed out waiting for native sidebar QA completion\n", stderr)
exit(1)
