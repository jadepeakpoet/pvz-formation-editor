# 原站功能领域层验收

本记录只说明领域逻辑、源字符串和 SQLite 的自动化验证，不能替代 Flutter 点击、绘制、截图及导出图片验收。

2026-10-20 执行 `dart test test/parity_domain_test.dart --reporter json`：600 个命名用例全部通过，无跳过。`dart analyze test/parity_domain_test.dart`：无问题。逐例结果见 `docs/parity-domain-results.json`，每个 ID 对应测试文件中的命名用例。

| ID 前缀 | 数量 | 验证边界 |
| --- | ---: | --- |
| D-MAP | 26 | 原站地图编号、名称映射、项目存取 |
| D-FORMATION | 363 | 每个名阵的每条源对象类型、坐标、外表帧、效果及扩展字段 |
| D-COB / D-GLOOM | 36 / 21 | 每个炮/菇局部布局的全部源对象字段 |
| D-OBJECT | 78 | 48 植物及 30 已支持额外协议类型的位置、帧、水平翻转 |
| D-EFFECT | 14 | 真实 7 单项、4 组合、滤镜覆盖顺序、旧项目与旧像素字段兼容 |
| D-SELECT | 9 | 八种原站真实 checkbox 证据的行列笛卡尔积，全部选择及无效输入 |
| D-ACTION | 6 | 原站真实保存字符串与结果对象、位置、帧行、效果一致 |
| D-IMITATE | 5 | 五种白化范围，精确目标类型集合，保留已有半透明 |
| D-DELETE | 13 | 每种筛选类别的精确删除目标与保留补集 |
| D-FLIP | 4 | 原站四种 canvas side 与实际保存结果，识别垂直信息丢失 |
| D-PERSIST | 8 | 各显示开关、三种卡槽写入 SQLite 并关闭重开后完整恢复 |
| D-CODEC | 17 | 11 种无效/重叠输入拒绝；6 种有损导出拒绝、完整项目保留 |

证据来自已有原站浏览器探测结果，已复制到 `test/fixtures/parity/selection.json`、`actions.json`、`flip.json`。名阵/地图来自 `OriginalCatalog` 的源站捕获；已有 `original_catalog_test.dart` 同时检查打包 JSON 与目录一致性。补花盆/荷叶的随机帧列不应固定到某次随机值，因此比较时仅忽略它们的帧列，并独立验证其合法范围；其他字段均比较。动作比较忽略源对象 DOM 排序和随机实例 ID，不忽略位置、类型、效果和帧行。

## 尚不能据此标为完整 1:1

- `notVerified`：领域测试不覆盖每张地图画面几何、全部对象外表帧截图、声音、镜像视窗、交互及导出 PNG；应由 Flutter 运行及截图矩阵验收。
- `notVerified`：八种快捷选择的源证据只有默认泳池。其他地图的快捷选择虽然有逻辑实现，尚无对应原站点击证据。
- `notVerified`：草稿撤销/重做属于 Flutter `EditorSession`，需要 Flutter 测试执行；本文件只检查真实 SQLite 文档持久化。
- `notImplemented`：原站字符串尚不支持所有 97 个对象模板类型，额外协议 ID 0x5A、0x5C、0x64 等仍未验证，不能把本测试中的 78 种协议类型说成全部模板。
- `protocolLimitation`：原站自己的 Save 表单也丢弃垂直翻转（canvas side=2/3，但保存回 side=0）。本地项目保存可保留；网站格式保守拒绝导出垂直翻转，防止无提示丢失。
- `protocolLimitation`：卡槽、自定义雾列/阳光、缩放的无损源字符串导出仍受限，测试验证的是明确拒绝，而非已实现这些协议字段。

本阶段根据真实 UI 取证修复 Piece.opacity 及 gray 协议；新增测试和证据。工作目录没有 `.git`，无法提交该阶段。


## 真实 UI 证据纠正（替代旧七位假设）

此前 128 个七位效果组合用例仅证明旧实现自洽，不能证明与原站相符，已删除。当前效果期望独立来自原站实际点击 icon + Zombie 卡片 + 棋盘后 Save，及多效果 Peashooter 保存，见 `test/fixtures/parity/effects.json`、`effect-combinations.json`。

| 原站效果 | gray | 第七字段 opacity |
| --- | --- | --- |
| 模仿者 | `1`，有颜色 mask 时后缀 `imitater` | 1 |
| 冰冻 | `0010` | 1 |
| 魅惑 | `1000` | 1 |
| 高亮 | `0001` | 1 |
| 我是僵尸（内部旧名称“阴影”） | `0000dropshadow` | 1 |
| 灰烬 | `0000black` | 1 |
| 半透明 | `0` | 0.5 |

四位中第二位保留，不擅自赋予语义。模仿、dropshadow、black 共用一个滤镜槽，按选择顺序后者覆盖前者；例如 source 全七种依次选择结果是 `1011black 0.5`，不是七位标志。Piece 在构造/修改时规范化互斥滤镜，确保项目 JSON 排序不改变最后生效滤镜。旧 app 项目缺 opacity 字段时根据原有半透明效果迁移到 0.5，否则 1；scale 始终是独立的几何缩放。

当前 600 个领域验收及另外 32 个领域既有测试通过；`dart analyze` 受影响领域代码和测试无问题。不能沿用旧 714 个用例全部通过的数字，当前逐例报告已更新。
