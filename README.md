# 植物大战僵尸布阵器 · PVZ Formation Editor

<img src="assets/branding/app-logo.png" width="128" alt="植物大战僵尸布阵器图标">

[简体中文](README.md) | [English](README.en.md)

**落植为棋，布阵成道。** 一个以 **Windows** 为主要平台、使用 Flutter Widget / Canvas 构建的本地离线布阵器。

**v1.0.1** · [官网](https://xmpvz.pages.dev) · [使用文档](https://xmpvz.pages.dev/docs/) · [下载 Windows x64 绿色版](https://xmpvz.pages.dev/downloads/PvZ-Formation-Editor-1.0.1-windows-x64.zip) · [加入 QQ 群：425175276](https://qm.qq.com/q/BbkV57ELaa)

作者及维护者：**越小梦** · [作者信息](AUTHORS) · [鸣谢](ACKNOWLEDGMENTS.md)

本项目主要参考 [jspvz 网页布阵器](http://jspvz.com/ArrayDesign/)，作者 **LonelyStar（囧丫乙）**，以其功能和 UI 为基础迁移到本地并进行功能增强。技术参考：[PvZ Toolkit](https://pvz.lmintlcx.com/toolkit/)（lmintlcx）、[PvZ-Portable](https://github.com/wszqkzqk/PvZ-Portable)（wszqkzqk 及社区贡献者）。

## Windows 版本

当前发布为 **Windows v1.0.1**，已构建并启动验证。其他平台目前提供工程源码，没有本次对应的发布包。

| 项目 | 信息 |
| --- | --- |
| 应用版本 | 1.0.1 |
| 系统与架构 | Windows 10 / Windows 11，x64 |
| 发布形式 | Release 绿色 ZIP 包，免安装 |
| 启动程序 | `pvz_formation_editor.exe` |
| 运行库 | 包内附带 MSVC 运行库；保留 DLL 和 `data` 文件夹 |
| 游戏接入 | 原版 Windows PvZ 1.0.0.1051，生存无尽模式 11–15 |
| 本地数据 | 用户应用支持目录；不随绿色包目录自动移动 |
| 更新方式 | 正常退出旧版，解压新版后运行；迁移设备前先导出存档 |

**[下载 Windows v1.0.1 x64 绿色版](https://xmpvz.pages.dev/downloads/PvZ-Formation-Editor-1.0.1-windows-x64.zip)** · [SHA-256 校验](https://xmpvz.pages.dev/downloads/SHA256SUMS.txt) · [Windows 使用文档](https://xmpvz.pages.dev/docs/)

本版包含独立双窗口、Windows 中文字体优化、名阵打开即自动保存、存档批量导入导出，以及模仿者/梯子/墓碑/钉耙的游戏应用支持。完整游戏实测范围见下文；不保证改版或其他游戏版本兼容。

## 下载与使用

Windows 10 / 11 x64：下载绿色包、完整解压，然后运行 `pvz_formation_editor.exe`。请保留旁边的 DLL 和 `data` 文件夹，无需安装。校验值见 [SHA256SUMS](https://xmpvz.pages.dev/downloads/SHA256SUMS.txt)。官网仅提供应用下载，源代码以本 GitHub 仓库为准。

- 主画面与侧窗独立，Windows 主画面可以单独最小化。Windows 主窗口 810×695，侧窗 410×695。
- 侧窗页签依次为：**存档仓库、懒人布局、图鉴选卡、镜像窗口、载入导出、选项设置**。首次显示图鉴选卡。
- 编辑支持 26 种地图、植物/僵尸/物品、卡槽、图层与外观调整、批量选择和铲除、撤销/重做及 PNG 导出。
- 内置 363 个名阵、春哥与曾哥局部布局；最多创建三个只读镜像快照。
- 存档仓库提供搜索、标签、批量选择、导出、导入、去重和存档历史。收藏入口暂时隐藏，已有收藏数据保留。
- 默认导出目录为文稿目录下的 `PvzFormationEditor`，可在设置中更改。“显示土壤水花”默认关闭。
- 应用可切换简体中文 / English；官网语言下拉框提供跟随系统、简体中文和 English，并保存选择。

## 自动保存

编辑会自动保存到本地存档，主画面顶部显示“自动保存已开启 / 正在自动保存 / 已自动保存”；失败会明确提示，可点击重试。

- 名阵打开到当前标签页或新标签页时，立即保存为可编辑存档，无需先修改或手动保存。同内容的已保存阵型会复用，避免反复打开制造副本。
- 新建空白页面在尚无修改时不会生成空存档；首次有效编辑后自动保存。只读预览不会入库。
- 后续修改更新同一个存档，并保留旧版本；快速编辑、改名、撤销和重做均进入串行保存队列。
- 重新启动可恢复已保存文档；打开标签页保留撤销记录，关闭或重启后不恢复撤销栈。
- Ctrl/Cmd+S 可主动提交；另存为创建独立副本。导出文件是独立副本，需要再次导出才能更新该文件。

## 实际游戏阵型

当前游戏接入支持 **Windows 原版 1.0.0.1051、生存无尽模式 11–15**。先启动游戏并进入实际关卡。

1. “载入导出”输入框上方的 **从游戏获取** 将阵型码填入输入框；再点击 **载入布阵器** 才替换编辑画面。
2. 当前阵型码可直接复制或 **应用到游戏**；应用会替换现有布阵，保留游戏当前阳光数。
3. 存档/名阵详情中的应用按钮位于“复制 Toolkit 阵型码”旁，列表项“更多”菜单也有同一操作，直接写入运行中的游戏。

支持常规植物、模仿者、睡眠状态、墓碑、梯子、钉耙及六类场景切换。缩放、翻转、图像特效、装饰僵尸和我是僵尸模式暂不支持，会明确拒绝而不伪报成功。其他游戏版本和改版未保证兼容。

选卡默认将大喷菇、忧郁蘑菇、磁力菇设为唤醒外观，寒冰菇、毁灭菇及其他可睡眠蘑菇默认睡眠。用户可继续切换外观，保存、导出及应用到游戏始终以最终外观帧为准，载入既有阵型不会重套默认值。

v1.0.1 直接应用文档时还会按外观设置玉米炮装填、土豆雷出土、阳光菇大小、仙人掌高矮，以及部分植物的受损程度。有弹玉米炮直接可发射；空炮冷却归零，恢复运行后立即装填。PvZ Toolkit 阵型码本身不保存上述全部状态，完整项目及网页阵型码可保存外观。详见 [v1.0.1 更新说明](docs/releases/1.0.1.md)。

**实测：363 个名阵全部尝试，360 个应用后读回一致，3 个因网页装饰内容被拒绝。** 用户提供的 86 对象历史名阵码也通过真实写入/读取验证。各应用入口已分别实测，测试后恢复原阵型。详见 [完整名阵验证记录](docs/game-integration/all-presets-validation.md) 和 [Windows 接入说明](docs/game-integration/windows-1051.md)。

游戏注入历史备份/回退功能已移除；存档自身的历史版本及游戏存档文件备份功能保留。

## 导入、导出与数据

- PvZ Toolkit 阵型码及网页布阵器阵型码：保存各自格式可表达的布阵；不支持的内容会明确提示。
- 完整项目 `*.pvzf.json` / `PVZF1:`：保留阵型文档、地图、对象状态、外观、显示设置等。
- 存档集合 `*.pvzlib.json`：导入/导出名称、备注、标签和完整阵型；重复内容跳过，同名不同内容自动改名。集合不包含全部历史版本。
- PNG：静态图片，不能代替可编辑备份。
- 实验性 PC 无尽存档导入只提取布阵，不恢复完整战斗进度，也不修改源 `.dat` 文件。

数据位于用户应用支持目录中的 `formations.sqlite`（数据库版本 4，文档版本 1）。绿色版免安装不代表数据保存在程序旁。完整历史备份应在正常退出后复制数据库及可能存在的 journal/WAL/SHM 文件；恢复前保留当前数据。

导入上限为 8 MiB、5,000 对象。先校验整个文件再写入，错误、损坏或超限文件不会部分导入；取消操作保留现有内容。尚不支持自定义图片资源。

## 启动恢复与图片缓存

正常退出后恢复上次打开的阵型页、选中标签和文件关联；首次使用或上次关闭全部页面时显示一个空白阵型，不会每次启动新增存档。

363 张名阵缩略图随安装包提供，分辨率为 256×192，WebP 文件合计 7.49 MiB。列表直接按需读取，解码缓存限制为 4 MiB；自定义阵型缩略图首次生成后缓存到本地，修改画面才重新生成。植物外观按帧加载并共享相同图片，列表预览不再导出完整大图。

## 开发与构建

实际使用 Flutter **3.19.2 stable** / Dart **3.3.0**；依赖锁定于 `pubspec.lock`。

```sh
flutter pub get
flutter run -d windows  # 按实际宿主选择 macos / linux 或移动设备
flutter build windows --release
```

Windows 需要 Visual Studio 2022 C++ 桌面工具链及系统 `winsqlite3.dll`；macOS/iOS 需要 Xcode 和 CocoaPods；Android 使用 JDK 17、Android SDK 和 Gradle 7.6.3；Linux 需要 Flutter GTK 开发依赖、`libsqlite3.so.0`、`zenity` 和中文字体。

```sh
flutter build macos
flutter build linux
flutter build apk
flutter build ios --no-codesign
```

替换运行中的 macOS 构建时，使用 `swift tool/restart_macos_app.swift <app-bundle-path>`，让旧实例先正常保存退出。

`tool/package_windows_release.py` 打包 Windows Release 与本地 MSVC 运行库（可用 `--build`、`--crt` 指定目录）。`python website/build.py` 构建官网，`node website/test-download.mjs` 校验绿色包流式下载与 Range 续传。部署方式见 [官网说明](website/README.md)。

## 验证

```sh
flutter analyze
dart test test/toolkit_codec_test.dart test/archive_bundle_test.dart test/archive_dedup_test.dart test/formation_exchange_test.dart test/file_backups_test.dart test/game_save_codec_test.dart test/website_codec_test.dart
```

本轮静态分析通过，以上 63 项测试通过；真实 Flutter 引擎验证了完整项目/阵型码文件读写、批量导入导出、去重、损坏/超限/取消、自动保存和重开恢复。Windows Release 已构建并启动，363 个名阵及各应用入口已在真实 1051 游戏中验证，范围见上述记录。

macOS 已有历史构建与启动记录；本轮未重新构建 macOS。Linux/iOS 未实机验收，Android 先前打包受 Gradle 下载网络问题阻塞。仓库包含这些平台工程，不代表均已有发布包。原生文件对话框、异常断电和所有游戏版本未做完整验收。

## 项目结构与许可

`lib/domain`：文档、校验、布局、编解码；`lib/editor`：编辑命令、自动保存、渲染；`lib/storage`：SQLite、迁移与历史；`lib/platform` 和原生 runner：文件、窗口及游戏接入；`website`：官网与使用文档。

项目源代码采用 [GNU GPL v3.0](LICENSE)。Copyright (C) 2026 越小梦。植物大战僵尸素材和第三方依赖保留各自的权利与许可声明，见 [鸣谢](ACKNOWLEDGMENTS.md) 与 [素材说明](docs/assets.md)。
