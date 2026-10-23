// AX inspection for an explicit isolated QA pid; global keyboard events require that exact app to remain frontmost (native panels use a remote service).
import Cocoa
import ApplicationServices

guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
  fputs("BLOCKED: Accessibility or event-posting permission unavailable\n", stderr); exit(2)
}
guard let raw = ProcessInfo.processInfo.environment["PVZ_QA_PID"], let process = Int32(raw),
      let app = NSRunningApplication(processIdentifier: process),
      app.bundleURL?.resolvingSymlinksInPath().path.hasPrefix(URL(fileURLWithPath: "/tmp/pvz-full-file-dialog-build/").resolvingSymlinksInPath().path + "/") == true else {
  fputs("Refusing events: explicit isolated QA app pid required\n", stderr); exit(3)
}
let base = URL(fileURLWithPath: "/tmp/pvz-native-file-dialog")
let ax = AXUIElementCreateApplication(process)
func value(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
  var out: CFTypeRef?; guard AXUIElementCopyAttributeValue(e, key as CFString, &out) == .success else { return nil }; return out
}
func sheet(_ e: AXUIElement, _ depth: Int = 0) -> AXUIElement? {
  if depth > 10 { return nil }
  if value(e, kAXRoleAttribute) as? String == kAXSheetRole { return e }
  for child in value(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
    if let found = sheet(child, depth + 1) { return found }
  }
  return nil
}
func sheetCount(_ e: AXUIElement, _ depth: Int = 0) -> Int {
  if depth > 12 { return 0 }
  return (value(e, kAXRoleAttribute) as? String == kAXSheetRole ? 1 : 0) +
    (value(e, kAXChildrenAttribute) as? [AXUIElement] ?? []).reduce(0) { $0 + sheetCount($1, depth + 1) }
}
func allSheets(_ e: AXUIElement, _ depth: Int = 0) -> [AXUIElement] {
  if depth > 12 { return [] }
  return (value(e, kAXRoleAttribute) as? String == kAXSheetRole ? [e] : []) +
    (value(e, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap { allSheets($0, depth + 1) }
}
func textField(_ e: AXUIElement, _ depth: Int = 0) -> AXUIElement? {
  if depth > 12 { return nil }
  if value(e, kAXRoleAttribute) as? String == kAXTextFieldRole { return e }
  for child in value(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
    if let result = textField(child, depth + 1) { return result }
  }
  return nil
}
func button(_ e: AXUIElement, _ title: String, _ depth: Int = 0) -> AXUIElement? {
  if depth > 12 { return nil }
  if value(e, kAXRoleAttribute) as? String == kAXButtonRole && value(e, kAXTitleAttribute) as? String == title { return e }
  for child in value(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
    if let found = button(child, title, depth + 1) { return found }
  }
  return nil
}
func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
  for down in [true, false] {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
    event?.flags = flags; guard NSWorkspace.shared.frontmostApplication?.processIdentifier == process else {
      fputs("Refusing global key: QA app is not frontmost\n", stderr); exit(4)
    }
    event?.post(tap: .cghidEventTap)
  }
  Thread.sleep(forTimeInterval: 0.2)
}
let deadline = Date().addingTimeInterval(150)
var previous = -1
var evidence = [[String: Any]]()
while Date() < deadline {
  if let data = try? Data(contentsOf: base.appendingPathComponent("report.json")),
     let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any], report["pid"] as? Int32 == process {
    try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted]).write(to: base.appendingPathComponent("driver-report.json"), options: .atomic)
    print(report); exit(report["status"] as? String == "pass" ? 0 : 1)
  }
  if let data = try? Data(contentsOf: base.appendingPathComponent("request.json")),
     let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
     request["pid"] as? Int32 == process,
     let id = request["id"] as? Int, id != previous,
     let action = request["action"] as? String, let path = request["path"] as? String,
     let panel = sheet(ax),
     value(panel, kAXDescriptionAttribute) as? String == (action == "open" ? "open" : "save") {
    app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    evidence.append(["id": id, "action": action, "pid": process, "role": value(panel, kAXRoleAttribute) as? String ?? "", "title": value(panel, kAXTitleAttribute) as? String ?? ""])
    Thread.sleep(forTimeInterval: 1.0)
    if action == "cancel" {
      if let cancel = button(panel, "Cancel") { AXUIElementPerformAction(cancel, kAXPressAction as CFString) }
    } else if action == "save" {
      if let save = button(panel, "Save") { AXUIElementPerformAction(save, kAXPressAction as CFString) }
    }
    else {
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == process else {
        fputs("Refusing events: QA app is not frontmost\n", stderr); exit(4)
      }
      key(5, [.maskCommand, .maskShift]); Thread.sleep(forTimeInterval: 0.7)
      guard sheetCount(ax) >= 2 else { fputs("Go-to-folder sheet did not appear; no path typed\n", stderr); exit(5) }
      guard let goTo = allSheets(ax).last, let field = textField(goTo),
            AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, path as CFString) == .success else {
        fputs("Cannot set QA path field\n", stderr); exit(6)
      }
      evidence.append(["id": id, "pathField": value(field, kAXValueAttribute) as? String ?? ""])
      Thread.sleep(forTimeInterval: 0.4); key(36)
      Thread.sleep(forTimeInterval: 0.8); key(36)
    }
    try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted]).write(to: base.appendingPathComponent("driver-report.json"), options: .atomic)
    previous = id
  }
  Thread.sleep(forTimeInterval: 0.05)
}
fputs("Timed out waiting for QA file panels\n", stderr); exit(1)
