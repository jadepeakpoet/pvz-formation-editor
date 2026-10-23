# 全量原站验收任务记录

目标：右侧六标签工具箱全部按钮、下拉、开关、弹窗及左侧结果逐项测试；Flutter全量执行并截图与原站对比，修复后重测，未实现/未执行不得计通过。

阶段：原站控件清单和截图取证；UI真实引擎全量套件；领域fixture全量；像素比较工具与绘制修复。

文件分工：root维护lib/main.dart、原站浏览器取证、docs/parity-cases.json和总报告；full_ui_suite负责tool/parity_ui.dart与tool/parity_support.dart；domain_coverage负责test/parity_domain_test.dart与fixtures；render_parity负责lib/editor绘制文件及tool/parity_render.dart、tool/compare_parity.py。共享stage/commit由root串行；当前目录无Git仓库和确认远程，不能提交推送。

继承约束：保留草稿/存档数据、不能把隐藏或未实现的原站能力标为通过，不能用缩小验收范围或调宽图片阈值掩盖差异。

初始已知缺口：声音/音量、三窗口皮肤、扑克等宽、完整原站卡槽UI、动态附属效果、完整工具箱布局、部分地形规则；现有45项测试和smoke不足以证明全部按钮一致。

2026-10-20 本轮进展：
- 用户再次强调右侧布阵器工具箱为主要功能区；六标签及每个控件均纳入验收，不仅左侧画布。
- 领域旧套件714项与旧UI420预设项通过；它们不代表完整原站一致性。真实原站UI点击发现特效协议假设错误，正在修正并以新fixture重测。
- 新版设置53项通过，真实macOS音频harness确认背景音乐0/25/50/75/100音量与循环/暂停；种植音效仍缺源素材。
- 补齐地图下载原站3张1400x600 PNG，26/26下载资源映射核对完毕；修复下载时List强转Map导致失败。
- 工具箱410x640，桌面1224x640，原版卡片50高密排；6个直接镜像创建按钮及917像素扑克等宽导出/镜像快照；独立9项批量铲除、帮助、卡槽确认、双输入清空、地图设置导航、两个外链实现。最新改动需对应UI重测。
- 原站363名阵左画布与右工具箱全部截图已采集，manifest docs/parity-cases.json；57局部布局继续采集。
- 绘制1930case完成errors0，仅表明可渲染，不能视作像素比较通过。比较器对完整图及单对象分别记录严格差异，含ICC规范化前后指标。
- 真正特效协议：0010冰冻、1000魅惑、0001高亮，imitater/dropshadow/black后缀互斥，透明度独立第7字段；源证据/tmp/pvz-parity/effect-combinations.json、effect-dom.json、zombie-effect-dom.json。domain_coverage负责领域修复，render_parity据真实图片修绘制。
- 420预设新版三shard及其它控件实际引擎正在执行；在最终报告区分源码实现、自动UI、原生音频、截图比较、未完成项。

2026-10-20 窗口结构新约束（用户明确要求）：
- 主窗口必须固定尺寸，预留顶部PVZ标题装饰，不允许PVZ页面上下滚动。工具箱是真正独立窗口，其显示隐藏控制必须在PVZ内容外。
- 实现macOS主content810x667（32px存档栏+635px原PVZ框含顶部27px，800x600画布），原生titlebar/toolbar额外预留；工具箱独立NSWindow content410x640，独立FlutterEngine入口toolboxMain。开关放AppKit NSToolbar，工具箱关闭只隐藏。
- Dart WindowBridge双引擎同步；主session唯一持久化与历史，副session :memory: 且persistDraft=false。完整状态带baseFingerprint，过时文档编辑拒绝并回传主状态，不覆盖新改动；仅副窗口菜单请求转发主窗口保存/存档库。
- 新main app xcodebuild成功，open -n已实际运行。CGWindow实测主810x733（含66px native标题工具栏）、toolbox410x672（含32px native标题栏），截图/tmp/pvz-main-window.png、pvz-toolbox-window.png，PVZ顶部装饰完整可见。
- 真实AXPress主原生工具栏按钮：隐藏工具箱→显示工具箱，CG可见窗口由两窗变为仅主窗；不是mock回调。最终跨引擎选卡/换图/布局同步仍待tool/parity_windows.dart真实nativeharness执行。
- 当前分工：root维护main/EditorSession、domain_coverage维护native窗口与资源、full_ui_suite负责bridge和nativeharness、render_parity继续全1992渲染及左右截图比较。先前420单引擎通过证据保留，不冒充新双窗口全量验收。

