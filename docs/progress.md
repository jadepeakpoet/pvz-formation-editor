# 实施与验证记录

2026-10-20：早期网络访问失败后，Chrome 成功访问并实测原站基本阵型、预设、屋顶坐标和半比例镜像创建；main.js 脚本体仍受阻。详细证据与功能边界见 [feature-parity.md](feature-parity.md)。本文件记录实际执行证据，不能替代未实测平台的验收。

## 已执行的聚焦验证

| 范围 | 命令/入口 | 实际结果 |
|---|---|---|
| 文档与导入校验 | `/tmp/pvz-flutter-sdk/bin/dart test test/formation_test.dart` | 4 组测试通过：多层/跨格/全部效果往返、PVZF1 往返和拒绝其他输入、格式/版本/资源/schema/字段/大小/NaN 校验 |
| 画布与 PNG | 编译并直接运行 `tool/render_smoke.dart` | PASS：全部地图格子中心命中（含屋顶坐标变换）、2x 为 2200×1600、透明空图无网格/坐标辅助、炮绘制跨两格 |
| 会话与真实 SQLite | 编译并直接运行 `tool/session_smoke.dart` | PASS：空白不建草稿、有效修改后保存、700ms 防抖（300ms 未保存、800ms 已保存）、批量单历史项、撤销重做及分支、自动保存不改存档、A 编辑另存 B 后 A 不变、重建会话恢复 savedFingerprint、SQLite 写锁失败时内存保留及重试成功、多个会话/多版本排队不串档、删除含待执行保存的草稿后不复活 |
| 静态分析 | `flutter analyze lib/editor/board_painter.dart test/formation_test.dart tool/render_smoke.dart`；`flutter analyze tool/session_smoke.dart` | 均 No issues found |

会话失败测试使用另一个真实 SQLite 连接持有 `BEGIN EXCLUSIVE`，使仓库写入超时，然后释放锁并重试；不等同于磁盘耗尽或真实进程崩溃测试。恢复 savedFingerprint 测试从数据库重建会话，未执行设备强杀。

## 无 socket 的 Flutter 引擎 smoke 运行方式

普通 `flutter test test/board_painter_test.dart` 被当前沙箱禁止绑定 `127.0.0.1` server socket，测试断言未执行；已改用直接 Flutter engine 运行同等核心断言。

```sh
/tmp/pvz-flutter-sdk/bin/cache/dart-sdk/bin/dart \
  /tmp/pvz-flutter-sdk/bin/cache/dart-sdk/bin/snapshots/frontend_server.dart.snapshot \
  --sdk-root /tmp/pvz-flutter-sdk/bin/cache/artifacts/engine/common/flutter_patched_sdk \
  --target=flutter --packages .dart_tool/package_config.json \
  --output-dill /tmp/pvz-session-smoke.dill tool/session_smoke.dart
/tmp/pvz-flutter-sdk/bin/cache/artifacts/engine/darwin-x64/flutter_tester \
  --disable-vm-service --run-forever --enable-software-rendering \
  /tmp/pvz-session-smoke.dill
```

将 `session_smoke` 替换为 `renderer-smoke` 对应输出名并将入口改为 `tool/render_smoke.dart` 即可运行渲染检查。`--run-forever` 保持引擎直到脚本显式退出，避免异步 PNG 编码前提前退出。SDK 和引擎架构路径属于当前机器，其他环境须调整；临时 SDK 不随产品分发。engine 目录的 x64 frontend snapshot 与当前 arm64 Dart 不兼容，实际使用 dart-sdk 目录内 snapshot 编译成功。

平台完整构建、交互验收、原站基本子集以外协议、素材许可和未覆盖故障场景须另行记录。上述 smoke 结果不能推导 Windows/Linux/Android/iOS 已通过。

## 原站表单实测与保守字符串兼容（2026-10-20 后续证据）

后续浏览器成功访问 <http://jspvz.com/ArrayDesign/>，主协调代理通过 Load/Save 表单操作及读取对象 DOM 核实以下范围，替代前述“完全无法访问”的早期状态：地图索引 `0..5` 分别为泳池、夜晚泳池、白天、夜晚、屋顶、月夜屋顶；48 个标准植物 ID 使用十六进制 `0..2F`，逐坐标放入后读取 DOM 确认映射；六字段记录保存后追加默认第七字段 `1`；模仿者位 `1` 产生 `p_Gray`。真实保存样例为：

```text
0,0 1 1 0 0 0 1 ,2F 2 3 0 0 0 1 ,10 3 1 0 0 0 1 ,1E 3 1 0 0 0 1 
```

这是原站表单及 DOM 的已验证行为。虽然已发现 `main.js` 地址，但脚本正文抓取仍失败；额外字段、其他对象及效果不能据此认定协议已查清，也不代表 PvZ Toolkit 兼容性。应用仅实现该保守子集；导出前阻止无法表达的对象、同格同类别重叠、自定义图层、非默认外表、缩放、水平/垂直翻转、除模仿者以外的效果及非默认显示设置。

`/tmp/pvz-flutter-sdk/bin/dart test test/website_codec_test.dart --reporter expanded`：8 组测试全部通过，覆盖真实样例逐字往返、独立 48 植物映射 fixture、六地图、六/七字段及模仿者、扩展字段与非法坐标拒绝、导出损失阻止（含垂直翻转）、不同叠放类别、8 MiB/5000 条限制。`flutter analyze --no-pub lib/domain/website_codec.dart test/website_codec_test.dart`：No issues found。

## 最终集成验证与交付边界

