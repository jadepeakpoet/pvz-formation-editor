# PVZ Formation Editor · 植物大战僵尸布阵器

作者：**越小梦 yuexiaomeng**

在存档库的设置或编辑器的“选项设置”中，可切换简体中文 / English；选择会保存，并同步到独立窗口。部分植物与预制阵型名称保留原始名称。

英文名称：**PVZ Formation Editor**；中文名称：**植物大战僵尸布阵器**。内部 Dart 包名仍为 `pvz_formation_editor`，应用标识、旧存档路径与文件格式标识保持兼容。

使用 Flutter Widget / Canvas 的离线布阵编辑器，项目名 `pvz_formation_editor`。包含 Windows、macOS、Linux、Android、iOS 工程，没有 WebView、服务器、账号或游戏内存操作。当前是可运行源码与通过引擎验证的首版，**不是原网页全部功能或美术的完整复刻**。

## 启动与构建

本次实际环境：Flutter **3.19.2 stable** / Dart **3.3.0**。锁定依赖见 `pubspec.lock`；需 Dart ≥3.3。可联网的常规开发环境：

```sh
flutter pub get
flutter run -d macos  # 按实际机器改为 windows / linux，或选择 Android/iOS 设备
```

原生构建分别在对应宿主平台执行：

```sh
flutter build macos
flutter build windows
flutter build linux
flutter build apk
flutter build ios --no-codesign
```

macOS/iOS 需要 Xcode 与可工作的 CocoaPods；Android 需要 Android SDK 和与本工程 Gradle 7.6.3 相容的 JDK 17（可在 `android` 目录通过 `JAVA_HOME=/path/to/jdk17 ./gradlew assembleDebug` 构建，避免改动全局配置）；Windows 需要 Flutter 桌面工具链且使用系统 `winsqlite3.dll`；Linux 需要 Flutter GTK 构建依赖、`libsqlite3.so.0` 和用于文件对话框的 `zenity`，以及中文字体。未提供发布签名、安装包或商店发布配置。

当前受管环境的原 Flutter SDK 缓存不可写，验证临时复制到 `/tmp/pvz-flutter-sdk`；**该机器路径不是产品依赖，也未打包进源码**。在正常可写 SDK 上直接使用以上命令即可。

## 使用

启动后直接进入最近草稿或空白泳池。经典界面按原站左侧 800×600 画布、右侧 380px 六标签工具箱排列；小窗口可滚动查看完整工作区。存档库保留在顶部入口。

- **卡槽选卡**：从图鉴选入最多十张卡片，点击选用或移除，随草稿保存。
- **懒人布局**：包含原站363名阵、36炮布局和21忧郁菇布局。选择后明确执行布阵，可保留当前地图；支持撤销。
- **图鉴选卡**：使用原站卡图与地图，七种效果、外表帧、左右/上下翻转；单格、连续放置、批量选择和分类铲除。
- **镜像窗口**：最多三个可拖动独立快照浮窗，支持六种原站比例、各自背景与PNG导出；关闭后不保存。
- **载入导出**：内联载入/获取原站字符串，导出PNG；完整项目和PVZF1保留应用全部状态。
- **选项设置**：26原站地图及自由棋盘，阳光、卡槽、推车、脑子、继续标识、迷雾列数，以及对象图层属性。
- **草稿与存档**：修改后自动保存，主动保存正式存档时保留版本。草稿和存档互不覆盖。

实际覆盖及剩余差异见[原站对照](docs/feature-parity.md)。

桌面快捷键：Ctrl/Cmd+Z 撤销，Ctrl/Cmd+Shift+Z 重做，Ctrl+Y 重做，Ctrl/Cmd+S 主动存档，Delete/Backspace 删除选中对象，Esc 清除选择。文本输入有焦点时保留输入编辑行为。

## 草稿、存档与版本

- 空白编辑器仅打开再离开，不生成草稿。有效修改后以 **700ms 防抖**写入独立工作草稿；离页、后台和正常桌面退出时尽力立即提交。
- 只有 SQLite 提交成功才显示“草稿已保存”。失败保留内存文档，显示失败及重试按钮；离页会提示未保存内容。异常强杀可能丢失尚未提交的防抖窗口，不能靠退出回调保证最后一次编辑。
- 草稿使用稳定 ID、单会话保存队列、数据库 revision 保护和删除墓碑，防止旧写覆盖、串档或删除后复活。缩略图在文档提交后异步生成，严格绑定对应 revision。
- 存档为独立完整文档快照，自动保存不会更新它。打开存档只读；继续编辑时，可继续已有关联草稿或新建副本。删除草稿不影响存档；删除存档只解除草稿关联。
- 明确更新存档在同一事务内保留旧版本。历史恢复创建新草稿。存档支持元数据、标签、收藏、复制、搜索、排序和导出。
- 当前标签页未关闭时保留完整撤销记录，不再按100条或16MiB裁剪；编辑、清空、改名和当前页换阵型均可使用撤销／重做。自动保存不增加记录，关闭标签或重启后不恢复撤销栈，但会恢复成功保存的文档。