2026-10-20 双窗口验收/位置修订：
- 真实native QA首轮抓出跨Swift字典键重排使Formation.fingerprint不同，所有操作被冲突检测撤回；新增documentJson跨窗保留序列化顺序，保持既有项目fingerprint语义。
- 发布串行且保留ACK前第二次本地操作；文档过期或readonly明确拒绝，副窗口不创建草稿。
- 第四轮实际双engine QA run1792438800556286-17352，9/9通过，含固定尺寸/标题/不滚动、跨窗选卡种植/换图/布局/style实际资源、快速连续操作、隐藏重显与不竞争草稿。与28个mock原生channel合同通过分开。
- 用户最新修订：开关不再放最顶部原生toolbar，放标题栏与PVZ内容之间。已移除NSToolbar；在现有32px Flutter独立操作栏（PVZ Stack外）放toolbox-visibility-toggle。主content810x667不变，native titlebar额外空间自然预留。新版位置harness改为真实pointer点此开关并断言几何完全在PVZ外，正在重新构建验收。旧native toolbar AX测试仅历史证据，不冒充新位置通过。
- 静态source420名阵/局部截图已全重采，先关闭出生土壤动画，captureMode明确动画验收pending；原瞬态粒子不应永久画进静态PNG。出生动画GrowPlant六帧单独实现/验收，不能由静态通过推断。
- 原站192控件逐项覆盖文档docs/parity-control-coverage.md已生成。仍有seedImitater/音效/原精确布局等剩余，不宣称全1:1。

位置修订后第五轮真实QA：run1792438928138366-18012，固定尺寸/标题/开关在0..32且PVZ top32、选卡/换图/布局/style/rapid7项通过；剩余2项因为OS应用后台时无新frame超时（失败图已画出正确retain输入），未标通过。新增原生activateWindow正常焦点接口；harness真实pointer前激活目标窗口，且仅有scheduledFrame/pendingPaint时等帧，避免无意义空frame等待。正在第六轮重新执行，不改断言。

2026-10-20 开关位置最终验收：
- run1792439144231947-19030实际双FlutterEngine 9/9通过，主窗口content810x667、frame810x699；无NSToolbar，32px Flutter操作栏位于系统标题栏下/PVZ框上。固定布局、滚轮、跨窗编辑、隐藏重显保持状态通过。
- root额外实际AX关闭工具箱、CG确认隐藏，再用系统pointer点击操作栏显示工具箱，确认独立窗口恢复；截图/tmp/pvz-window-final-main.png。最新生产app已build/open。
- 全量UI最终755/755通过（初跑752+3复测，原失败保留），证据/tmp/pvz-parity-native-stage-summary.json；这不等于原站像素1:1已全部通过。1995渲染无错误，469参考像素比较仍进行，剩余卡槽/出生音效等继续按原范围处理。

2026-10-20 存档库窗口与设计修订：
- 用户要求存档库不能替换PVZ主内容，并重新设计。macOS新增独立可调整大小NSWindow 1040x720（最小860x600）、第三FlutterEngine libraryMain，主编辑器/工具箱继续保留；关闭仅隐藏，重复打开刷新。
- LibraryBrowser全新三栏设计：分类/收藏/草稿计数、统一搜索和排序、阵型缩略图列表、详情大预览、备注标签及明确的只读打开/继续编辑；保留收藏、复制、元信息、版本恢复、导出和删除。
- 仅点击打开才向主编辑器请求切换；先保存活动草稿，再按ID从数据库读最新内容，归档保持只读。新空白草稿显式持久化后才跨engine打开；当前草稿重命名/删除保护；主窗口有对话框时拒绝切换，防止pop错误路由。
- 主production xcodebuild成功，实际系统pointer点击主窗口存档库，CG证实main810x699/toolbox410x672/library1040x752三独立窗口同时存在。截图/tmp/pvz-library-production.png、/tmp/pvz-library-main-preserved.png，窗口证据/tmp/pvz-library-production-windows.json。
- 真实headless UI8/8通过，两尺寸无layout错误；SQLite测试13/13通过。实际三engine专用harness第一轮旧Element引用导致脚本点击失败，原报告保留，已修脚本重跑；不得冒充原生切换已全通过。
- 当前目录仍非Git仓库，无法按milestone提交，且无已确认远程。

