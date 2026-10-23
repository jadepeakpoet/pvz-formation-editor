import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
  private var terminationPending = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // FlutterAppDelegate replaces the primary title with CFBundleName here,
    // after MainFlutterWindow.awakeFromNib has already configured it.
    super.applicationDidFinishLaunching(notification)
    let primary = mainFlutterWindow as? MainFlutterWindow
      ?? NSApp.windows.compactMap { $0 as? MainFlutterWindow }.first
    primary?.title = "植物大战僵尸布阵器"
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminationPending { return .terminateLater }
    guard let channel = sender.windows.compactMap({ $0 as? MainFlutterWindow }).first?.lifecycleChannel else {
      return .terminateNow
    }
    terminationPending = true
    channel.invokeMethod("prepareExit", arguments: nil) { [weak self, weak sender] value in
      DispatchQueue.main.async {
        self?.terminationPending = false
        // Errors and missing handlers cannot be mistaken for successful persistence.
        sender?.reply(toApplicationShouldTerminate: (value as? Bool) == true)
      }
    }
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
}
