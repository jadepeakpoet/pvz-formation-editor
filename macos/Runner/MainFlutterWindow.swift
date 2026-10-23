import Cocoa
import AVFoundation
import FlutterMacOS

// Track the editor even while its separate toolbox is the key window.
private final class EditorHoverTracker: NSObject {
  weak var view: NSView?
  var send: (([String: Double]?) -> Void)?
  private var tracking: NSTrackingArea?

  init(view: NSView, send: @escaping ([String: Double]?) -> Void) {
    self.view = view
    self.send = send
    super.init()
    let area = NSTrackingArea(rect: .zero,
        options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
        owner: self, userInfo: nil)
    tracking = area
    view.addTrackingArea(area)
  }

  @objc(mouseMoved:) func mouseMoved(with event: NSEvent) {
    guard let view = view else { return }
    let point = view.convert(event.locationInWindow, from: nil)
    send?(["x": Double(point.x),
           "y": Double(view.isFlipped ? point.y : view.bounds.height - point.y)])
  }
  @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
  @objc(mouseExited:) func mouseExited(with event: NSEvent) { send?(nil) }

  deinit {
    if let tracking = tracking { view?.removeTrackingArea(tracking) }
  }
}

// The first click after editing the board must also reach sidebar controls.
private final class SidebarWindow: NSWindow {
  private(set) var pointerDiagnostics: [[String: Any]] = []
  override func sendEvent(_ event: NSEvent) {
    if event.type == .leftMouseDown && !isKeyWindow && attachedSheet == nil {
      makeKey()
    }
    if event.type == .leftMouseDown || event.type == .leftMouseUp {
      let hit = contentView?.hitTest(contentView?.convert(event.locationInWindow, from: nil) ?? .zero)
      pointerDiagnostics.append([
        "type": event.type == .leftMouseDown ? "down" : "up",
        "x": event.locationInWindow.x, "y": event.locationInWindow.y,
        "key": isKeyWindow, "active": NSApp.isActive,
        "hit": hit.map { String(describing: type(of: $0)) } ?? "none",
        "next": hit?.nextResponder.map { String(describing: type(of: $0)) } ?? "none"
      ])
      if pointerDiagnostics.count > 60 { pointerDiagnostics.removeFirst() }
    }
    super.sendEvent(event)
  }
}

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  // This primary editor has a fixed product title. Flutter/AppKit may assign
  // CFBundleName later; document names are displayed inside the editor instead.
  override var title: String {
    get { super.title }
    set { super.title = englishUI ? "PVZ Formation Editor" : "植物大战僵尸布阵器" }
  }

  private var englishUI = false
  private func sidebarTitle(_ mode: String) -> String {
    if englishUI { return mode == "library" ? "Library" : "Formation Toolbox" }
    return mode == "library" ? "存档库" : "布阵器工具箱"
  }

  private(set) var lifecycleChannel: FlutterMethodChannel?
  private var audioChannel: FlutterMethodChannel?
  private var musicPlayer: AVAudioPlayer?
  private var plantingPlayer: AVAudioPlayer?
  private var plantingPlayers: [String: [AVAudioPlayer]] = [:]
  private var lastPlantingSource: String?
  private var soundVolume: Float = 0
  private var fileChannel: FlutterMethodChannel?
  private var windowsChannel: FlutterMethodChannel?
  private var toolboxChannel: FlutterMethodChannel?
  private var toolboxEngine: FlutterEngine?
  private var toolboxController: FlutterViewController?
  private var toolboxFilesChannel: FlutterMethodChannel?
  private var toolboxAudioChannel: FlutterMethodChannel?
  private var libraryEngine: FlutterEngine?
  private var libraryController: FlutterViewController?
  private var libraryChannel: FlutterMethodChannel?
  private var libraryFilesChannel: FlutterMethodChannel?
  private var libraryAudioChannel: FlutterMethodChannel?
  private var sidebarWindow: NSWindow?
  private var sidebarContainer: NSViewController?
  private var sidebarHost: NSView?
  private var sidebarMode = "toolbox"
  private var sidebarPlacement = "independent"
  private var sidebarInitiallyPositioned = false
  private var libraryDataPath: String?
  private var libraryActiveDraftId: String?
  private var sharedFileHandler: FlutterMethodCallHandler?
  private var sharedAudioHandler: FlutterMethodCallHandler?
  private var editorHoverTracker: EditorHoverTracker?
  private var latestToolboxState: [String: Any]?
  private var sidebarLifecycleSyncQueued = false
  private var sidebarFrontQueued = false

  override func sendEvent(_ event: NSEvent) {
    super.sendEvent(event)
    if event.type == .leftMouseDown { queueVisibleSidebarFront() }
  }

  func windowDidBecomeKey(_ notification: Notification) {
    guard notification.object as? NSWindow === self else { return }
    queueVisibleSidebarFront()
  }

  private func queueVisibleSidebarFront() {
    guard !sidebarFrontQueued else { return }
    sidebarFrontQueued = true
    // Let the clicked window finish becoming key before ordering its companion.
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.sidebarFrontQueued = false
      guard NSApp.isActive, !NSApp.isHidden, self.isKeyWindow,
            self.isVisible, !self.isMiniaturized, self.attachedSheet == nil,
            NSApp.modalWindow == nil,
            let panel = self.sidebarWindow,
            panel.isVisible, !panel.isMiniaturized,
            panel.attachedSheet == nil else { return }
      // Ordering does not change the key window or steal the board's responder.
      // Reuse only the current visible panel; never reopen a hidden sidebar.
      panel.order(.above, relativeTo: self.windowNumber)
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if sender === sidebarWindow {
      setSidebarVisible(false)
      return false
    }
    NSApp.terminate(sender)
    return false
  }

  private func activateWindow(_ target: NSWindow?) {
    guard let target = target else { return }
    NSApp.activate(ignoringOtherApps: true)
    if target.isMiniaturized { target.deminiaturize(nil) }
    target.makeKeyAndOrderFront(nil)
    if target === self { queueVisibleSidebarFront() }
  }

  @IBAction func showCurrentHistory(_ sender: Any?) {
    guard let channel = windowsChannel, attachedSheet == nil,
          sidebarWindow?.attachedSheet == nil, NSApp.modalWindow == nil else { return }
    activateWindow(self)
    channel.invokeMethod("showHistory", arguments: nil)
  }

  private func configureSidebar(_ arguments: [String: Any]) {
    if let path = arguments["dataPath"] as? String, !path.isEmpty { libraryDataPath = path }
    if arguments.keys.contains("activeDraftId") { libraryActiveDraftId = arguments["activeDraftId"] as? String }
  }

  private func notifySidebarState() {
    queueSidebarLifecycleSync()
    let visible = sidebarWindow?.isVisible ?? false
    windowsChannel?.invokeMethod("sidebarStateChanged", arguments: ["visible": visible, "mode": sidebarMode])
    windowsChannel?.invokeMethod("toolboxVisibilityChanged", arguments: visible && sidebarMode == "toolbox")
  }

  @discardableResult
  private func setSidebarVisible(_ visible: Bool) -> Bool {
    if visible {
      guard selectSidebarMode(sidebarMode, show: false) else { return false }
      positionSidebarOnce()
      activateWindow(sidebarWindow)
    } else { sidebarWindow?.orderOut(nil) }
    notifySidebarState()
    return sidebarWindow?.isVisible ?? false
  }

  private func setToolboxVisible(_ visible: Bool) { setSidebarVisible(visible) }

  // A Flutter engine observes its window disappearing when its view is
  // detached. Reusing that engine in the same visible NSWindow does not always
  // produce a new window-visible notification, leaving Dart in `hidden` with
  // frames disabled. The shared host owns visibility for both sidebar engines.
  @objc private func sidebarLifecycleChanged(_ notification: Notification) {
    queueSidebarLifecycleSync()
    if notification.name == NSApplication.didBecomeActiveNotification {
      queueVisibleSidebarFront()
    }
  }

  private func queueSidebarLifecycleSync() {
    guard !sidebarLifecycleSyncQueued else { return }
    sidebarLifecycleSyncQueued = true
    // Run after AppKit/Flutter's own window notifications so the mounted view,
    // rather than a stale detach notification, determines the final state.
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.sidebarLifecycleSyncQueued = false
      guard let panel = self.sidebarWindow else { return }
      for (mode, engine, controller) in [
        ("toolbox", self.toolboxEngine, self.toolboxController),
        ("library", self.libraryEngine, self.libraryController)
      ] {
        guard let engine = engine, let controller = controller else { continue }
        let visible = panel.isVisible && !panel.isMiniaturized && !NSApp.isHidden
          && self.sidebarMode == mode && controller.view.window === panel
        let state = visible
          ? (NSApp.isActive && panel.isKeyWindow ? "resumed" : "inactive")
          : "hidden"
        FlutterBasicMessageChannel(name: "flutter/lifecycle",
            binaryMessenger: engine.binaryMessenger,
            codec: FlutterStringCodec.sharedInstance())
          .sendMessage("AppLifecycleState.\(state)")
      }
    }
  }

  private func ensureSidebarWindow() {
    if sidebarWindow != nil { return }
    let container = NSViewController()
    container.view = NSView(frame: NSRect(x: 0, y: 0, width: 410, height: 695))
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 410, height: 695))
    host.autoresizingMask = [.width, .height]
    container.view.addSubview(host)
    let panel = SidebarWindow(contentRect: container.view.bounds, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    panel.title = sidebarTitle(sidebarMode)
    panel.contentViewController = container
    panel.collectionBehavior = [.fullScreenNone]
    panel.standardWindowButton(.zoomButton)?.isEnabled = false
    panel.isReleasedWhenClosed = false
    panel.isRestorable = false
    panel.delegate = self
    sidebarWindow = panel
    sidebarContainer = container
    sidebarHost = host
    for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                 NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                 NSWindow.didChangeOcclusionStateNotification] {
      NotificationCenter.default.addObserver(self, selector: #selector(sidebarLifecycleChanged(_:)),
          name: name, object: panel)
    }
    for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                 NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
      NotificationCenter.default.addObserver(self, selector: #selector(sidebarLifecycleChanged(_:)),
          name: name, object: NSApp)
    }
  }

  @discardableResult
  private func selectSidebarMode(_ mode: String, show: Bool = true) -> Bool {
    guard mode == "toolbox" || mode == "library" else { return false }
    if mode == "library" {
      guard let path = libraryDataPath, !path.isEmpty, ensureLibrary() else { return false }
    } else if !ensureToolbox() { return false }
    ensureSidebarWindow()
    guard let panel = sidebarWindow, let host = sidebarHost, let container = sidebarContainer,
          let controller = mode == "library" ? libraryController : toolboxController else { return false }
    if sidebarMode == mode, controller.view.superview === host {
      positionSidebarOnce()
      if mode == "library" { libraryChannel?.invokeMethod("refresh", arguments: libraryConfiguration()) }
      if show { activateWindow(panel) }
      notifySidebarState()
      return true
    }
    sidebarMode = mode
    panel.title = sidebarTitle(mode)
    host.subviews.forEach { $0.removeFromSuperview() }
    if controller.parent == nil { container.addChild(controller) }
    panel.contentMinSize = NSSize(width: 1, height: 1)
    panel.contentMaxSize = NSSize(width: 10000, height: 10000)
    // Both modes share identical geometry: browsing must never widen the sidebar.
    panel.styleMask.remove(.resizable)
    let content = NSSize(width: 410, height: 695)
    panel.setContentSize(content)
    panel.contentMinSize = content
    panel.contentMaxSize = panel.contentMinSize
    controller.view.frame = host.bounds
    controller.view.autoresizingMask = [.width, .height]
    host.addSubview(controller.view)
    // The previous engine may have had an active text input. Never leave the
    // shared window's keyboard responder attached to its now-detached view.
    panel.makeFirstResponder(controller.view)
    positionSidebarOnce()
    if mode == "library" { libraryChannel?.invokeMethod("refresh", arguments: libraryConfiguration()) }
    if show { activateWindow(panel) }
    notifySidebarState()
    return true
  }

  private func positionSidebarOnce() {
    // Place once. Editor moves, mode switches and show/hide must never drag
    // another native window underneath an in-progress pointer gesture.
    guard !sidebarInitiallyPositioned, let panel = sidebarWindow,
          let screen = self.screen ?? NSScreen.main else { return }
    sidebarInitiallyPositioned = true
    sidebarPlacement = "independent"
    let available = screen.visibleFrame
    let x = min(max(frame.maxX + 8, available.minX), available.maxX - panel.frame.width)
    let top = min(max(frame.maxY, available.minY + panel.frame.height), available.maxY)
    panel.setFrameTopLeftPoint(NSPoint(x: x, y: top))
  }

  private func ensureToolbox() -> Bool {
    if toolboxController != nil { return true }
    let engine = FlutterEngine(name: "pvz-toolbox", project: nil)
    toolboxEngine = engine
    let secondary = FlutterMethodChannel(name: "pvz_formation_editor/windows", binaryMessenger: engine.binaryMessenger)
    toolboxChannel = secondary
    secondary.setMethodCallHandler { [weak self] call, result in
      guard let window = self else { result(FlutterError(code: "closed", message: "主窗口已关闭", details: nil)); return }
      switch call.method {
      case "activateWindow":
        result(window.selectSidebarMode("toolbox") && (window.sidebarWindow?.isKeyWindow ?? false))
      case "selectSidebarMode", "setSidebarVisible", "configureSidebar":
        window.handleSidebarCall(call, result: result)
      case "diagnostics":
        result(window.windowDiagnostics())
      case "ready":
        if let state = window.latestToolboxState {
          secondary.invokeMethod("receiveState", arguments: state)
        }
        result(window.latestToolboxState)
      case "mainAction":
        guard let args = call.arguments as? [String: Any], args["action"] is String else {
          result(FlutterError(code: "arguments", message: "缺少主窗口操作", details: nil)); return
        }
        guard window.latestToolboxState != nil else {
          result(FlutterError(code: "inactive", message: "当前没有活动阵型", details: nil)); return
        }
        window.activateWindow(window)
        window.windowsChannel?.invokeMethod("mainAction", arguments: args, result: result)
      case "editState":
        guard let state = call.arguments as? [String: Any] else {
          result(FlutterError(code: "arguments", message: "工具箱状态必须是对象", details: nil)); return
        }
        guard window.latestToolboxState != nil else {
          result(FlutterError(code: "inactive", message: "当前没有活动阵型", details: nil)); return
        }
        window.windowsChannel?.invokeMethod("applyToolboxState", arguments: state, result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }
    let files = FlutterMethodChannel(name: "pvz_formation_editor/files", binaryMessenger: engine.binaryMessenger)
    files.setMethodCallHandler(sharedFileHandler)
    toolboxFilesChannel = files
    let audio = FlutterMethodChannel(name: "pvz_formation_editor/audio", binaryMessenger: engine.binaryMessenger)
    audio.setMethodCallHandler(sharedAudioHandler)
    toolboxAudioChannel = audio
    guard engine.run(withEntrypoint: "toolboxMain") else {
      toolboxChannel = nil
      toolboxFilesChannel = nil
      toolboxAudioChannel = nil
      toolboxEngine = nil
      return false
    }
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    controller.backgroundColor = NSColor(calibratedRed: 0.953, green: 0.965, blue: 0.922, alpha: 1)
    RegisterGeneratedPlugins(registry: controller)
    toolboxController = controller
    return true
  }

  private func windowDiagnostics() -> [String: Any] {
    func size(_ window: NSWindow) -> [Double] {
      let value = window.contentView?.bounds.size ?? window.contentRect(forFrameRect: window.frame).size
      return [Double(value.width), Double(value.height)]
    }
    func controllerSize(_ controller: FlutterViewController?) -> [Double] {
      guard let value = controller?.view.bounds.size else { return [] }
      return [Double(value.width), Double(value.height)]
    }
    func rect(_ value: NSRect) -> [Double] {
      return [Double(value.origin.x), Double(value.origin.y), Double(value.width), Double(value.height)]
    }
    let visible = sidebarWindow?.isVisible ?? false
    return [
      "mainContentSize": size(self), "mainFrame": rect(frame),
      "mainResizable": styleMask.contains(.resizable), "mainTitle": title,
      "toolboxContentSize": controllerSize(toolboxController),
      "toolboxFrame": sidebarWindow.map { rect($0.frame) } ?? [],
      "toolboxVisible": visible && sidebarMode == "toolbox",
      "toolboxResizable": false,
      "toolbarVisible": toolbar?.isVisible ?? false, "toolbarLabel": "", "toolbarEnabled": false,
      "hasToolboxEngine": toolboxEngine != nil,
      "libraryContentSize": controllerSize(libraryController),
      "libraryFrame": sidebarWindow.map { rect($0.frame) } ?? [],
      "libraryVisible": visible && sidebarMode == "library",
      "libraryResizable": sidebarMode == "library" && (sidebarWindow?.styleMask.contains(.resizable) ?? false),
      "hasLibraryEngine": libraryEngine != nil, "hasActiveDocument": latestToolboxState != nil,
      "mainKey": isKeyWindow, "sidebarKey": sidebarWindow?.isKeyWindow ?? false,
      "sidebarPointerEvents": (sidebarWindow as? SidebarWindow)?.pointerDiagnostics ?? [],
      "sharedSidebarWindow": true, "sidebarVisible": visible, "sidebarMode": sidebarMode,
      "sidebarWindowNumber": sidebarWindow?.windowNumber ?? 0,
      "sidebarMiniaturized": sidebarWindow?.isMiniaturized ?? false,
      "sidebarContentSize": sidebarWindow.map(size) ?? [],
      "sidebarFrame": sidebarWindow.map { rect($0.frame) } ?? [],
      "sidebarHeaderHeight": 0, "sidebarPlacement": sidebarPlacement,
      "sidebarHeaderSegments": [String: [Double]]()
    ]
  }

  private func handleSidebarCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method != "configureSidebar", sidebarWindow?.attachedSheet != nil {
      result(FlutterError(code: "file_dialog_open", message: "请先完成侧栏中的文件选择", details: nil)); return
    }
    let arguments = call.arguments as? [String: Any] ?? [:]
    configureSidebar(arguments)
    if let state = arguments["state"] as? [String: Any] {
      latestToolboxState = state
      toolboxChannel?.invokeMethod("receiveState", arguments: state)
    }
    switch call.method {
    case "configureSidebar": result(true)
    case "selectSidebarMode":
      guard let mode = arguments["mode"] as? String, ["toolbox", "library"].contains(mode) else {
        result(FlutterError(code: "arguments", message: "缺少有效侧栏模式", details: nil)); return
      }
      guard selectSidebarMode(mode) else {
        result(FlutterError(code: "sidebar_unavailable", message: "侧栏尚未准备好，请先初始化存档库路径", details: nil)); return
      }
      result(true)
    case "setSidebarVisible":
      guard let visible = arguments["visible"] as? Bool else {
        result(FlutterError(code: "arguments", message: "缺少侧栏可见状态", details: nil)); return
      }
      result(setSidebarVisible(visible))
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func ensureLibrary() -> Bool {
    if libraryController != nil { return true }
    let engine = FlutterEngine(name: "pvz-library", project: nil)
    libraryEngine = engine
    let library = FlutterMethodChannel(name: "pvz_formation_editor/library", binaryMessenger: engine.binaryMessenger)
    libraryChannel = library
    library.setMethodCallHandler { [weak self] call, result in
      guard let window = self else { result(FlutterError(code: "closed", message: "主窗口已关闭", details: nil)); return }
      switch call.method {
      case "ready":
        result(window.libraryConfiguration())
      case "openEditor":
        guard let arguments = call.arguments as? [String: Any] else {
          result(FlutterError(code: "arguments", message: "缺少存档参数", details: nil)); return
        }
        guard let main = window.windowsChannel else {
          result(FlutterError(code: "closed", message: "编辑器未准备好", details: nil)); return
        }
        main.invokeMethod("libraryOpen", arguments: arguments) { response in
          if let error = response as? FlutterError { result(error); return }
          if let accepted = response as? Bool, accepted {
            _ = window.selectSidebarMode("toolbox")
            window.activateWindow(window)
          }
          result(response)
        }
      case "close":
        window.setSidebarVisible(false)
        result(true)
      case "activateWindow":
        result(window.selectSidebarMode("library") && (window.sidebarWindow?.isKeyWindow ?? false))
      case "selectSidebarMode", "setSidebarVisible", "configureSidebar":
        window.handleSidebarCall(call, result: result)
      case "diagnostics":
        result(window.windowDiagnostics())
      default: result(FlutterMethodNotImplemented)
      }
    }
    let files = FlutterMethodChannel(name: "pvz_formation_editor/files", binaryMessenger: engine.binaryMessenger)
    files.setMethodCallHandler(sharedFileHandler)
    libraryFilesChannel = files
    let audio = FlutterMethodChannel(name: "pvz_formation_editor/audio", binaryMessenger: engine.binaryMessenger)
    audio.setMethodCallHandler(sharedAudioHandler)
    libraryAudioChannel = audio
    guard engine.run(withEntrypoint: "libraryMain") else {
      libraryChannel = nil
      libraryFilesChannel = nil
      libraryAudioChannel = nil
      libraryEngine = nil
      return false
    }
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    controller.backgroundColor = NSColor(calibratedRed: 0.953, green: 0.965, blue: 0.922, alpha: 1)
    RegisterGeneratedPlugins(registry: controller)
    libraryController = controller
    return true
  }

  private func libraryConfiguration() -> [String: Any] {
    return ["dataPath": libraryDataPath ?? "",
            "activeDraftId": libraryActiveDraftId as Any? ?? NSNull()]
  }

  override func awakeFromNib() {
    super.awakeFromNib()
    self.isRestorable = false
    self.setFrameAutosaveName("")
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = NSColor(calibratedRed: 0.953, green: 0.965, blue: 0.922, alpha: 1)
    self.contentViewController = flutterViewController
    self.acceptsMouseMovedEvents = true
    editorHoverTracker = EditorHoverTracker(view: flutterViewController.view) { [weak self] point in
      self?.windowsChannel?.invokeMethod("editorPointerMoved", arguments: point)
    }
    self.styleMask.remove(.resizable)
    self.collectionBehavior = [.fullScreenNone]
    self.standardWindowButton(.zoomButton)?.isEnabled = false
    self.setContentSize(NSSize(width: 810, height: 695))
    self.contentMinSize = NSSize(width: 810, height: 695)
    self.contentMaxSize = NSSize(width: 810, height: 695)
    self.toolbar = nil
    self.setContentSize(NSSize(width: 810, height: 695))
    self.title = "植物大战僵尸布阵器"
    self.center()
    // Leave room to the right for the fixed-size independent toolbox.
    if let available = (self.screen ?? NSScreen.main)?.visibleFrame {
      let pairWidth: CGFloat = 810 + 8 + 410
      let left = available.minX + max(0, (available.width - pairWidth) / 2)
      self.setFrameOrigin(NSPoint(x: left, y: self.frame.origin.y))
    }
    RegisterGeneratedPlugins(registry: flutterViewController)
    lifecycleChannel = FlutterMethodChannel(name: "pvz_formation_editor/lifecycle", binaryMessenger: flutterViewController.engine.binaryMessenger)
    self.delegate = self
    let channel = FlutterMethodChannel(name: "pvz_formation_editor/files", binaryMessenger: flutterViewController.engine.binaryMessenger)
    fileChannel = channel
    sharedFileHandler = { [weak self] call, result in
      guard let window = self else { result(FlutterError(code: "closed", message: "窗口已关闭", details: nil)); return }
      switch call.method {
      case "setLanguage":
        let args = call.arguments as? [String: Any]
        window.englishUI = args?["language"] as? String == "en"
        window.title = ""
        window.sidebarWindow?.title = window.sidebarTitle(window.sidebarMode)
        NSApp.mainMenu?.items.compactMap { $0.submenu }.flatMap { $0.items }
          .first { $0.action == #selector(MainFlutterWindow.showCurrentHistory(_:)) }?
          .title = window.englishUI ? "Version History…" : "历史版本…"
        result(nil)
      case "openExternal":
        guard let args = call.arguments as? [String: Any],
              let raw = args["url"] as? String,
              let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              raw.rangeOfCharacter(from: .controlCharacters) == nil,
              raw.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              raw.range(of: "%0[ad]", options: [.regularExpression, .caseInsensitive]) == nil,
              let url = components.url else {
          result(FlutterError(code: "invalid_url", message: "只支持有效的 HTTP/HTTPS 网页地址", details: nil)); return
        }
        result(NSWorkspace.shared.open(url))
      case "pickProject", "pickFormation":
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: NSApp.keyWindow ?? window) { response in
          guard response == .OK, let url = panel.url else { result(nil); return }
          do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 8 * 1024 * 1024 else { result(FlutterError(code: "too_large", message: "项目文件超过 8 MiB", details: nil)); return }
            let data = try Data(contentsOf: url)
            guard data.count <= 8 * 1024 * 1024 else { result(FlutterError(code: "too_large", message: "项目文件超过 8 MiB", details: nil)); return }
            let bytes = FlutterStandardTypedData(bytes: data)
            if call.method == "pickFormation" { result(["path": url.path, "bytes": bytes]) }
            else { result(bytes) }
          } catch { result(FlutterError(code: "read_failed", message: error.localizedDescription, details: nil)) }
        }
      case "chooseSavePath":
        guard let args = call.arguments as? [String: Any], let name = args["name"] as? String else {
          result(FlutterError(code: "arguments", message: "文件参数无效", details: nil)); return
        }
        let panel = NSSavePanel()
        panel.directoryURL = (args["directory"] as? String).map { URL(fileURLWithPath: $0, isDirectory: true) }
          ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: NSApp.keyWindow ?? window) { response in
          result(response == .OK ? panel.url?.path : nil)
        }
      case "chooseExportDirectory":
        let args = call.arguments as? [String: Any] ?? [:]
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = (args["directory"] as? String).map { URL(fileURLWithPath: $0, isDirectory: true) }
          ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: NSApp.keyWindow ?? window) { response in
          result(response == .OK ? panel.url?.path : nil)
        }
      case "copyImage":
        guard let args = call.arguments as? [String: Any],
              let bytes = args["bytes"] as? FlutterStandardTypedData,
              let image = NSImage(data: bytes.data) else {
          result(FlutterError(code: "image", message: "图片数据无效", details: nil)); return
        }
        NSPasteboard.general.clearContents()
        var copied = NSPasteboard.general.setData(bytes.data, forType: .png)
        if let tiff = image.tiffRepresentation {
          copied = NSPasteboard.general.setData(tiff, forType: .tiff) || copied
        }
        result(copied)
      case "saveFile":
        guard let args = call.arguments as? [String: Any], let name = args["name"] as? String, let bytes = args["bytes"] as? FlutterStandardTypedData else { result(FlutterError(code: "arguments", message: "文件参数无效", details: nil)); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: NSApp.keyWindow ?? window) { response in
          guard response == .OK, let url = panel.url else { result(nil); return }
          do { try bytes.data.write(to: url, options: .atomic); result(url.path) }
          catch { result(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil)) }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
    channel.setMethodCallHandler(sharedFileHandler)
    let audio = FlutterMethodChannel(name: "pvz_formation_editor/audio", binaryMessenger: flutterViewController.engine.binaryMessenger)
    audioChannel = audio
    sharedAudioHandler = { [weak self] call, result in
      guard let window = self else { result(FlutterError(code: "closed", message: "窗口已关闭", details: nil)); return }
      let args = call.arguments as? [String: Any] ?? [:]
      do {
        switch call.method {
        case "initialize", "configurePlantingSound":
          if call.method == "initialize", window.musicPlayer != nil { result(nil); return }
          guard let bytes = args["bytes"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "arguments", message: "缺少音频数据", details: nil)); return
          }
          let player = try AVAudioPlayer(data: bytes.data)
          guard player.prepareToPlay() else {
            result(FlutterError(code: "prepare_failed", message: "无法准备音频", details: nil)); return
          }
          player.volume = 0
          if call.method == "initialize" {
            player.numberOfLoops = -1
            window.musicPlayer = player
          } else {
            let source = args["source"] as? String ?? "plant1"
            guard ["plant1", "plant2", "plant_water"].contains(source) else {
              result(FlutterError(code: "arguments", message: "未知种植音效", details: nil)); return
            }
            var voices = [player]
            for _ in 0..<2 {
              let voice = try AVAudioPlayer(data: bytes.data)
              guard voice.prepareToPlay() else {
                result(FlutterError(code: "prepare_failed", message: "无法准备种植音效", details: nil)); return
              }
              voice.volume = window.soundVolume
              voices.append(voice)
            }
            window.plantingPlayers[source]?.forEach { $0.stop() }
            window.plantingPlayers[source] = voices
            window.plantingPlayer = player
          }
          result(nil)
        case "setMusicVolume", "setSoundVolume":
          guard let value = args["volume"] as? NSNumber,
                value.doubleValue.isFinite, (0...1).contains(value.doubleValue) else {
            result(FlutterError(code: "arguments", message: "音量必须在 0 到 1 之间", details: nil)); return
          }
          if call.method == "setSoundVolume" {
            window.soundVolume = value.floatValue
            for voice in window.plantingPlayers.values.flatMap({ $0 }) {
              voice.volume = value.floatValue
              if value.floatValue == 0 { voice.stop() }
            }
            result(nil)
          } else {
            guard let player = window.musicPlayer else {
              result(FlutterError(code: "not_initialized", message: "背景音乐未加载", details: nil)); return
            }
            player.volume = value.floatValue
            if value.floatValue == 0 { player.pause(); result(false) }
            else { result(player.isPlaying || player.play()) }
          }
        case "playPlantingSound":
          let source = args["source"] as? String ?? "plant1"
          guard let voices = window.plantingPlayers[source] else {
            result(FlutterError(code: "missing_asset", message: "种植音效素材尚未加载", details: nil)); return
          }
          let volume = (args["volume"] as? NSNumber)?.floatValue ?? window.soundVolume
          guard volume.isFinite, (0...1).contains(volume) else {
            result(FlutterError(code: "arguments", message: "音量无效", details: nil)); return
          }
          // The source permits three simultaneous instances of each sound.
          guard let player = voices.first(where: { !$0.isPlaying }) else { result(true); return }
          window.lastPlantingSource = source
          window.plantingPlayer = player
          player.currentTime = 0
          player.volume = volume
          result(volume > 0 && player.play())
        case "diagnostics":
          result(["musicLoaded": window.musicPlayer != nil,
                  "musicPlaying": window.musicPlayer?.isPlaying ?? false,
                  "musicVolume": window.musicPlayer?.volume ?? 0,
                  "musicLoops": window.musicPlayer?.numberOfLoops ?? 0,
                  "soundLoaded": window.plantingPlayer != nil,
                  "soundSources": window.plantingPlayers.keys.sorted(),
                  "lastPlantingSource": window.lastPlantingSource as Any? ?? NSNull(),
                  "soundPlaying": window.plantingPlayers.values.flatMap({ $0 }).contains(where: { $0.isPlaying }),
                  "soundVolume": window.soundVolume])
        case "dispose":
          window.musicPlayer?.stop()
          window.plantingPlayers.values.flatMap({ $0 }).forEach { $0.stop() }
          window.plantingPlayers.removeAll()
          window.lastPlantingSource = nil
          window.musicPlayer = nil
          window.plantingPlayer = nil
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "audio_decode_failed", message: error.localizedDescription, details: nil))
      }
    }
    audio.setMethodCallHandler(sharedAudioHandler)
    let windows = FlutterMethodChannel(name: "pvz_formation_editor/windows", binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowsChannel = windows
    windows.setMethodCallHandler { [weak self] call, result in
      guard let window = self else { result(FlutterError(code: "closed", message: "窗口已关闭", details: nil)); return }
      switch call.method {
      case "activateWindow":
        window.activateWindow(window)
        result(window.isKeyWindow)
      case "showLibrary":
        guard let arguments = call.arguments as? [String: Any],
              let path = arguments["dataPath"] as? String, !path.isEmpty else {
          result(FlutterError(code: "arguments", message: "缺少存档库路径", details: nil)); return
        }
        window.configureSidebar(arguments)
        let opened = window.selectSidebarMode("library")
        if opened { window.libraryChannel?.invokeMethod("refresh", arguments: window.libraryConfiguration()) }
        result(opened)
      case "refreshLibrary":
        window.libraryChannel?.invokeMethod("refresh", arguments: window.libraryConfiguration())
        result(nil)
      case "selectSidebarMode", "setSidebarVisible", "configureSidebar":
        window.handleSidebarCall(call, result: result)
      case "diagnostics":
        result(window.windowDiagnostics())
      case "deactivate":
        window.latestToolboxState = nil
        window.setToolboxVisible(false)
        result(true)
      case "initialize":
        window.configureSidebar(call.arguments as? [String: Any] ?? [:])
        window.ensureSidebarWindow()
        result(window.selectSidebarMode("toolbox", show: false))
      case "publishState":
        guard let state = call.arguments as? [String: Any] else {
          result(FlutterError(code: "arguments", message: "状态必须是对象", details: nil)); return
        }
        window.latestToolboxState = state
        let activeDraftId = state["activeDraftId"] as? String
        if window.libraryActiveDraftId != activeDraftId {
          window.libraryActiveDraftId = activeDraftId
          window.libraryChannel?.invokeMethod("refresh", arguments: window.libraryConfiguration())
        }
        window.toolboxChannel?.invokeMethod("receiveState", arguments: state)
        result(true)
      case "setToolboxVisible":
        guard let args = call.arguments as? [String: Any], let visible = args["visible"] as? Bool else {
          result(FlutterError(code: "arguments", message: "缺少可见状态", details: nil)); return
        }
        if let state = args["state"] as? [String: Any] {
          window.latestToolboxState = state
            window.toolboxChannel?.invokeMethod("receiveState", arguments: state)
        }
        window.setToolboxVisible(visible)
        result(window.sidebarWindow?.isVisible ?? false)
      default: result(FlutterMethodNotImplemented)
      }
    }
    // AppKit has completed nib restoration before these final geometry values.
    self.title = "植物大战僵尸布阵器"
    self.setContentSize(NSSize(width: 810, height: 695))
    self.contentMinSize = NSSize(width: 810, height: 695)
    self.contentMaxSize = NSSize(width: 810, height: 695)
    self.positionSidebarOnce()
  }
}