详见 [行为说明](docs/behavior.md)。

## 文件、数据位置与备份

数据库是应用私有支持目录内的 `formations.sqlite`；首页右上“信息”显示**本机精确路径**。macOS 沙箱版位于应用容器内；其他平台由 `path_provider` 选择应用支持目录。数据库 `user_version=2`，含 v0/v1 迁移入口；阵型文档 `schemaVersion=1`，项目容器 `version=1`。

- `*.pvzf.json`：完整**阵型文档**和内置资源清单版本，保留地图、全部对象/层/占格/外观/状态、阳光与显示设置。文件不依赖数据库内部路径，不保存工具、选框或缩放平移，也不是整个资料库（名称、备注、标签及所有历史版本）的备份。
- `PVZF1:`：同一项目的 Base64URL 文本形式，**不是原站格式**。
- 原站字符串：支持26地图编号、已验证对象、外表帧及七位效果字段；未知类型和不能表达的属性显式拒绝。
- PNG：静态图，不可代替可编辑备份。

备份单个阵型可导出完整项目；备份**全部草稿、存档元数据与历史版本**，应正常退出后复制私有目录的数据库文件及旁边可能存在的 journal/WAL/SHM 文件。恢复前先保留现有目录，再在应用关闭时恢复同一整套备份。当前未提供一键整库备份/合并导入 UI。

项目导入上限 8MiB、5000 对象，校验类型、版本、坐标、占格、ID、效果、缩放与内置资源版本；不执行任何导入代码。非法导入在验证通过前不会替换当前文档。尚不支持用户自定义图片资源；未知资源清单明确拒绝。

## 原站兼容与素材

浏览器已成功操作 [参考布阵器](http://jspvz.com/ArrayDesign/)，取得真实输入输出和 DOM 证据；外部 `main.js` 正文仍受读取工具限制，未声称完整解析其协议。

原站字符串支持26地图编号、标准48植物与实际验证的僵尸/物品编号、外表行列与七位效果。扩展字段保存在完整项目中；水平翻转可导入导出，未知编号和未验证缩放/垂直翻转编码仍会明确拒绝。没有PvZ Toolkit实机兼容验证。

本地素材来自原站页面，包括原图卡片、角色帧和26地图；可离线编辑与导出。素材位置和来源见[素材说明](docs/assets.md)。当前剩余差异包括声音、窗口拖动/样式、部分特殊地形限制与动态附属效果、扑克等宽和部分扩展定位。以[功能对照](docs/feature-parity.md)为准，不能将当前版本称为全部功能验收完成。

## 验证记录

```sh
flutter analyze
dart test test/formation_test.dart test/storage_test.dart test/website_codec_test.dart test/original_catalog_test.dart test/layout_actions_test.dart
# macOS/类 Unix；引擎路径可用 FLUTTER_ENGINE_DIR 指定
FLUTTER_SDK=/path/to/flutter ./tool/check.sh
```

`tool/check.sh` 执行静态分析、纯 Dart / 真实 SQLite 测试、Flutter debug bundle 构建，再编译并直接运行 render/session/ui 三套 Flutter engine smoke。该方式避免当前沙箱禁止本地测试 server socket 的限制；不等同于平台安装包或真机验证。

当前已执行结果与具体覆盖范围见 [实施与验证记录](docs/progress.md)。macOS Debug完整构建现已通过并实际启动，见[运行记录](docs/macos-run.md)；此前Flutter子进程构建曾因Xcode服务/工作区访问失败。Android 已尝试构建，但 Gradle 7.6.3 下载遇到 `UnknownHostException: services.gradle.org`，未产出 APK。Windows、Linux、iOS **未构建或运行实测**。原生文件选择、保存对话框及桌面退出握手仍需各平台交互验收。强杀/掉电/实际磁盘耗尽未测试；已有 SQLite 写锁/事务失败和损坏文件测试。

## 代码职责

`lib/domain`：不可变文档、验证、局部布局与两套编解码；`lib/editor`：命令历史、自动保存会话、坐标及离屏绘制；`lib/storage`：串行 SQLite 仓库与事务/迁移；`lib/platform` 与原生 runner：文件接口；`lib/main.dart`：资料库及响应式编辑 UI。UI 不执行 SQL，绘制器不管理存档。
