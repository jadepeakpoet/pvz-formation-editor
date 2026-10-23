# macOS 本地运行记录

2026-10-20，本机使用 `/tmp/pvz-flutter-sdk` 的 Flutter SDK。

## CocoaPods

默认 PATH 中 `/usr/local/bin/pod` 使用 Ruby 3.4，缺少 cocoapods gem。现有
`/Users/developer/.gem/ruby/2.6.0/bin/pod --version` 返回 `1.17.0`。
仅为本次命令调整 PATH 后，Flutter 的 `pod install` 成功；没有重装 Ruby 或修改全局配置：

```sh
PATH=/Users/developer/.gem/ruby/2.6.0/bin:$PATH /tmp/pvz-flutter-sdk/bin/cache/dart-sdk/bin/dart /tmp/pvz-flutter-sdk/bin/cache/flutter_tools.snapshot run -d macos --no-pub
```

该 Flutter 子进程中的 Xcode 调用随后遇到沙箱限制，包括 CoreSimulatorService
连接失败和 `Runner.xcworkspace is not a workspace file`。工作区 XML 本身存在且有效。

## 成功的构建与启动方式

直接执行已允许的 Xcode 命令可正常构建，并执行 Flutter Assemble 更新 Dart 内核和资源：

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug -derivedDataPath /tmp/pvz-macos-run CODE_SIGNING_ALLOWED=NO build
open -n /tmp/pvz-macos-run/Build/Products/Debug/pvz_formation_editor.app
```

直接构建已获得 `BUILD SUCCEEDED`，启动后通过进程路径核验应用运行。
这验证本机 Debug 构建和启动，不代表发布签名、安装包或跨平台验收。

启动窗口现在按可见屏幕设置内容尺寸：宽度 `min(1240, 屏幕可见宽度 - 40)`，
高度 `min(800, 屏幕可见高度 - 60)`，最小窗口尺寸 640×480，并居中。
标题为“植物大战僵尸阵型编辑器 · PVZ Studio”，方便识别新窗口。

## 旧进程边界

尝试关闭本轮自己创建的旧进程前，已核验其精确可执行路径。
`kill -TERM` 被沙箱以 `operation not permitted` 拒绝，未重复尝试或绕过限制。
因此用 `open -n` 打开新实例，旧窗口可能仍保留；用户原有实例未修改或关闭。