- 最终 `flutter analyze`：No issues found。
- `dart test test/formation_test.dart test/storage_test.dart test/website_codec_test.dart --reporter expanded`：**26 项通过**（文档与细分过滤 5、SQLite 13、原站子集 8）。
- `flutter build bundle --debug --no-pub`：通过，生成 debug kernel 与本地资源；这是 Dart/资源编译，不能冒充原生安装包构建。
- `tool/render_smoke.dart`：通过。除原有 PNG 验证外，新增实测屋顶差值/第六列后平坦、缩放对象跨逻辑格命中、层命中顺序与 PNG 半透明 alpha 验证。
- `tool/ui_smoke.dart`：真实 Flutter engine 中通过。指针拖放恰好两对象、一次整体撤销/重做、提交草稿；窄屏素材面板无布局错误；文本焦点下 Delete 保留棋盘对象，点击画布后 Delete 生效。使用模拟指针/键盘事件，不是真机测试。人工查看输出截图确认棋盘、工具、状态栏和窄屏入口；截图只在临时目录，不作为原作素材分发。
- `tool/session_smoke.dart` 最后增补：SQLite `BEFORE DELETE` 触发器强制删除失败后，session 恢复可编辑、已提交内容保留，解除失败后继续编辑可保存，没有遗留墓碑。此定向运行通过；不把失败删除误显示为文档保存失败。
- `dart run tool/catalog.dart --check`：清单与目录一致。`tool/check.sh` 可统一重跑静态分析、26 项测试、bundle 和三套无 socket 引擎检查；SDK/engine 路径可由环境变量指定。

### 原生平台

| 平台 | 实际执行 | 结果与边界 |
|---|---|---|
| macOS | CocoaPods 安装成功并同步依赖；Swift 入口语法/类型检查；尝试 Flutter macOS build 和直接 xcodebuild | Swift 检查通过；完整构建 **未通过**：受管环境 Xcode/CoreSimulator/XPC 服务异常，最终报告工作区不可访问/not a workspace file；未启动原生窗口，未验收文件面板或退出握手 |
| Android | 检查本机 SDK/JDK，`GRADLE_USER_HOME=/tmp/pvz-gradle JAVA_HOME=<本机JDK17> flutter build apk --debug --no-pub` | **未通过**：所需 Gradle 7.6.3 未缓存，下载时报 `UnknownHostException: services.gradle.org`；尚未编译 Kotlin/插件，也没有设备运行证据 |
| iOS | 原生文件接口源码与 Swift 语法检查 | 未完整构建、未模拟器/真机测试；同宿主 Xcode 服务已受阻，没有重复运行同类失败构建 |
| Windows | SQLite/文件/关闭握手源码对照 Flutter 接口 | 未构建或运行；需目标宿主、系统 SQLite 和 PowerShell |
| Linux | SQLite/文件/关闭握手源码对照 Flutter 接口 | 未构建或运行；需目标宿主、libsqlite3 与 zenity |

macOS、Windows、Linux 普通窗口关闭会先请求 Dart `prepareExit`，提交当前手势并等待草稿 flush；仅成功后关闭，失败保留窗口。移动端后台事件也会提交手势并尽力 flush。原生握手未被设备/真实窗口验收；OS 强杀、系统强制注销/掉电、实际磁盘耗尽和大规模压力未实测，不能由引擎 smoke 推导这些情形已通过。

### 工作目录与同步

初始目录为空，不是 Git 仓库，没有既有文件或暂存改动可覆盖。完成里程碑时尝试 `git init`，受管权限对 `.git` 返回 `Operation not permitted`，没有创建成功。因此不能在当前沙箱提交；没有确认的远程地址，未推送。源码与全部文档保留在当前工作目录；临时 SDK、Gradle home、数据库、日志和截图位于临时目录，不是产品源文件。

已完成本地原生编辑/持久化闭环及文档交付。剩余工作是取得原站脚本正文/完整扩展与素材许可，补齐原站其余地图/名阵/帧/DIYTime规则，并在各目标平台完成原生构建、文件操作、正常关闭与设备生命周期验收。当前没有已知的未处理核心存储缺陷；这一陈述不替代上述未实测范围。


## 原站复刻重构里程碑（2026-10-20）

用户将目标明确调整为尽量1:1复刻原站全部功能。当前已将原来资料库入口和三栏占位编辑器改成默认直接编辑、800×600原图画布和380px经典六标签工具箱。

### 实际来源和实现

通过browser技能实测原站，并导出初始248图片及26地图底图/叠加层，读取97模板、363名阵、36炮布局和21菇布局。原始目录数据保存到assets/original_catalog.json，图片及帧/地图元数据在assets/original。没有引入WebView或在线图片依赖。

实测扩展输入：2A外表row1；30梯子；31钉耙；32墓碑；多个僵尸/物品编号；七位gray文本。原始额外字段保存在Piece中，编辑移动时清除失效位置，修改效果不会被旧字段覆盖。420个完整/局部预设全部通过解析及项目保存往返。

草地、泳池、五/六行屋顶、高地通过Peashooter/Cobcannon DOM锚点测量；修复炮向右40px、屋顶行高、推车原始帧、继续标识底部遮罩和透明导出菜单残留。

### 本轮验证

- dart analyze lib test tool：No issues found。
- 37项领域/SQLite/编码/目录/一键操作测试通过。
- 直接执行flutter_tools.snapshot build bundle --debug --no-pub：通过。直接调用用于避开SDK启动脚本cache lockfile权限问题，不代表原生平台完整构建。
- render_smoke真实引擎：27地图格子中心命中；透明空图无辅助或菜单；2x为1600×1200；半倍400×300；真实素材跨格炮和半透明像素验证通过。
- ui_smoke真实引擎：拖放和单历史撤销/重做、手动外表、翻转、卡槽持久化、三镜像上限、选择名阵不立即修改、保留地图布阵、下一个阵、内联字符串获取/载入、窄窗滚动。额外验证原图/3/4/2/3/1/2 PNG尺寸以及自定义显示设置不妨碍只导出阵型。
- session_smoke真实引擎：草稿防抖、撤销重做、存档隔离、SQLite写失败重试、排队会话、删除墓碑及删除失败回滚通过。
- 实际截图在/tmp/pvzstudio-editor.png、/tmp/pvzstudio-layouts.png、/tmp/pvzstudio-transfer.png，已人工查看。