存档库原生复测最终结果：run1792440689890310-27005，4/4通过，无Flutter错误。前轮另发现并实际修复旧route延迟dispose断开新WindowBridge问题：等待route.completed再创建下一编辑器。四项覆盖独立窗口保留主画布、archive只读切换+真实toolbox同步、关闭重开保留engine、新建空白草稿持久化+真实toolbox同步。证据/tmp/pvz-library-native/report.json，初轮失败保留各run文件夹。相关Dart分析无问题。

2026-10-20 紧凑存档库与预制名阵阶段：
- 用户要求缩小UI，增加预制名阵+自己的存档，内置也有缩略图并可按场地筛选/全部。
- 独立窗口默认900x600、最小800x540；三列更紧凑，分类保留文字（窄窗口使用图标提示），列表按需构建缩略图。
- LibraryPresets.all包含原站363完整名阵，稳定original-index ID、lazy不可变Formation，浏览不写库。原局部炮位/无炮布局不是完整名阵，仍在原工具箱中，不当完整预制阵型伪装。
- 预制名阵/我的存档/收藏/工作草稿分区；场地dropdown按真实mapId筛选并可全部，预制只提供加入个人存档，不能删除或修改原件。加入时newId独立快照+来源备注+场地标签，保留main画布。
- 领域3项覆盖全363精确内容、缓存与地图分组；连同13项storage共16/16通过。相关产品分析无问题。真实紧凑UI与复制持久化测试继续，原生新尺寸待最终截图。

2026-10-20 格式、保存、Windows1051新阶段：
- 用户明确默认导出PvZToolkit，可选网页格式；导入均自动识别；原地编辑/另存为；Windows显示实际游戏与存档，写入内存前备份可撤销。版本已明确先做原版1.0.0.1051。
- ToolkitCodec按RFC1437独立实现：六地图/48植物/分层支持/睡眠/模仿者/钉耙；严格Base64与压缩边界/Adler32/网格位校验。Piece.asleep可选true序列化不破坏既有false指纹。协议主来源与独立Python黄金向量详docs/toolkit-protocol.md。
- FormationExchange统一自动识别Toolkit、网页、PVZF1、JSON；导出默认Toolkit，可选网页或完整JSON。文本仅布阵，显式说明忽略阳光/选卡/显示元数据，Toolkit还归一动画帧与原站像素偏移；真正不支持对象仍明确拒绝，项目JSON完全保留。原站睡眠状态未验证则拒绝网页导出。
- 主存档保存更新sourceArchiveId并保留旧版本，另存为强制newId即使内容相同；readonly也可另存副本。文件来源路径+格式当前session关联，保存原文件/另存位置/撤销文件覆盖有独立操作。
- ProjectFiles.pickWithPath与saveWithBackup包含真实选择路径与备份路径；桌面所有覆盖先写完整原文件和CRC32manifest，再原子替换；恢复也先备份当前文件，支持redo。macOS三个engine共享新filepanel接口。
- Windows新增GameBridge/native1051识别、读取当前组成/阳光/睡眠、发现实际userdata存档文件、同场地生存无尽普通植物构造函数应用。Windows-onlyLibrary游戏面板提供现场预览/编辑/另存Toolkit/加入存档/文件备份另存恢复/应用与撤销。
- GameBackups先持久CRC校验快照才准native写；版本/场地/进程保护，撤销也备份当前，可列出同进程历史。修复切换游戏后误用另进程备份风险。
- 原生代码重读备份后实际组成以拒绝竞争更改；入口磁盘/远程PE一致性检查、主循环阻断/恢复验证、远程代码超时保留资源直到线程结束，不把写入当跨进程原子事务。独立review修复PE重复读取游标错位及恢复失败锁定。细节docs/game-integration/windows-1051.md。
- 验证：相关pureDart最终57/57；文件存档真实Flutter流程7/7（仅文件选择通道mock）；游戏面板5/5（fake game channel，非游戏实测）；GameBackups真实文件系统+注入适配器9/9；便携C++ PE/x86 ABI测试通过。紧凑library10/10，最新真实macOS三engine run1792442366165176-35389四项4/4通过，主窗口保留、900x600独立库、只读切换/toolbox同步、关闭重开、新空白draft持久化。
- 未执行且不能标通过：Windows原生编译（本机无Windows SDK/MinGW）、真实1051进程读取/应用/撤销、真实Toolkit程序互导。内存写入当前明确拒绝模仿者、道具、白天蘑菇、睡眠、跨场地、我是僵尸等，未清空即拒绝。代码接入不能当全对象或Windows实机验收完成。
- 主production最新macOS build/open最后执行中；无Git仓库/确认remote，无法commit/push。

