// Gracefully replace this application across build locations, then launch once.
// Usage: swift tool/restart_macos_app.swift /absolute/path/to/PVZ Formation Editor.app
import Cocoa

guard CommandLine.arguments.count == 2 ||
      (CommandLine.arguments.count == 3 && CommandLine.arguments[2] == "--quit-only") else {
  fputs("Usage: restart_macos_app.swift /path/to/PVZ Formation Editor.app [--quit-only]\n", stderr)
  exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
guard url.pathExtension == "app", let bundle = Bundle(url: url),
      let identifier = bundle.bundleIdentifier,
      identifier == "com.xiaomeng.pvz.formation.macos",
      let executable = bundle.executableURL,
      FileManager.default.isExecutableFile(atPath: executable.path) else {
  fputs("Expected a built PVZ Studio app bundle\n", stderr); exit(2)
}
func matchingApps() -> [NSRunningApplication] {
  [identifier, "com.example.pvzFormationEditor"].flatMap {
    NSRunningApplication.runningApplications(withBundleIdentifier: $0)
  }.filter {
    $0.executableURL?.lastPathComponent == executable.lastPathComponent
  }
}
let previous = matchingApps()
for app in previous {
  guard app.terminate() else {
    fputs("Could not request graceful quit; no replacement launched\n", stderr); exit(3)
  }
}
let deadline = Date().addingTimeInterval(15)
while !matchingApps().isEmpty && Date() < deadline {
  RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
guard matchingApps().isEmpty else {
  fputs("Existing app has not finished saving/quitting; no replacement launched\n", stderr)
  exit(4)
}
if CommandLine.arguments.count == 3 {
  print("Gracefully closed \(previous.count) instance(s); no replacement launched")
  exit(0)
}
// Updating a bundle at the same path can leave Dock using an old or wrapped
// Launch Services icon. Refresh only this bundle from its shipped artwork.
if let iconURL = bundle.url(forResource: "AppIcon", withExtension: "icns"),
   let icon = NSImage(contentsOf: iconURL), icon.isValid {
  if !NSWorkspace.shared.setIcon(icon, forFile: url.path, options: []) {
    fputs("Could not refresh Dock icon; launching with the bundled icon\n", stderr)
  }
}
let launch = Process()
launch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
launch.arguments = [url.path]
try launch.run()
launch.waitUntilExit()
guard launch.terminationStatus == 0 else { exit(launch.terminationStatus) }
print("Replaced \(previous.count) previous instance(s); launched one updated app")