### 剩余范围与同步

这是可审阅的复刻改进里程碑，仍未声称全部功能100%完成。声音、桌面窗体拖动/样式、扑克等宽、动态土壤/散雾及部分附属效果、扩展绝对定位尚未完全复刻，见feature-parity.md。原站当前DIYTime按钮本身display:none。

当前目录仍不是Git仓库；此前git init已经受管权限阻止，没有确认的远程地址。本轮未提交或推送。保留工作目录所有现有原生平台代码；未重跑此前已知失败的原生宿主构建，不把引擎验证当成平台安装包验收。

最终UI修复：默认种植替换同层同类对象，避免重复点击无限叠放导致原站字符串无法获取。跨格炮替换两格普通植物，保留睡莲/南瓜等其他层；实际引擎验证重复点击不增加对象、一次撤销恢复原fingerprint、批量替换整次撤销。源码最终静态分析No issues found。默认不再显示编辑网格。


## 继续1:1与实际原生运行（2026-10-20，本轮）

用户要求运行当前应用并继续原版复刻。本轮已通过直接调用xcodebuild成功生成macOS Debug应用，并实际open启动。此前Flutter子进程中Xcode服务拒绝、CocoaPodsPATH错误不再等同于本轮原生构建结果；详见macos-run.md最终证据。

### 原站实测与修正

- 原站AutoSelect逐项读取选中行列，泳池：后置炮陆路第4列、前置第5列、超前置第7列、底线第1列；水路前场第7–9列；水路56列第5–6列。新增纯领域选择集合并接入图鉴批量模式，重置及分类删除/批量种植可直接使用。
- AutoGrow11项通过原站载入/获取实际操作，重复输入确认花盆外表row1/随机col0–1，荷叶row0/随机col0–2。补容器只作用于已有植物或单独南瓜，玉米炮两格都补；搭梯须坚果/高坚果+同格南瓜。修复此前错误的全图填充和删除容器。碾花盆/炸荷叶在所测默认及非默认外表输入下均不改变字符串，当前保留对象和帧，没有臆造删除行为。
- 水平翻转实际种植保存及8字段载入验证：scale1后side1，导出按当前flipped覆盖旧字段。原站上下/双翻在测试中没有相应side输出，当前仍明确阻止垂直翻转字符串导出以防丢失；完整项目和视觉翻转保留。
- 镜像改为应用内可拖动浮窗，最多三个，各自背景/六倍率/PNG导出，保持创建时独立文档；工具箱标题可拖动且有窗口复位。详情见mirror-windows.md。

### 验证

- 45项领域/SQLite/编解码/目录/原站一键fixture测试通过。
- 全部lib/test/tool静态分析No issues found。
- 最终真实Flutter engine UI smoke通过；新增镜像拖动/关闭/六倍率/独立背景/源文档改变不污染快照，并验证图鉴快捷后置炮4格、水路56列4格、重置。此前连续种植、撤销、卡槽、名阵、导入导出及窄窗仍通过。
- 最新界面截图 /tmp/pvzstudio-mirrors.png、/tmp/pvzstudio-editor.png 等已人工查看。

声音、窗体皮肤和部分动态附属效果仍未完成，不声明全功能100%一致。工作目录依旧无Git仓库和已确认远程，本轮未提交/推送；不以源码同步替代运行证据。


## 2026-10-22 工具箱、选阵导航与首屏

范围：花园风格工具箱；只读页面可选择懒人布局；名阵共用卡片选择器；任何当前页阵型替换可后退／前进并恢复名称；模板使用后返回列表；跨行绘制和命中层次修复；独立存档库首帧不等待全部素材、模仿者灰度按需生成。

协作归属：主协调负责main/library/window bridge、平台接线和整体验证；独立阶段实现editor_tabs与生命周期测试；独立渲染阶段负责board_painter/original_assets及像素与资源测试；独立审查发现并跟进文件操作导航守卫、失败传播、版本恢复与工具箱旧状态覆盖问题。

当前目录无Git元数据，无法创建提交或远端同步；保留本地修改。本轮验证：

- `/tmp/pvz-flutter-sdk/bin/flutter analyze`：无问题。
- `tool/editor_tabs_smoke.dart`：真实Flutter引擎＋临时SQLite，19/19通过，覆盖逐页后退／前进、名称和撤销记录、历史分支、失败保留、全部会话保存、删除存档历史及同一存档版本恢复。
- `tool/formation_navigation_smoke.dart`：4/4通过，覆盖真实选择器点击→当前页、只读预览选择布局、实际文件导入路径和导航守卫、地图替换后退。
- `tool/preset_actions_smoke.dart`：5/5通过，覆盖模板成功使用后返回列表、继续打开、菜单安全操作与个人存档行为。
- `tool/formation_io_smoke.dart`：7项实际文件／格式对话框和SQLite检查通过（仅文件选择平台通道模拟），包含导入、覆盖备份、恢复及再次恢复。
- `tool/layer_order_smoke.dart`：真实不透明像素重叠及命中顺序检查通过，覆盖跨行南瓜／植物、忧郁菇附属层、同格花盆／荷叶／南瓜；原有render_smoke通过。
- `tool/assets_loading_smoke.dart`：按需灰度、精确HSL像素、并发去重／缓存／重绘、首次PNG灰度与南瓜背面准备通过。相同本地引擎下273张源图加载测量由424ms降至90–95ms；此数字是本机素材准备，不代表所有设备端到端延迟。
- `tool/library_startup_smoke.dart`：真实引擎首帧约269ms显示加载界面，首帧图片数量0，之后实际存档列表可见；配置通道模拟，不能视为原生窗口整条链路性能基准。
- `tool/toolbox_tabs_native.dart`＋限定CGEvent鼠标驱动：真实原生多引擎窗口，12次跨焦点标签单击＋工具箱转交主窗口选阵／当前页打开／后退恢复通过，数据库为内存，不改用户资料。
- macOS正常入口Debug `xcodebuild ... FLUTTER_TARGET=.../lib/main.dart build`成功。其他平台未构建或实测。

