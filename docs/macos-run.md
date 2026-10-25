# macOS 构建与运行

macOS 工程使用 Flutter 3.47.8、Xcode、Swift Package Manager 和 CocoaPods，最低运行版本为 macOS 12.0。工程已迁移到新版 Flutter 的 Swift Package Manager 集成；尚未支持该方式的 sqflite 继续由 CocoaPods 管理。项目包含主窗口与共享侧窗的原生桥接。已有 macOS 构建、启动及桌面交互验证记录；主要发布包为 Windows 版本，见 [平台支持](platforms.md)。

```sh
flutter pub get
flutter run -d macos
flutter build macos --release
```

替换正在运行的 macOS 构建时，使用项目的正常退出与重启脚本：

```sh
swift tool/restart_macos_app.swift build/macos/Build/Products/Release/pvz_formation_editor.app
```

脚本先请求已有实例保存并退出，再启动新版本；退出受阻时保留当前实例，便于处理正在进行的工作。