最终补充：新原生run1792442535822901-36253，5/5通过，新增来源文件路径/格式跨library/main引擎传递，保持实际导入文件原位保存能力；先前瞬态窗口未可见判定失败保留旧run，测试改为等待真实native visible而非350ms固定延迟。所有相关Dart静态分析最终无问题。用户工作流docs/formation-workflow.md，Windows实机限制继续保留。

交付运行证据：最终production lib/main.dart xcodebuild exit0；open -n实际运行pid36558，主窗口CG18410与工具箱CG18415，主frame810x699。系统pointer实际切到载入导出，截图/tmp/pvz-final-transfer.png确认默认PvZToolkit选择和自动识别输入提示。相关QA进程30752/35389/36253已正常terminate（走保存握手），保留其它既有用户实例。

2026-10-20 用户进一步精简交互（明确覆盖原站控件）：
- 场地类型不再使用下拉，改为直接ChoiceChip标签，包含全部和各场地数量；按当前预制/个人/收藏/草稿类别计数，紧凑窗口自动换行。
- 原始未编辑空阵图不写草稿。去掉跨engine打开前强行持久化空白的逻辑，kind=new携带内存文档/来源文件链接，主editor首次真正编辑才保存；非空导入内容保留，编辑过再清空仍保存同一草稿。此前“空白新建立即保存”验收被用户新要求替代，不能继续当目标。
- 当前阵型码实时只读展示，跟随document与exportFormat，包括primary/secondary接收状态；去掉获取、清空输出、双向清空以及获取PVZF1按钮，兼容PVZF1输入仍保留。仅保留复制；不支持当前格式时清除旧码、显示简短原因并禁用复制，恢复有效内容即自动恢复。
- 工具箱底部“搜索卡片”展开项移除；存档库搜索保留。对应旧search.card与transfer等case按新用户要求改写，不再要求与原站这些按钮1:1。
- 标签真实UI10/10与空白draft3/3已通过；live输出及最新native同步验收继续。此前新blank native6case run1792442987434033-38393全部通过，此run早于live输出更改，不能冒充live输出通过。

2026-10-20 浏览器式标签页与复制策略：
- 固定主内容区增至810×695，为28px标签条预留位置，native frame810×727；标题、标签条/工具控制和PVZ画布各占独立空间。存档库依旧独立900×600窗口。
- 个人存档和草稿提供当前/新标签打开；每页独立EditorSession与undo，切换前提交手势并保存；相同草稿重复打开切换已有页，最后一页关闭生成不持久化的原始空页。
- 主工具箱状态和主窗口动作携带session/epoch documentToken，切换后拒绝旧工具箱消息，即使两份空图指纹相同。原生文件对话框和存档保存期间阻止标签切换。
- 复制字符串和工具箱实时输出均固定PvZToolkit，去掉网页复制与输出格式切换；文件导出仍按先前授权可选网页/完整JSON。
- focused真实Flutter：tabs controller12/12，Workspace5/5，live output6/6，Library10/10（其中剪贴板模拟）；实际原生三engine标签页/系统剪贴板验收另行记录。
- Windows进程/内存入口仅Platform.isWindows展示；离线PC存档提取不需要Windows，允许各平台显示。实验性schema提取器20相关用例通过，但没有真实1051存档验收，详docs/game-save-import.md。

原生标签页验收run1792444015089039-43763：4/4通过，实际三engine/临时SQLite/系统剪贴板无模拟；mainContent810×695、frame810×727不可resize，library900×600独立；当前/新页打开、真实tab点击与工具箱码同步、系统Toolkit复制、关最后页后空白不落库、旧空页token消息拒绝。报告/tmp/pvz-tabs-native/report.json。

2026-10-20 后续筛选交互覆盖：
- 用户要求存档“筛选”独立弹框，类似电商筛选；场地+炮数分组暂存，确认应用，重置只改待选条件，取消不改列表。原inline方案停止作为验收目标。
- 零炮统一称“无炮”；炮数名称和匹配阵型数量需用独立视觉元素区分，避免两个数字混淆。
- 离线PC导入真实Flutter harness已收录tool/game_save_import_smoke.dart，交付文件重编译重跑8项通过（仅原生文件选择mock、schema合成fixture；真实1051仍notRun）。
- 生产已成功build并open pid44144/mainCG18495/library18503；当前运行是inline旧筛选版本，需在modal完成后再次更新，不可当最终弹框证据。