当前页更换后通过顶部后退／前进导航；编辑撤销／重做继续管理单个阵型的植物修改。存档库失败打开保持详情；旧工具箱布局请求通过基础指纹验证，拒绝覆盖主画面新编辑。


## 2026-10-22 自动底座、独立窗口和标签内统一撤销

用户约束：当前标签未关闭即保留全部撤销，清空无需确认；右侧不再跟随左侧拖动；自动荷叶默认开、花盆默认屋顶，可选屋顶及陆地／关闭；普通种植替换旧植物但保留底座及南瓜，玉米炮清理双格植物／南瓜；香蒲、海草、海蘑菇水面不保留荷叶；移除懒人布局额外批量面板。

主协调负责种植规则／设置／UI／原生移动和验证；会话阶段负责名称命令与无限期会话撤销；导航阶段负责按操作顺序跨页面撤销；只读复核发现并修复设置未在启动读取的问题。窗口代码现在只在首次定位右侧，不再注册拖动主窗口时重排侧栏的回调。

已完成：会话检查10组与新增128条撤销／名称检查通过；标签控制器22/22通过；真实原生拖动、存档库切换、12次标签点击及无确认清空撤销16项通过。种植规则7组及导航/撤销界面7组均通过，后续新增批量完成与删除联动检查见下文。当前无Git元数据，修改保留本地。

### 智能铲除、白南瓜搭梯与批选收纳

- 铲除默认“智能”，鼠标跟随铲子，命中对象以自身高亮；高亮与删除共用 ShovelTargets，保留全部原有类型范围。南瓜上方开口可选内层植物，边缘可单铲南瓜；铲除南瓜同时删除同格梯子。
- 懒人布局新增“智能搭梯”，仅给模仿者南瓜补梯，已有梯子不重复添加；通过标签内历史撤销。
- 用户要求保留有价值的批量功能，并指定留在懒人布局。将快捷选区、按类型铲除、批量种植、批量模仿收进折叠区；外部常驻显示已选数量与“取消选区”。右键/Esc 也可取消。批选提示改为淡绿填充，取消后消失。
- 预制阵型列表改为工具箱内部显示；选择直接在当前标签打开，列表保持，支持回退。
- 检查：flutter analyze 无问题；shovel_preview_smoke 实际渲染及智能目标/范围/只搭白南瓜/幂等检查通过；过滤的 board.clear 与 mirror.snapshot 通过。原生窗口拖动、模式切换和 12 次首击标签通过；新增右侧列表原生自动化未定位到卡片，暂未通过该项，不作为产品通过证据。软件渲染的右侧列表点击/导航测试通过。
- macOS Debug 构建成功，使用 open -n 启动，保留此前应用实例以免丢失用户的内存撤销历史。当前目录无 Git 元数据，无法提交。
- 最终 formation_navigation_smoke 7/7 通过：右侧列表点击、只读布局、文件导入、地图历史、清空统一撤销、一键格式化撤销、外部取消选区（阵型指纹不变）。最终 flutter analyze 无问题，macOS Debug 再次构建成功并启动。

### 讨论需求收尾核对

- 保存成功（普通归档、另存存档、阵图文件）后自动清选区并退出批选。失败、取消不会清除。编辑区右上角、懒人布局已选数量旁和批量折叠区均增加“完成批量操作”。
- 独立只读核对发现并补齐：智能命中不再限制于鼠标逻辑格；炮清除覆盖范围梯子；Delete 删除南瓜同步删附梯。
- formation_navigation_smoke 扩展至 8/8 通过，新增保存后清选区及工具栏完成按钮检查，确认不改变阵型和撤销深度。shovel_preview_smoke 新增可见精灵跨格命中检查通过。完整应用构建和原生右侧列表检查见后续记录。
- 最终审查范围覆盖本轮所有讨论项：点植株切帧、右键复原、模仿者单独改植株、跟随种植和取消、右侧标签和独立窗口、工具箱庭院配色、懒人布局与预制库共用卡片/当前页导航、标签内完整撤销和无二次确认、模板使用返列表、按行绘制、存档库首帧加载、底座偏好及水生排斥、炮/南瓜覆盖清理、格式化后放优先、铲子跟随和智能铲除、仅白南瓜搭梯、批量功能保留与结束清选区。对应实现和已通过证据在上文。
- 本轮原生自动化重试在鼠标拖动检查未通过，原因尚未确认，可能与当前多个已有窗口的前台关系有关；未取得新增列表卡片 OS 点击的通过证据，停止重复同类重试。既有真实12标签、独立窗口通过记录与本轮软件界面列表导航通过记录分别保留，不混淆覆盖范围。
- 收尾结果：种植/支持/铲除实际编辑链路 8/8 通过（包括伸出格子的高坚果点击删除及撤销、Delete 南瓜与梯子原子删除及撤销）；保存/导航/批量完成界面8/8通过；shovel渲染通过；flutter analyze无问题；最终macOS Debug构建成功且open -n启动。

## 2026-10-22 全功能点击冒烟与性能验证完成

本轮按用户要求先全功能点击/冒烟，再单独性能测量。755项全量UI声明与执行一致，最终755通过，含420布局；初轮743通过/12失败的原始证据与独立复测保留。17文件747领域测试、25套编辑器/渲染与11套存档库/导出/游戏文件检查通过。原生16工具箱、2文档、4多标签、4真实系统文件面板及实际AVAudioPlayer检查通过。资源过期和旧UI断言修正仅涉及测试，产品lib未改。细节见qa/full-smoke-2026-10-22.md。

