# 开发与构建

项目名：`pvz_formation_editor`。技术组成：Flutter Widget 界面、Canvas 阵图、SQLite 本地存储，以及 Windows/macOS 的原生桌面适配。

## 工具链

当前构建基线为 Flutter 3.19.2 stable / Dart 3.3.0，依赖由 `pubspec.lock` 锁定。

| 目标 | 宿主与工具 |
| --- | --- |
| Windows | Windows、Visual Studio 2022 C++ 桌面开发工具、Windows SDK |
| macOS / iOS | macOS、Xcode、CocoaPods |
| Linux | Linux、Flutter GTK 开发依赖、SQLite、中文字体 |
| Android | JDK 17、Android SDK、项目 Gradle 工程 |

## 常用命令

```sh
flutter pub get
flutter analyze
flutter run -d windows
flutter build windows --release
```

其他目标可在对应宿主执行 `flutter build macos`、`flutter build linux`、`flutter build apk` 和 `flutter build ios --no-codesign`。平台状态见 [平台支持](platforms.md)。

## 目录

- `lib/domain`：阵图模型、植物状态、布局、校验与格式编解码。
- `lib/editor`：编辑命令、Canvas 渲染、自动保存、标签页与图像资源管理。
- `lib/library`：存档仓库、搜索筛选、缩略图和游戏面板。
- `lib/storage`：SQLite、数据迁移、存档集合和文件备份。
- `lib/platform`、各平台 runner：文件、剪贴板、窗口、语言和游戏桥接。
- `assets/original`：地图、卡片、精灵帧、音效及名阵缩略图。
- `website`：官网、使用文档和访问统计后台。
- `test`、`tool`：模型测试、Flutter 界面/通道测试、原生验证及资源构建工具。

## 验证

纯 Dart 测试可以直接执行，例如：

```sh
dart test test/mushroom_state_test.dart test/plant_game_state_test.dart test/toolkit_codec_test.dart test/website_codec_test.dart test/game_save_codec_test.dart
```

依赖 `dart:ui` 的 `tool/*_smoke.dart` 由 Flutter 引擎运行。`tool/mushroom_game_smoke.dart` 检查实际 GameBridge 发送字段；`tool/plant_state_smoke.dart` 检查编辑界面的默认选择和用户切换；`tool/mushroom_live_smoke.dart` 是可选的真实 Windows 游戏验证入口，会在测试后恢复捕获的阵型。

`tool/game_x86_smoke.cpp` 检查 x86 调用编码、寄存器和栈约定。真实游戏测试需有适配版本运行在选卡或布阵场景，并设置测试输出路径。

官网构建与检查：

```sh
python website/build.py
node website/test-analytics.mjs
node website/test-download.mjs
```

## 发布

应用版本统一记录在 `pubspec.yaml`、`lib/platform/app_info.dart`，Windows 资源版本由 Flutter 构建配置生成。`tool/package_windows_release.py` 从 `pubspec.yaml` 读取发布版本，将 Release 程序、资源和本地 MSVC 运行库打包到 `release/<version>/`。

GitHub Release 提供 Windows 绿色包、源码归档和 SHA-256 校验文件。官网提供绿色包与文档，源码入口指向 GitHub。官网部署说明见 [website/README](../website/README.md)。