Modal最终产品验证：lib/main.dart production xcodebuild exit0，open新pid45157，实际mainCG18511、toolbox18516、library18517。系统pointer打开独立库并点击筛选，截图/tmp/pvz-latest-filter-dialog.png已人工检查：分组标题/无炮/独立N阵徽标/匹配N个阵型/固定重置取消确定均可见，没有inline面板覆盖列表。旧root生产44144已匹配bundle路径正常terminate，其他既有实例未动。相关产品和交付离线导入harness analyzer无问题。Modal行为及两尺寸自动测试等待最终报告。

独立筛选弹框首轮12/12真实Flutter检查通过（含两尺寸无Flutter错误）；首轮支持零计数选择随后被最新用户覆盖：0阵选项全部隐藏，只有全部/重置保留，全部0时不展示0阵徽标。Nativeagent保留pre-hide-zero报告，针对最新规则单独focused验证，不重复无关成功用例。截图须包含Navigator Overlay；旧仅home RepaintBoundary截图不能当Dialog截图证据。

最新零匹配隐藏验收最终6/6真实Flutter通过：场地/炮数交集和独立阵型数量、暂存重置/取消保留、空结果全部/重置恢复、真实cob计数的无炮、900×600与800×540完整Navigator Overlay截图无错误。报告/tmp/pvz-library-filter-dialog-report.json，截图/tmp/pvz-library-filter-dialog-900.png与-800.png，已视检800。生产最新xcodebuild exit0/open pid45811；此次工具侧测试未改产品，不需再build。旧modal12pass/旧inline失败记录保留，不充作最终规则。
最新用户提出工具箱与存档库冗余及互斥共用窗口的设计问题；当前阶段给出设计建议，尚未实施窗口融合。

2026-10-20 用户授权共用侧栏与完成既有功能：
- 方案：macOS一个独立NSWindow，40px原生工具箱/存档库切换条；保留两个Flutterengine/VC，仅切换视图，减少窗口数量而保留浏览/工具状态。主窗口合并入口为显示/隐藏侧栏，仍在PVZ内容之外。
- 内容尺寸：主810×695固定；工具箱410×640、库800×600(min800×540)，额外40px头不侵占Flutter。屏幕够宽时并排，必要只移动主窗口位置；窄于主810+gap8+库800时库退浮动模式，主尺寸不变，诊断明确floating。
- 通道：initialize配置dataPath/activeDraftId，selectSidebarMode/setSidebarVisible/configureSidebar；sidebarStateChanged{visible,mode}是总体可见状态，旧toolboxVisibilityChanged只表示工具箱实际可见，Dart用protocol标志避免旧false覆写。
- 原生openEditor成功自动回工具箱；关闭侧栏只隐藏，同window/engine可恢复。跨平台原生独立侧栏此前仅macOS实现，Windows/Linux仍用共同的Flutter嵌入fallback，不把macOS验收冒充Windows通过。fallback也改单ClassicWindow/模式切换，常驻LibraryPage借用repo、当前/新tab打开回工具；隐藏库时排除焦点，保留输入值。
- 当前production /tmp/pvz-macos-sidebar lib/main.dart build exit0，尚未打开；真实新sharedsidewindow QA、最新fallback QA、755经典UI回归执行中。

最新用户覆盖侧栏宽度：存档库必须参考工具箱宽度，两个模式统一410×640 Flutter内容+40px原生切换头，侧窗固定不resize，切换尺寸不变。Browser<=500改横向分类+搜索筛选+紧凑缩略图列表，点选进入同区域详情/返回保留浏览状态；宽版旧UI仍兼容历史测试。旧宽库native4pass已保留/tmp/pvz-sidebar-native-wide-report.json，不用来冒充窄版通过。
原功能回归：695pure领域通过，755经典UI全执行，初始753pass/2旧asset缺失保留，最新资源focused两款皮肤recheck pass后latest755pass；781组每组full/toolbox/desktop截图存在且尺寸核验，无漏case/重复。编译基线为融合前经典控制，不冒充新壳体验收。详docs/parity-regression.md。
取得原站完整main.js公开正文153964bytes（/tmp/pvz-source-main.js，SHA256c29371c0bd70a06027e3e021e85f5e874079f1e946813169cead0bdc04613254），补历史缺口：3种种植声public原素材，source确定land随机plant1/2、水plant_water；土壤6帧0,100,200,300,400,500ms，650ms清除，cSoil仅限制图片不限制声音。新增seedchooser组件及主入口，包括40基础模仿者、索引移除安全和ROCK关闭；这两路尚等focused最新验收，不能套用原755pass。