离屏压力、软件UI、原生合并UI和真实双引擎同步性能均完整测量。真实双引擎80有效编辑均成功同步；初始80对象主响应P95约32ms/同步约113ms，500对象约50ms/145ms（含10ms轮询和文件IPC）。正常原生列表滚动P95约60ms，存在UI构建尖峰，已记录为性能优化点，不把本次诊断称为性能全通过。Profile工具架构不兼容，使用Debug；无发布FPS/跨平台性能结论。报告见qa/performance-2026-10-22.md。原始测试数据均隔离，完整命令和日志在/tmp/pvz-full-*、/tmp/pvz-performance-*。
- 最终清理后复核：保留的6个空闲QA实例均按专用构建路径关闭，再串行复测原生合并UI及真实双引擎。最终实际80对象编辑P95约33ms、同步约87ms；初始500对象编辑约47ms、同步约137ms；原生列表滚动约30ms、切换约80ms。旧测量另存before-cleanup，报告最终表已更新，不把环境差异称为代码优化。所有性能场景complete且零FlutterError。
- 当前目录没有Git元数据，本轮测试脚本和报告均保留在本地，无法提交/推送。

## 2026-10-22 名称区重命名入口

主窗口与合并布局共用documentHeading：点击“名称 · 保存状态”直接进入原有重命名流程，铅笔按钮紧邻文本，移除工具栏右侧独立编辑图标；只读或正在显式保存时禁用。名称超长仍省略显示。focused workflow.save-rename-history真实指针检查通过：点击标题重命名并持久化，图标与标题间距不超过6px，图标再次打开弹窗，取消不修改名称或撤销深度。macOS Debug构建通过；目录无Git元数据，修改保留本地。

## 2026-10-22 名称原地修改

名称区改为原地输入，自动选中旧名称；回车、失焦或旁边勾选保存，Esc 取消，空白不修改。单次重命名保留一个可撤销历史项；切换标签和保存前提交输入，并固定目标会话，避免串改其他标签。静态分析无问题，macOS Debug 构建通过并启动。

验证：focused workflow.save-rename-history、workflow.inline-rename-switch 均通过，覆盖标题/相邻按钮、回车、Esc、空白、失焦保存、撤销重做、切换标签提交及只读禁用。首轮测试在撤销/重做后未等待界面刷新，补充等待后完整通过。

## 2026-10-22 批量选区删除

懒人布局选区摘要及批量操作区新增“删除选区”，Delete / Backspace 优先删除批量选区，无批量选区时删除单选对象。覆盖格子全部图层及横跨选区的炮，保留按类型铲除；不弹确认，单次删除一条撤销记录，只读禁止，空选区不改历史。focused formation_navigation 的 batch.cancel、batch.save-finish、batch.delete-selection 均通过（含全部图层、炮前格、区外保留、撤销重做、重复删除及只读）；flutter analyze 无问题，macOS Debug 构建通过。目录无 Git 元数据，无法提交。

## 2026-10-22 名称输入框尺寸

原地名称输入框按原名称文字宽度加少量留白，限制在 80–220px，高度降至 22px；不再撑满标题区域。仅尺寸调整，flutter analyze 和 macOS Debug 构建通过。

## 2026-10-22 玉米加农炮占位替换

状态循环只匹配种植起始格，避免在炮前半格种新炮时误触旧炮状态切换。非花盆/荷叶的新对象与旧炮任一格重叠时移除整炮；2–3列新炮同时替换1–2列和3–4列旧炮。新增真实种植手势用例验证双炮替换、撤销重做、普通植物/南瓜/梯子替换及容器保留。flutter analyze 无问题、macOS Debug 构建通过。

planting_support_smoke 全部9项通过；新版已启动。当前目录无 Git 元数据，修改保留本地。

## 2026-10-22 智能铲除命中修复

智能铲除按当前精灵帧的 alpha 轮廓命中，排除透明边界与地面阴影，并复用渲染的锚点、缩放、翻转、屋顶/花盆偏移。按实际文档按需缓存一位轮廓；南瓜开口保留内部植物语义。一次拖动命中按按下时快照解析，删除前景后不穿透继续删除后行目标，高亮与删除共用结果。planting_support_smoke 全10项通过，新增合成4帧×屋顶/池塘×缩放/翻转测试、跨行透明遮挡与连续移动不穿透及撤销重做；shovel_preview_smoke通过，保留南瓜带梯、范围列表、容器与导出验证。旧测试点击了高坚果透明边角，修正为上方可见像素；静态分析无问题，macOS Debug构建通过。下一任务：用户自建存档标签管理、标签搜索与标签列表查看。

## 2026-10-22 存档标签与标题外观

自建存档详情和菜单新增“设置标签”：复用已有标签、多选、新建、取消、清空；保存时未点添加的输入同样提交，空白及重复标签去除。使用现有 SQLite 标签与版本机制、主窗口文档请求，保留名称、备注、阵型。详情标签可点击返回列表，窄/宽版列表增加可折叠标签索引及数量；点击标签清空旧搜索/场景/炮数过滤并展示精确标签的所有自建存档，之后可叠加文字搜索。预制名阵不提供标签编辑。

标题始终显示紧凑的名称编辑框边框/底色，保持原地编辑、Enter/失焦/勾选保存和Esc取消；按用户要求移除“已保存”等状态文案。

验证：library_tags_smoke 在410px与1224px各4项全通过，包含标签创建复用去重、待提交输入、持久化重开、精确分组、搜索、取消、全部清空、存档其他内容保持和历史版本；library_narrow_smoke全部5组通过；focused document_workflow两项通过。静态分析无问题，最终macOS Debug构建通过。当前目录无Git元数据，无法提交。

## 2026-10-23 懒人布局选择后返回首页

useFormationPreset 成功应用后清除选择列表状态并回到懒人布局 tab：首页、炮位、无炮三组一致；独立工具箱等待主窗口处理完成后再关闭列表，异常仍保留列表。focused picker.history 与 picker.layout-return 均通过，覆盖单击阵型后返回首页、回退恢复原名称与阵型，以及炮位/无炮选择后的返回行为。静态分析无问题，macOS Debug构建通过。

## 2026-10-23 工具箱顶部标签反复失效：根因修复

