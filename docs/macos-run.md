# macOS 构建与运行

macOS 工程使用 Flutter 3.47.8、Xcode、Swift Package Manager 和 CocoaPods，最低运行版本为 macOS 12.0。工程已迁移到新版 Flutter 的 Swift Package Manager 集成；尚未支持该方式的 sqflite 继续由 CocoaPods 管理。项目包含主窗口与共享侧窗的原生桥接。已有 macOS 构建、启动及桌面交互验证记录；1.0.2 提供 Apple Silicon arm64 与 Intel x64 ZIP，见 [平台支持](platforms.md)。

```sh
flutter pub get
flutter run -d macos
flutter build macos --release
```

替换正在运行的 macOS 构建时，使用项目的正常退出与重启脚本：

```sh
swift tool/restart_macos_app.swift "build/macos/Build/Products/Release/PVZ Formation Editor.app"
```

脚本先请求已有实例保存并退出，再启动新版本；退出受阻时保留当前实例，便于处理正在进行的工作。

## 1.0.2 下载与首次打开

要求 macOS 12.0 或更新版本。在“ → 关于本机”确认芯片：

- Apple Silicon（M 系列）：[macos-arm64.zip](https://xmpvz.pages.dev/downloads/PvZ-Formation-Editor-1.0.2-macos-arm64.zip)。
- Intel：[macos-x64.zip](https://xmpvz.pages.dev/downloads/PvZ-Formation-Editor-1.0.2-macos-x64.zip)。

解压后将 `PVZ Formation Editor.app` 拖入“应用程序”。两种包使用临时签名（ad-hoc），没有 Apple Developer ID 签名或 Apple 公证。首次打开若被系统拦截，先核对下载来源及 [SHA-256 校验值](https://xmpvz.pages.dev/downloads/SHA256SUMS.txt)，再进入“系统设置 → 隐私与安全性”，为此应用选择“仍要打开”。不需要关闭系统整体安全检查。

macOS 应用标识（Bundle ID）为 `com.xiaomeng.pvz.formation.macos`。

macOS 支持本地编辑、自动保存、存档管理、阵型码与项目交换和图片导出。原版 Windows PvZ 的进程识别、实际游戏读写及游戏存档目录接入不在 macOS 提供。

## 旧开发包存档迁移

新 Bundle ID 使用独立的 macOS 应用容器，旧开发包 `com.example.pvzFormationEditor` 的数据库不会自动变成新包的存档。迁移工具仅复制完整资料库到空目标，不合并两份资料库，也不覆盖目标中已有的存档、草稿或历史。

1. 让旧应用正常保存并退出。
2. 首次启动新包以建立新容器，随后正常退出新应用。迁移期间保持新旧应用均已关闭。
3. 确认旧数据库、新数据库和私有备份目录的实际路径，再从项目根目录运行：

```sh
python3 tool/migrate_macos_data.py \
  --source "<旧DB路径>/formations.sqlite" \
  --destination "<新DB路径>/formations.sqlite" \
  --backup-dir "<私有备份目录>" \
  --apps-closed
```

沙箱容器中的数据库一般位于 `~/Library/Containers/<Bundle ID>/Data/Library/Application Support/<Bundle ID>/formations.sqlite`，请以应用实际使用的路径为准。脚本保留旧库，通过 SQLite 备份接口生成包含已提交 WAL 内容的一致性快照；目标空库若存在也会先备份。备份目录保留迁移记录与校验值。目标含已有用户数据、仍有 SQLite 辅助文件或迁移过程中被改动时，脚本会拒绝迁移；需要合并资料时改用应用的存档集合导出、导入。

迁移完成后打开新包，检查存档、历史及上次工作区。确认无误前保留旧库和全部迁移备份。

## 双芯片打包

```sh
python tool/package_macos_release.py --build "build/macos/Build/Products/Release/PVZ Formation Editor.app"
```

脚本从通用 Release 应用逐个裁剪 Mach-O 为 arm64 或 x86_64，分别临时签名，检查架构、签名及 ZIP 完整性，再输出两个 ZIP 与 SHA-256 校验文件到 `release/1.0.2/`。运行验证与上述包检查分别进行。

## 验证边界

两包已通过逐个 Mach-O 单架构检查、`codesign --verify --deep --strict` 和 ZIP CRC 校验。新 Bundle ID 的 Apple Silicon 最终 ZIP 解压后签名校验通过，签名为 ad-hoc，未设置 TeamIdentifier；已实际启动并确认对应运行进程。

本机旧开发包资料库迁移后，新旧库均为 1 个存档、0 条历史，数据库校验通过，保存的工作区指向“电波钟无炮”。这验证数据库内容及工作区记录，不代表完成应用界面的视觉验收。旧库和一致性备份均保留。

本机未安装 Rosetta，无法运行 Intel 包；Intel 原机运行仍待验证。
