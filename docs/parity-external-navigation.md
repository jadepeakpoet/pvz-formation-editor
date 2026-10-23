# 原生外链导航

接口：`await ProjectFiles.openExternal(Uri.parse(url))`，返回系统是否接受打开请求。调用失败会抛出异常供 UI 显示，不把失败当作成功。

- Dart 在进程/channel 调度前验证 HTTP/HTTPS scheme、authority、非空主机，并拒绝用户密码字段、控制符及编码 CR/LF。
- macOS 的 files channel 再独立验证 URL，交给 `NSWorkspace.shared.open`；没有调用 shell。
- Linux 使用 `Process.run('xdg-open', [url], runInShell: false)`。
- Windows 使用固定 PowerShell 脚本 `Start-Process -FilePath $env:PVZ_EXTERNAL_URL`，URL 放环境变量，不拼进脚本，不使用 shell 参数插值。

`tool/parity_external.dart` 包含安全地址接受，以及 file/javascript/data/mailto/ftp、无主机、userinfo、编码 CRLF 在 native dispatch 前拒绝的用例。默认只验证参数，不打开外部网页。接受用例包含原站实际两链接 `https://pvz.lmintlcx.com/` 与 `https://tieba.baidu.com/p/5272254427`。没有打开任何外部浏览器，避免打断原站验收。

静态验证：`dart analyze lib/platform/project_files.dart tool/parity_external.dart`；Swift 语法验证：`swiftc -frontend -parse macos/Runner/MainFlutterWindow.swift`。Linux/Windows 进程启动实现尚未在对应平台执行，不标为已通过。实际 macOS channel 和浏览器导航由主代理的原生构建/UI 运行阶段验证。