根因已在原生多引擎 QA 复现：共享 NSWindow 从存档库切回工具箱后，Flutter 仍停在 AppLifecycleState.hidden，framesEnabled=false。真实鼠标 Down/Up 已到达 Dart，classicTab 与 pickingPresetGroup 均变化，但 widget 树没有重建（选择器 pickerBuilt=false）。此前原生测试仅验证 state tab，漏掉重绘，导致误判通过。排除了 classicTab 同步覆盖、模态路由遮挡与线程卡死；同机多个旧实例叠放是另外的干扰，非本次确定根因。

修复：共享原生侧栏 host 统一管理两个引擎的生命周期。在模式切换、显示隐藏、焦点、应用活跃/隐藏、最小化及 occlusion 通知后，合并到下一主队列回合，以实际挂载窗口和可见性发送 flutter/lifecycle。可见引擎恢复 resumed/inactive，离屏引擎保持 hidden；不更改文档或撤销记录。独立只读复审未发现循环或阻断问题。保留有界原生事件诊断便于以后核对。

验证：toolbox_tabs_native + 真实 CGEvent 驱动全部23项通过；18次标签单击每次都核对 framesEnabled、实际构建选中项与已完成绘制帧的 tab；其中4次确认 Finder 实际活跃后首次单击，6次关闭重开，反复存档库/工具箱重挂载；真实最小化恢复、独立窗口拖动、原生选阵回退、清空撤销均通过。旧驱动固定28px标题栏造成4px坐标误差，更新为当前32px。静态分析无问题，产品 macOS Debug 构建通过。基线与最终报告位于 /tmp/pvz-tab-rootcause-before.json、/tmp/pvz-toolbox-tabs-first-click/report.json。当前目录无 Git 元数据，无法提交。

新版已启动并检查原生窗口可见；仍运行的旧实例已隐藏，保留其内存撤销记录。隔离 QA 实例正常退出，临时服务发现命令已清理。

## 2026-10-23 替换启动、再次点卡取消及铲除范围

按用户最新明确要求，后续更新必须正常退出旧实例后启动一个新版，不再新增或隐藏旧实例。新增 tool/restart_macos_app.swift：限定同一 PVZ app bundle，请求正常退出，等待保存/退出完成；失败保留旧应用且不启动第二份，绝不强制结束。项目 AGENTS.md 记录此工作流。

图鉴选卡再次点击当前卡片取消待种植与鼠标预览；卡槽选卡再次点击原卡片或已选卡槽可移除，模仿者索引随移除调整，单次可撤销/重做，移除当前卡片同时取消种植。铲除范围两处UI移除最上层，旧跨窗口值兼容归一为智能，其余按类型范围保留。

验证：cards.toggle通过（图鉴选/取消、无阵型历史污染、卡槽增删/模仿者索引/撤销重做及范围选项）；seed_chooser_smoke全部8组通过；ui_smoke全部3组通过（拖种撤销、存档、窄界面）。静态分析无问题，macOS Debug构建通过，重启工具Swift类型检查通过。

## 2026-10-23 顶部铲子区、咖啡豆叠加与原版规则参考

顶部十卡槽后加入原版 ShovelBank 原图，位置按原版456+153=609，铲子偏移-7/-3；点击直接切换铲除，拿起时槽内铲子消失并复用指针跟随及智能高亮，再点放回。控制覆盖层不进入图片导出；拦截对应区域的底层地图手势，避免误铲长到HUD下的植物；只读禁用，关闭卡槽显示时同步隐藏。

咖啡豆修为独立上层槽，与底座/主植物/南瓜共存，只替换咖啡豆，不自动补底座；普通植物替换不清独立咖啡槽，炮冲突规则保留。修复给猫尾套南瓜误补荷叶。新增 coffee.independent-slot、shovel.top-bank，实际指针验证切换、目标高亮、铲除/撤销、只读、HUD遮挡和隐藏；最终 planting_support_smoke 全13项通过。首轮旧断言曾要求普通植物清咖啡，按用户最新叠加要求更新断言后全通过；静态分析无问题，macOS Debug构建通过。人工查看截图确认原版铲子区在卡槽后、菜单前，咖啡豆叠加显示。


本轮新版通过正常退出替换启动，未额外保留旧实例。

## 2026-10-23 工具箱滚动防回弹与位置保持

工具箱统一使用 ClampingScrollPhysics 并关闭 overscroll 指示，含工具箱内的阵型选择列表；主体滚动视图显式 primary=false，每个顶部tab拥有独立ScrollController/PageStorageKey，切页、状态刷新与临时打开选择器不会丢失原滚动位置。controller随EditorPage销毁。

验证：ui_smoke全部4组通过，新增真实指针上下拖至边界、拖动与松手不越界、普通重建/切tab/打开选择器再返回保持offset，以及选择器继承无弹性物理；其余拖种撤销/存档/390px窄视口回归通过。首轮测试点落在系统滚动条上而非内容区，改在内容留白处拖动后通过。静态分析无问题，macOS Debug构建通过。

用户关于重做/恢复的提问：回复行业常见命名为撤销/重做，恢复易与恢复存档/默认值混淆；本轮未擅自改按钮名称。

## 2026-10-23 — 启动恢复与空白页延迟保存（已完成）

已确认根因：启动只读旧draft记录，但v4已将draft迁入archives；随后默认新建会话在构造时立即保存，导致每次进入新增空档。当前改为 EditorSession.resume 按独立last_opened_archive指针恢复可编辑阵型；无指针时优先最近实际内容/自定义名字，保留全部旧档。默认空白页延迟保存，首次命令或显式保存才创建archive；已存档清空照常自动保存及撤销。临时页名字仅在开放tab间分配，首次入库时规范化唯一名字。主动保存空页生效，取消另存为不先生成空档。