最终窄侧栏验收阶段：
- /tmp/pvz-sidebar-native/report.json run1792445471542264-52195四组4/4通过，实际CG18575单侧窗两mode、双方Flutter410×640/整窗410×712，7次可信CLI按原生segmentrect真指针，主810×695不变，current/newtab自动toolbox、系统ToolkitClipboard和新filter/filehandoff通过。原宽版report另存，不混标。
- 410纯库5/5真实Flutter通过，列表详情返回保留scroll/query、current/new/copy、filtermodal适配、预制精确复制、导入文件路径传递。/tmp/pvz-library-narrow-report.json，list/detail截图已人工看无overflow。
- 410 fallback实际10/10通过，含隐藏搜索失焦+真实平台键流CtrlZ、current/new回工具箱、blank不落库。旧直接HardwareKeyboard注入绕过FocusManager导致假失败保留；改用平台onKeyData后pass，未为测试猜测添加产品fix。/tmp/pvz-sidebar-fallback-report.json。
- Seed组件8真实pointer组+主接线focused3/3通过；source40基础灰卡素材全部本地，seedbar按source首x89+51i及缺图fallback，7000像素renderer检查通过，非原站整幅像素一致证明。
- 原生音效 /tmp/pvz-planting-native-report.json实际AVAudioPlayer三源play=true/.5音量、水格真实指针选water、静音false通过；纯headlessfeedback4/4通过。独立review修复初载音源race，新增delayedsource2/2通过 /tmp/pvz-planting-audio-race-report.json；不重复无关native四组。
- Source地形review发现非标准水图反馈错误，新增OriginalTerrain仅用于反馈，不改地图元数据/种植规则；全部26原始矩阵、custom与边界29puretests通过。Root已接音画water参数与terrain0guard，专项额外pointer检查执行中。

最终交付运行：lib/main.dart production xcodebuild -derivedDataPath /tmp/pvz-macos-sidebar exit0，实际open pid54605，主CG18594/共享侧栏CG18599。旧root生产45811匹配路径正常terminate，其余旧用户实例未动。真实header指针切库、真实filter指针打开弹框，/tmp/pvz-final-shared-sidebar.png、/tmp/pvz-final-shared-filter.png、/tmp/pvz-final-shared-main.png已人工检查：同410px宽、横向分类/列表/独立filter、0匹配项隐藏、炮数/阵型徽标分开、主侧栏toggle在PVZ外。
最终地形集成focused1组10次actualboardpointer通过 /tmp/pvz-planting-feedback-report.json 和 /tmp/pvz-planting-terrain-observations.json；旧feedback4pass保留before-terrain报告。全产品相关Dart analyzer clean，新增OriginalTerrain29purepass、audio初始化race2pass。
本轮功能/窄库/共享侧栏/选卡/反馈实现与相关回归已完成；仍未完成的真实Windows编译/1051实机与真实.dat、469原站严格像素差异、隐藏DIYTime动态内容保留在feature-parity.md，不能以自动功能测试当原站全像素或跨平台通过。无Git仓库/已确认远程，无法提交推送。

2026-10-20 主窗口双按钮控制最新覆盖：
- 用户明确将工具箱/存档库切换入口移到主窗口PVZ内容上方，显示mode按钮高亮，再点隐藏，另一按钮切换并显示；两个都未选中代表隐藏。侧栏完全移除40px原生切换条，native内容410×640/frame预期410×672；主810×695保持。
- 主按钮keys main-sidebar-toolbox/library，Semantics selected同步visible&&mode。串行处理点击，保留隐藏mode；侧栏close事件同步取消主按钮选中，库打开后自动toolbox仍保留。
- 用户可见“网页布阵器”统一改为“布阵器”。fallback也移除模式条，由主bar控制；ClassicWindow标题按mode变化，内容640不变。若侧栏有未完成原生file sheet，主切换请求明确拒绝并保持原mode，避免视图切换破坏文件选择。
- Swift/Dart实现已完成，最新原生与fallback专项在跑；上轮带header报告保留，不冒充无header通过。无Git仓库与remote，仍无法提交/推送。

最新无header主bar控制专项4/4实际native通过run1792446887213756-59222：同CG18638、content410×640/frame410×672，主bar各Semantics.selected与真实visible/mode同步、互斥/再点隐藏/另一模式显示、close channel取消高亮、input/query/archives/current-new/Clipboard保留。close为channel路径验证，不冒充物理X点击；带header4pass独立保留。
用户随后要求窗口title已有模式名，内容中去掉重复标题；主按钮选中态也需优化。已移除native toolbox内ClassicWindow标题，仅AppKittitle保留；LibraryPage/Browser增加showTitle用于独立host及fallback，动作行保留、重复库title隐藏。主bar使用26px图标+浅绿底#dceade/深绿#315e45/细边框/6px圆角，不再用经典黄底。新的UI专项进行中，不把前4pass套用视觉修改。

