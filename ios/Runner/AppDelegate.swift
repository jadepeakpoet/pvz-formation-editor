import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate {
  private var fileChannel: FlutterMethodChannel?
  private var fileResult: FlutterResult?
  private var exportFile: URL?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "pvz_formation_editor/files", binaryMessenger: controller.binaryMessenger)
      fileChannel = channel
      channel.setMethodCallHandler { [weak self, weak controller] call, result in
        guard let app = self, let host = controller else { result(FlutterError(code: "closed", message: "窗口已关闭", details: nil)); return }
        guard call.method == "pickProject" || call.method == "saveFile" else { result(FlutterMethodNotImplemented); return }
        guard app.fileResult == nil else { result(FlutterError(code: "busy", message: "文件对话框已打开", details: nil)); return }
        let picker: UIDocumentPickerViewController
        if call.method == "pickProject" {
          picker = UIDocumentPickerViewController(documentTypes: ["public.data", "public.content"], in: .import)
        } else {
          guard let args = call.arguments as? [String: Any], let name = args["name"] as? String, let bytes = args["bytes"] as? FlutterStandardTypedData else { result(FlutterError(code: "arguments", message: "文件参数无效", details: nil)); return }
          do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent((name as NSString).lastPathComponent)
            try bytes.data.write(to: url, options: .atomic)
            app.exportFile = url
            picker = UIDocumentPickerViewController(url: url, in: .exportToService)
          } catch { result(FlutterError(code: "write_failed", message: error.localizedDescription, details: nil)); return }
        }
        app.fileResult = result
        picker.delegate = app
        picker.allowsMultipleSelection = false
        host.present(picker, animated: true)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishFile(nil)
  }
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { finishFile(nil); return }
    if exportFile != nil { finishFile(url.absoluteString); return }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    do {
      let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard size <= 8 * 1024 * 1024 else { finishFile(FlutterError(code: "too_large", message: "项目文件超过 8 MiB", details: nil)); return }
      let bytes = try Data(contentsOf: url)
      guard bytes.count <= 8 * 1024 * 1024 else { finishFile(FlutterError(code: "too_large", message: "项目文件超过 8 MiB", details: nil)); return }
      finishFile(FlutterStandardTypedData(bytes: bytes))
    } catch { finishFile(FlutterError(code: "read_failed", message: error.localizedDescription, details: nil)) }
  }
  private func finishFile(_ value: Any?) {
    let callback = fileResult
    fileResult = nil
    if let url = exportFile { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    exportFile = nil
    callback?(value)
  }
}