改动范围：editor_session.dart、editor_tabs.dart、formation_repository.dart、main.dart。SQLite以附加editor_preferences表保留编辑激活指针，与updated_at排序独立；三引擎共享DB，但仅主工作区写入激活记录，刷新/预览/空页不改变有效目标。代理先前只修改tool/startup_resume_smoke.dart、tool/session_smoke.dart、tool/editor_tabs_smoke.dart，服务恢复后代理已不在，主agent接管验证和补充测试。静态分析、macOS Debug构建通过；startup_resume 8组、session 10组、editor_tabs 22组、tabs_workspace 5组共45项通过。旧历史测试显式保存初始化fixture后保留原覆盖；首轮4个失败源于旧fixture依赖自动保存/命名完成时序，并非忽略后继续。真实两次正常退出替换启动前后archives总数均81，恢复ID一致，单实例；截图确认恢复新建阵型（37）的豌豆+荷叶，而非空页。独立只读审查无阻塞问题。证据 docs/qa/startup-resume-2026-10-23.json；应用已更新。无Git元数据，无法提交或推送。


## 2026-10-23 — 启动恢复、历史按钮、铲子与原站选卡收尾

用户确认继续未完成的启动恢复修复：未修改的新建空白页不入库，首次实际编辑、重命名或明确保存才创建个人存档；已有存档清空、撤销或恢复后仍正常保存。启动依据上次激活的可编辑存档恢复，不使用最近更新时间代替；临时空白和只读页不覆盖记录。首次升级没有记录时优先实际工作，旧自动空白仍无损保留。恢复保存的阵型和名称，不跨进程恢复撤销栈或全部标签。

用户明确将“重做”文案改为“恢复”，配左右弯曲箭头；悬停说明恢复刚撤销的操作。Ctrl/⌘Z撤销，Ctrl/⌘Y恢复，Ctrl/⌘S保存，保留⇧⌘Z。真实平台键流专项通过；文本输入的编辑快捷键保护保留。

选中铲子原先画在BoardPainter内，后画的铲子槽控件会覆盖它。现在跟随铲子独立位于画板Stack最上层，IgnorePointer不拦截点击，仍不进入图片导出。专项确认原图、层级、智能铲除及撤销。


回归发现打开选择器再返回会丢失工具箱scroll offset（34变0），改为各tab控制器在脱离时保留位置，不依赖host的PageStorage。相同真实指针回归现已通过；此前失败日志不作为通过证据。

最终相关验证：静态分析No issues；启动恢复真实Flutter+SQLite 8/8；会话10组；标签22项；存储/偏好/迁移23项；选卡独立8组；主UI6/6（含真实首标签直接开关、顶部退卡/模仿者/恢复、快捷键、滚动、窄窗），FlutterError0；种植/铲子13/13。选卡普通/模仿者截图已视检。证据见docs/qa/startup-and-editor-controls-2026-10-23.json。Dart/资源bundle编译通过，不代表完整原生重构建。



## 2026-10-23 — 项目名称与自动底座预览；目录改名请求

用户指定英文名PvZ Formation Editor、中文名植物大战僵尸布阵器。已修改Flutter主界面、macOS产品包名/工程引用/窗口标题、iOS显示名及BundleName、Android默认英文与zh中文app_name、Windows产品信息与窗口标题、Linux窗口标题、README与项目描述。内部包名/各平台应用ID/存档路径/协议保持兼容；macOS保留pvz_formation_editor可执行文件名以保持正常替换启动识别，产品包名为PvZ Formation Editor.app。plutil检查两个Info.plist与pbxproj通过；Android XML与scheme XML解析通过；Swift原生源文件与重启助手语法通过。未重复运行既知受限的完整原生构建。

用户要求种植预览同时显示自动荷叶与花盆：主界面在副本上模拟同一PlantingSupport规则，只向BoardPainter传递新增自动底座，固定逻辑格坐标绘制；已有底座、关闭选项、水生植物和咖啡例外与实际放置一致，多格按占格预览。不写入文档或历史，helpers=false导出不包含预览。新增support.hover-preview专项覆盖实际像素差异、导出排除、格坐标及规则，测试结果待本轮最后汇总。最新静态分析Noissues。

用户明确要求将工作目录pvzstudio重命名为PvzFormationEditor并重新打开。目标为/Users/developer/coding/jadepeak/maydaycode/codex/PvzFormationEditor，当前并无同名目标；操作需写入当前可写根之外的父目录，将在验证与保存记录后尝试。此目录无Git元数据/确认remote，无法提交推送。

补充验收：support.hover-preview与此前种植/铲子回归合计14/14通过，FlutterError0；水面荷叶与屋顶花盆预览截图已视检，像素差异及helpers=false导出排除验证通过。证据docs/qa/planting-support-preview-2026-10-23.json。

最终bundle编译通过。目录重命名实际尝试os.rename(pvzstudio,PvzFormationEditor)被沙箱以PermissionError/Operation not permitted拒绝：父目录codex及新同级路径不在会话可写根范围。未改名、未覆盖其他目录、未重新打开新目录，当前源码仍保存在pvzstudio。当前工具没有修改工作区根目录/重开项目的接口，且环境禁止sandbox提权；需用户在宿主终端改名后用新目录重新打开。


## 2026-10-23 — 中英文界面设置

新增 AppLanguage 持久化语言偏好，存档库设置和编辑器选项设置共用语言选择器。主要界面标签、提示、地图、对话框以及 Flutter 内置组件支持简体中文/English；不修改用户保存的名称、备注、阵型内容或内部标识。部分植物与预制阵型名称保留来源名称。独立 Flutter 引擎每两秒读取原子写入的偏好，同步语言；macOS 原生主窗口和侧栏标题跟随切换。独立审查指出的临时文件竞争和旧读取回写已修复：每次写入使用独立临时目录，并用修订号阻止过期读取。

验证：flutter analyze --no-pub 无问题；language_smoke 在真实 Flutter 引擎下通过下拉框切换、即时 UI 刷新、State/controller 和输入内容保留、偏好重新读取及损坏偏好回退；export_settings_smoke 在 410×640 下通过，FlutterError 为 0。xcodebuild Debug 构建成功，重启脚本正常退出替换一个旧实例并启动新版，进程路径核实仅一个新版应用。未执行其他平台构建，未把原始植物/预制名称视为全部翻译完成。