主bar交互fallback最新11/11真实Flutter通过，含串行快速双点与跨mode点击、Semantics互斥高亮、隐藏双不亮/原mode恢复以及既有浏览/标签流程；该run视觉编译早于title隐藏/浅绿样式，但状态机相同。
内容标题去重独立3/3通过，410/800 host下hide generic库title/grass、实际新建/导入/刷新可用；standalone默认title保留。最新全lib Dart analyze No issues found。生产build lib/main.dart exit0，最新chrome实际native单组验收执行中，未更新运行中的旧production，等QA结束再open最终。

最终新chrome单组native通过 /tmp/pvz-sidebar-chrome/report.json (60929)：工具箱首tabY3、无Flutter重复标题、主按钮26px/浅绿fill与选中语义、库showTitlefalse且refresh实际pointer通过，FlutterError0。首轮harness在首帧rootElement为空导致的库timeout另存initial-harness-failure；修等待后pass，产品未因此修改。
最终production lib/main.dart xcodebuild exit0并open pid61240，主CG18682+同侧窗CG18687，sideframe410×672/main810×727。真实主bar指针点击库、等待真实库surface后截图/tmp/pvz-final-main-controls.png、/tmp/pvz-final-toolbox-titleless.png、/tmp/pvz-final-library-titleless.png人工检查通过：按钮绿底选中、互斥库替换工具箱、只有native窗口标题、无多余模式条/重复heading。全lib analyze Noissues。旧用户其他app实例未处理；当前路径无Git/确认远程，无法提交推送。

补充：随后尝试再截库高亮的主窗时，系统返回could not create image from window，未生成该额外图片，不作证据；已有最终主按钮图和真实库surface图有效，且已视检。

2026-10-20 存档工作流新阶段（进行中，覆盖旧空白策略）：
- 用户最新要求所有创建后未保存的阵型进入草稿，包括未编辑空白；保存成功从草稿移出，之后编辑再次进入草稿。旧“空白不落库”验收仅为历史证据，不再作为当前预期。
- 新文档/复制/另存为使用不重复名称，新建阵型、 新建阵型 (2)…；普通保存保持当前存档ID/名称，不创建副本。首次保存明确“保存”，对话框名称成功同步标签与后续原位保存。
- 预制模板补齐当前/新标签使用、Toolkit复制、预览、收藏、导出、加入我的，不允许编辑原始模板。模板收藏新增独立preset_preferences表增量v3迁移，新旧18存储测试通过；UI动作实现静态分析通过，主工作流接线与实际操作测试尚在进行。
- 并行所有权：library_native负责main.dart与工作流测试；render_parity负责repository/session/tabs及相关存储测试；library_design负责browser与独立菜单测试。root负责集成复核、最终构建/启动及记录。此目录及maxdepth2无Git元数据，不能提交/推送。

最新最终用户规则覆盖上述阶段草稿策略：
- 完全移除草稿作为用户功能；新建即自动归档，默认唯一名称可改，每次编辑命令独立保存并保留历史，支持原位回退且回退前head也保留历史。旧draft通过v4事务无损迁入独立个人存档，不覆盖原存档。主流程与并发冲突专项仍待最终汇总。
- 个人库单个/多选/全部导出；批量.pvzlib.json保留完整项目、名称/备注/标签/收藏及可表达的Toolkit码，单个仍默认Toolkit。批量与单项导入比较完整Formation fingerprint，同内容跳过、同名异内容用全角（2）递增；报告导入/跳过/重命名。单文件上限8MiB，超过提示分批。
- 默认导出目录在设置修改，系统文稿为初始默认；系统保存面板仍可改位置，成功保存后记住目录。macOS NSPasteboard PNG+TIFF支持复制完整1600×1200阵图，菜单支持复制/导出图片与Toolkit复制。
- 用户最新侧栏等高：主内容810×695、侧栏410×695/nativeframe727；fallback对应ClassicWindow额外title29。旧640高度报告仅历史证据。
- root已验证bundle纯测试5/5，storage/preferences/bundle组合23/23，真实Flutter batch导入6条检查pass（2导入2跳过2重命名/再次导入全跳过/无效后条目零写入/metadata保留），专用bridge32/32mock合同通过，不冒充原生窗口。
- root原生media专项build通过，实际AppSupport目录设置写入/清除/恢复原值，PNG1600×1200渲染约1MiB、NSPasteboard写入，独立Swift实际读PNG/TIFF1600×1200；/tmp/pvz-export-media-native.json和/tmp/pvz-archive-share.png(人工视检)。系统保存/目录选择sheet未实际操控，不能当OS对话框点选验收。已请求正常terminate仅专用QA PID74697/75055。
- Browser真实Flutter窄410专项5/5（模板九动作回调、个人rename/history、批量选择/全部/取消、无草稿）、设置Dialog1/1通过且零FlutterError；菜单回调证据不冒充主流程图片/导出实际落盘。全lib analyzer目前Noissues，最终生产构建/跨engine验收尚待。

