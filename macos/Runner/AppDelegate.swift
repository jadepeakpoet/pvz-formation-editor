import Cocoa
import FlutterMacOS

@main
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

  @IBAction func showAbout(_ sender: Any?) {
    NSApp.orderFrontStandardAboutPanel(options: [
      .credits: NSAttributedString(string: "作者 / Author: 越小梦\n官网：https://xmpvz.pages.dev\n使用文档：https://xmpvz.pages.dev/docs/\nGitHub：https://github.com/jadepeakpoet/pvz-formation-editor\n交流 QQ 群：425175276\n\n主要参考 / Primary reference\njspvz 网页布阵器 — LonelyStar（囧丫乙）\nhttp://jspvz.com/ArrayDesign/\n以网页布阵器的功能和界面为基础，迁移到本地应用，并增强存档管理、桌面交互和游戏阵型读写等能力。\n\n技术参考 / Technical references\nPvZ Toolkit — lmintlcx\nhttps://pvz.lmintlcx.com/toolkit/\nPvZ-Portable — wszqkzqk 及社区贡献者\nhttps://github.com/wszqkzqk/PvZ-Portable\n\n致谢 / Thanks\nlmintlcx（PvZ Toolkit）\nwszqkzqk 及社区贡献者（PvZ-Portable）\n囧丫乙（LonelyStar）\nPopCap Games\nFlutter / Dart")
    ])
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