## 2026-10-23 — 点击拾取铲子后立即显示

根因：toggleBoardShovel 调用 cancelPlanting 清空 plantingPointer，工具槽隐藏铲子后，浮动图标要等下一次移动事件才出现。拾取时保留点击位置，棋盘 PointerDown 先更新位置；放回仍正常清除预览。回归测试移除手动补位置，直接断言连续拾取/放回/拾取后图标即时出现或消失，并保留顶层绘制、点击穿透、删除及撤销、只读覆盖。planting_support_smoke 全部通过，flutter analyze 无问题，macOS Debug 构建成功；截图确认图标在顶部 HUD 上方。


## 2026-10-23 — 普通/模仿者覆盖与自动底座继承

同类植物仅在模仿者标记一致时重复点击切换状态；标记不同时走正常替换，使普通和模仿者可双向覆盖。自动新增的荷叶/花盆仅继承模仿者标记，不修改已存在底座；预览共用规则。planting_support_smoke 全16项通过，新增覆盖六种植物双向替换、同形态状态循环、撤销重做、池塘/屋顶预览与落子、既有底座保留及普通底座回归；flutter analyze 无问题。


## 2026-10-23 — 选卡视觉和棋盘顶部直接操作

选中卡片从去色改为保留原色的约50%压暗；模仿者仍使用独立素材。参考原版选卡截图：https://plantsvszombies.fandom.com/wiki/File:Endless_seed_select.JPG 。seed_chooser_smoke 真实引擎9项通过，像素检查验证保留绿色、降低亮度、退卡恢复原像素，以及普通/模仿者互不混淆。截图 /tmp/pvz-seed-chooser-selected-color-dimmed.png 已视检。

顶部十个卡槽（包含空槽）均可直接打开选卡页，页面打开后点击已选卡片仍退卡；点击区域阻止穿透到棋盘种植，铲子独立。左上角阳光可原位编辑，回车/失焦保存、Esc取消，限制0–99999999整数，支持单步撤销；只读禁用。输入按会话Key隔离，外部数值变动取消旧输入，提交捕获目标会话，避免过期回调写入其他标签。交互棋盘由控件绘制阳光数字，导出继续由BoardPainter绘制，避免编辑时旧数字重影。

主UI真实引擎8/8通过、FlutterError为0；最终字体修正另做阳光专项验证。覆盖十个卡槽、只读浏览、原位输入/重复点击、空值、上下界、回车/取消/失焦、撤销重做、外部更新和只读限制，另保留主UI拖动、保存、滚动、退卡、窄窗和快捷键回归。独立代码审查无阻塞问题。macOS Debug 构建并按restart_macos_app.swift正常替换启动；其他平台未构建。


## 2026-10-23 — 花盆位置勾选与设置精简

自动垫花盆移除下拉框，改为独立的屋顶/陆地勾选，默认屋顶选中、陆地关闭。保留原有roof/land/off偏好语义，新增ground表示仅陆地，兼容旧配置；新值可保存、加载及通过原生窗口状态同步。实际种植和预览共用判断。选项设置移除“对象属性与扩展工具”折叠入口，相应旧UI用例移除该入口依赖。

验证：planting_support_smoke 17/17通过，覆盖默认勾选、四种组合、仅陆地种植/屋顶排除、新模式持久化及设置无扩展入口；截图视检通过。flutter analyze 无问题，macOS Debug构建成功。完整旧parity_ui套件未运行，只更新被删除入口对应的旧用例。


## 2026-10-23 — 主区选卡开关、更多菜单及阳光删除键

两套主区工具栏新增打开/收起选卡按钮，不复用顶部卡片退卡点击。标签栏“+”右侧增加更多菜单，保存/另存为移入菜单，保留保存快捷键；没有标签栏的独立测试宿主在工具栏显示菜单。更多菜单新增重命名弹窗，预填并选中现有名称，空白禁用确认，取消不修改；确认共用既有名称去重、单步撤销和持久化逻辑，捕获目标会话并在异步等待前后验证身份。只读禁用保存和重命名，允许另存为。

阳光输入框增加局部DefaultTextEditingShortcuts，避免外层棋盘CallbackShortcuts吞掉删除键。专项回归：同样测试旧控件Backspace失败，新控件通过Backspace、Delete、选中文本删除和未提交不改文档；测试使用Linux框架按键映射，macOS原生IME未做真实键盘实测，不将该限制视为已通过。主区选卡开关真实点击、更多菜单另存为/取消、重命名预填/取消/空白禁用/确认/撤销重做及只读权限专项均通过。静态分析无问题，独立审查无阻塞问题，macOS Debug构建成功。

额外document_workflow检查中保存、另存为、原地重命名、历史回退、导入和标签切换通过；workflow.new-blank-auto-archives失败，旧用例期待空白标签flush立即建档，而当前未修改的EditorTabsController.newBlank显式deferInitialSave=true、EditorSession.flush默认不强制建档。此项记录为失败，未更改空白存档语义，未宣称全工作流通过。原生窗口自动化document_windows本轮未运行。


## 2026-10-23 — 智能搭梯只保留陆地白南瓜

智能搭梯按OriginalTerrain逐格判断，仅terrain=1且有模仿者南瓜的位置需要梯子；移除水面、裸地、普通南瓜和无南瓜处的既有梯子，合格位置保留首个梯子原属性并清理重复项，缺失则补上。其他对象不变，重复执行不再改变文档。测试原有铲除夹具改为陆地图以保留铲除覆盖含义。

验证：layout_actions_test和original_terrain_test共39项通过，覆盖泳池陆/水、受限庭院裸格、无合格目标清空梯子、有效梯子属性保留、重复项及输入文档不变；shovel_preview_smoke通过，flutter analyze无问题，macOS Debug构建成功。