本阶段最终验收补充（原生跨engine仍在进行）：
- 无草稿session10组/标签12项/空白自动存档3项，以及迁移/存储/偏好/bundle26纯测试通过。每command不可变snapshot历史、失败有序重试、optimistic冲突保护、恢复baseline与旧draft无损迁移有独立证据docs/auto-archive-session.md。
- 主流程真实Flutter10/10通过/tmp/pvz-document-workflow-report.json：模板current/new/copy/export/preview/favorite、原位save/rename/history、SaveAs唯一新ID、实际历史选择回退后继续保存、singleimport去重、自动新建archive。旧8/9的同source多tab假设与旧harness失败另存，不冒充最终10pass。
- fallback最终采用与左PVZ内容窗口同635px外高且top对齐（没有额外724px被680pxStack裁切），native仍main/side内容同695px；原始724暂定值已废弃。
- review修复：主库rename/history主窗口false响应不得提示成功；导出后偏好写入FS/插件失败非致命；selection明确全选当前结果并提示筛选外已选项，真实410 focused1pass。

最终交付验收与启动（当前最新规则）：
- 发现WebsiteCodec每次导入重新生成Piece.id，旧fingerprint去重漏判；统一ArchiveBundle.importFingerprint仅忽略对象本地ID，保留所有内容属性与对象顺序，main与batch一致。纯新增身份回归通过，Website随机ID重复导入focused实际Flutter通过，Project basename/同名异内容全角后缀一起通过。
- 补v4迟到旧engine草稿迁移：任何支持版本启动若有draft行都事务迁移，重复内容复用已有映射，异内容独立保留，不改已有archive及history；最终storage/preferences/migration/bundle29/29通过/tmp/pvz-final-storage.log。
- Root旧fileIO专项因旧“只有1档”断言失败，更新为自动存档基数+新版另存为按钮预期后7/7通过/tmp/pvz-final-fileio.log，旧报告另存before-autoarchive，未用产品改动迎合测试。
- NativeQA真实三engine canonical名称/自动save同步1pass；历史链原报告1pass1fail保留，后来源码确认选择器遍历隐藏IndexedStack详情同key，不能标回退nativepass。Root随后生产可信CLI真实点击列表菜单、复制图片出现成功提示、打开历史版本与回退Dialog成功，截图/tmp/pvz-final-library-menu-actual.png与/tmp/pvz-final-native-history-dialog.png已视检。选择的是新空白无历史，不修改用户存档、不冒充执行原生回退；实际回退+继续编辑已在headless10组通过。
- 最终production xcodebuild lib/main.dart exit0，最新kernel晚于main文件mtime；覆盖所有落盘修复。已正常退出旧生产61240/77748并open最新pid78881，主CG18849框810×727、侧CG18854框410×727，同top112/content同695；旧数据按v4无损迁入。主保存已保存状态、用户草稿分类不再出现、共享侧栏高度与主对齐。
- 最终全lib analyzer Noissues；最新生产图片/tmp/pvz-final-workspace-main.png、toolbox.png、library.png（均相同前缀），首次library截图为engine初始化黑帧，待重截视检；旧production已视检Settings/批量导出/预制/我的/收藏及无草稿正确。默认目录真实持久化与PNG/TIFF系统Clipboard已在独立native专项通过；未操作OS保存/选目录sheet，Windows/Linux实机未验收。
- 无Git仓库/已确认remote，不能commit或push；原站严格469像素差异/隐藏动态内容、真实Windows1051/.dat等既有未完成边界继续保留，不宣称全1:1验收。

最终library初始化完成后已重新截图并视检/tmp/pvz-final-workspace-library.png：我的12项、自动名称新建阵型（2）、无草稿、批量选择/导出全部、设置入口均正常；初次黑帧不作最终证据。当前production78881保持运行。
