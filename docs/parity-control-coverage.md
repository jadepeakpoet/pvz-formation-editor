# 原站控件逐项覆盖审查

> 此表为早期控件审查快照，部分“未实现”已由后续阶段补齐。当前实现与实测请优先查看 [功能状态](feature-parity.md)、[本轮回归](parity-regression.md) 和 [任务记录](parity/ledger.md)，不能直接将本表旧状态当作最终结果。

审查基线：`docs/parity/original-controls.json` 中 101 个 controls 和 91 个 imageControls；逐项检查当前 `lib/main.dart` 与 `tool/parity_ui.dart`。本审查不修改产品代码。

状态含义：`covered` = 当前UI harness为该入口编写了实际事件和相关断言，不代表已通过源站逐像素验收；`exposed` = 可操作但功能不符/断言只检查表层；`notExposed` = 原入口缺失；`implemented-but-unverified` = 实现存在，当前测试无法验证真实系统结果。旧 `/tmp/pvz-parity-ui/report.json` 缺当前大部分case且来自旧版本，不能据其pass宣称此版通过。

## 当前独立审查结论

1. rWindow1–3现已真正用于PVZ左窗原始背景图（window1为808×632，window2/3为806×630，natural size，board固定x3/y27/800×600）。原harness仅断言radio选中，尚未断言实际背景资源、尺寸或每款截图；从“未实现”改为“implemented-but-unverified”。
2. 清空现已具有真实AlertDialog和取消/确认分支；`board.clear`新用例检查取消不修改、确认清空及dialog截图。该新用例尚不能用旧420执行结果证明已跑。文案当前“确定要铲除全部植物吗？”与源“确定清空场上所有植物和道具？”有差异，后续应核对源混合格语义。
3. 背景音乐已有 `/tmp/pvz-audio-results.json` 的真实AVAudioPlayer 0/25/50/75/100及暂停循环验证，不能扩大为新双engine音频同步已通过。种植音效仍明确missingAsset，五档radio可选不等于能播放。
4. seed chooser独立“模仿者”卡片入口（imageControls I90）仍缺失，不能用图鉴模仿效果I0代替。Let’s ROCK真实选卡提交/返回结果尚缺源交互证据；源handler触发B58[0]，当前Flutter去tab2，harness只检查离开seed页，不足以判断完整行为一致。
5. shovel源为独立10项，batch源为独立9项。Flutter已拆独立batch下拉，但single下拉仍含最上层/全部植物/特效等扩展项；harness遍历实现的ObjectFilter而非源10项固定清单，未断言源项标签、默认值、彼此独立性。类别导航目前测试“植物/僵尸/物品/特效”等实现标签，未逐一验证原站“植物选卡/僵尸选卡/物品效果选卡/DIYTime！”精确入口与切换后的可见状态。
6. 用户已另行授权PVZ与工具箱为独立原生窗口，因此这种结构不再作为“原站同DOM布局”缺陷。但旧单engine420次执行、600领域测试都不能替代新双engine全量执行；主/副同步、生命周期、原生关闭再开、native toolbar位置及文件sheet需新native验收。
7. 外链当前主suite仅mock验证目标URL，没有native浏览器导航结果；DIYTime/动态iframe仍无实现。

## 101 个 controls（源 index 保持不变）

| index | 原站 ID/标签 | 状态 | 当前 case ID | main 入口 | 具体边界/偏差 |
| ---: | --- | --- | --- | --- | --- |
| 0 | 卡槽选卡 | covered | tab.卡槽选卡 | classicTab / classicContents | 只验证六tab路由；内容完整性另按下列控件验收，不能视作像素1:1 |
| 1 | 懒人布局 | covered | tab.懒人布局 | classicTab / classicContents | 只验证六tab路由；内容完整性另按下列控件验收，不能视作像素1:1 |
| 2 | 图鉴选卡 | covered | tab.图鉴选卡 | classicTab / classicContents | 只验证六tab路由；内容完整性另按下列控件验收，不能视作像素1:1 |
| 3 | 镜像窗口 | covered | tab.镜像窗口 | classicTab / classicContents | 只验证六tab路由；内容完整性另按下列控件验收，不能视作像素1:1 |
| 4 | 载入导出 | covered | tab.载入导出 | classicTab / classicContents | 只验证六tab路由；内容完整性另按下列控件验收，不能视作像素1:1 |
| 5 | 选项设置 | covered | tab.选项设置 | classicTab / classicContents | 只验证六tab路由；内容完整性另按下列控件验收，不能视作像素1:1 |
| 6 | rHowGrow0 | covered | card.new-selection-clears-old-object | classicContents / tool=选择 | 按钮替代原radio；新卡片/选中对象测试覆盖交互 |
| 7 | rHowGrow1 | covered | batch.选定格子指定植物 | classicContents / tool=批选 | 原站有行列checkbox，Flutter用棋盘cells，不是相同布局或选择入口 |
| 8 | rSingleClear | covered | shovel.<ObjectFilter.options> | shovelFilter dropdown | 现默认全部已修复；仍有原站10项以外扩展项，source精确标签/项数/与batch独立性未断言 |
| 9 | dShovel | covered | shovel.<filter> | tool=铲除 / board tap | 实际点击后检查删除目标 |
| 10 | 全都不要给我清空 | covered | board.clear | classicContents / AlertDialog / original-clear-confirm/cancel | 新用例检查取消保持fingerprint、确认清空；待新版执行，不沿用旧420；提示文案与源不同 |
| 11 | 更换地图 | covered | original.change-map | original-change-map | 切选项设置 |
| 12 | 陆路 | covered | quick.陆路 | quickSelect / cells.clear | 仅默认泳池有源坐标证据；其他26图未逐图取证快捷选择 |
| 13 | 水路 | covered | quick.水路 | quickSelect / cells.clear | 仅默认泳池有源坐标证据；其他26图未逐图取证快捷选择 |
| 14 | 后置炮 | covered | quick.后置炮 | quickSelect / cells.clear | 仅默认泳池有源坐标证据；其他26图未逐图取证快捷选择 |
| 15 | 前置炮 | covered | quick.前置炮 | quickSelect / cells.clear | 仅默认泳池有源坐标证据；其他26图未逐图取证快捷选择 |
| 16 | 超前置炮 | covered | quick.超前置炮 | quickSelect / cells.clear | 仅默认泳池有源坐标证据；其他26图未逐图取证快捷选择 |
| 17 | 底线炮 | covered | quick.底线炮 | quickSelect / cells.clear | 仅默认泳池有源坐标证据；其他26图未逐图取证快捷选择 |
| 18 | 水路前场 | covered | quick.水路前场 | quickSelect / cells.clear | 仅默认泳池有源坐标证据；其他26图未逐图取证快捷选择 |
| 19 | 水路56列 | covered | quick.水路56列 | quickSelect / cells.clear | 仅默认泳池有源坐标证据；其他26图未逐图取证快捷选择 |
| 20 | 重置批量选择 | covered | quick.重置批量选择 | quickSelect / cells.clear | 仅默认泳池有源坐标证据；其他26图未逐图取证快捷选择 |
| 21 | rBatchClear | covered | batch-filter.<filter> | original-rBatchClear | 9类别逐一删除有用例；未断言源原标签、默认项以及single设置不影响batch |
| 22 | 选定格子指定植物 | covered | batch-filter.<filter>; batch.选定格子指定植物 | batchDelete(batchShovelFilter) |  |
| 23 | 选定格子所有植物 | covered | batch.选定格子所有植物 | batchDelete(植物) | 源Clear()是否包含Prop/Zombie需独立源混合格取证，当前用例单pea不能证明 |
| 24 | 全都不要给我清空 | covered | board.clear | classicContents / AlertDialog / original-clear-confirm/cancel | 新用例检查取消保持fingerprint、确认清空；待新版执行，不沿用旧420；提示文案与源不同 |
| 25 | 植物选卡 | covered | category.植物 | category tabs | 测试实现分类标签；原站选卡类别精确label导航/物品效果合并状态未逐项断言 |
| 26 | 僵尸选卡 | covered | category.僵尸 | category tabs | 测试实现分类标签；原站选卡类别精确label导航/物品效果合并状态未逐项断言 |
| 27 | 物品效果选卡 | covered | category.物品 | category tabs | 测试实现分类标签；原站选卡类别精确label导航/物品效果合并状态未逐项断言 |
| 28 | DIYTime！ | notExposed | — | — | DIYTime分类未复刻 |
| 29 | sGrowSelect | covered | grow-mode.0..7 | original-sGrowSelect | 随机策略仅南瓜范围断言；不是所有模板帧的视觉验收 |
| 30 | rSide0 | notExposed | flip.左右翻转; flip.上下翻转（等价部分） | plantingFlip / plantingVertical | 原站4个正反组合radio本身不存在；只有两个独立翻转按钮 |
| 31 | rSide1 | notExposed | flip.左右翻转; flip.上下翻转（等价部分） | plantingFlip / plantingVertical | 原站4个正反组合radio本身不存在；只有两个独立翻转按钮 |
| 32 | rSide2 | notExposed | flip.左右翻转; flip.上下翻转（等价部分） | plantingFlip / plantingVertical | 原站4个正反组合radio本身不存在；只有两个独立翻转按钮 |
| 33 | rSide3 | notExposed | flip.左右翻转; flip.上下翻转（等价部分） | plantingFlip / plantingVertical | 原站4个正反组合radio本身不存在；只有两个独立翻转按钮 |
| 34 | cSideX | covered | flip.左右翻转 | plantingFlip / plantingVertical | 覆盖单开/恢复；四组合源截图另行验收 |
| 35 | cSideY | covered | flip.上下翻转 | plantingFlip / plantingVertical | 覆盖单开/恢复；四组合源截图另行验收 |
| 36 | sResize | implemented-but-unverified | — | properties() selected scale Slider | sResize原站种植前缩放select无直接入口；现属性slider仅选中对象缩放，不等价 |
| 37 | 打开DIYTime来获取动态的僵尸和植物形象 | notExposed | — | — | 动态植物/僵尸DIY iframe未实现 |
| 38 | lMap | covered | map.<mapId>; map.policy.keep/reset | original-lMap | 26图可选择；本地额外custom不属于原站 |
| 39 | imgBack | covered | map-download.<mapId>; original.imgBack | original-imgBack | 内存files mock验证原文件bytes/可解码；不等于原生保存对话框验收 |
| 40 | 换地图且重置植物 | covered | map.policy.reset | original-btnMap-reset |  |
| 41 | 仅换地图不换植物 | covered | map.policy.keep | original-btnMap-keep | 本地过滤越界对象，原站实际跨图坐标保留规则需逐图对照 |
| 42 | cMusic0 | implemented-but-unverified | original.cMusic0 | originalVolume / OriginalAudio.setMusicVolume | 独立audio真实AVAudioPlayer各档播放/暂停已有pass；新双engine共享音频及UI同步尚未执行 |
| 43 | cMusic1 | implemented-but-unverified | original.cMusic1 | originalVolume / OriginalAudio.setMusicVolume | 独立audio真实AVAudioPlayer各档播放/暂停已有pass；新双engine共享音频及UI同步尚未执行 |
| 44 | cMusic2 | implemented-but-unverified | original.cMusic2 | originalVolume / OriginalAudio.setMusicVolume | 独立audio真实AVAudioPlayer各档播放/暂停已有pass；新双engine共享音频及UI同步尚未执行 |
| 45 | cMusic3 | implemented-but-unverified | original.cMusic3 | originalVolume / OriginalAudio.setMusicVolume | 独立audio真实AVAudioPlayer各档播放/暂停已有pass；新双engine共享音频及UI同步尚未执行 |
| 46 | cMusic4 | implemented-but-unverified | original.cMusic4 | originalVolume / OriginalAudio.setMusicVolume | 独立audio真实AVAudioPlayer各档播放/暂停已有pass；新双engine共享音频及UI同步尚未执行 |
| 47 | cAudio0 | exposed | original.cAudio0 | originalVolume / OriginalAudio.setSoundVolume | 缺原站种植音效素材，soundStatus=missingAsset。radio可选不等于能播放，不计功能通过 |
| 48 | cAudio1 | exposed | original.cAudio1 | originalVolume / OriginalAudio.setSoundVolume | 缺原站种植音效素材，soundStatus=missingAsset。radio可选不等于能播放，不计功能通过 |
| 49 | cAudio2 | exposed | original.cAudio2 | originalVolume / OriginalAudio.setSoundVolume | 缺原站种植音效素材，soundStatus=missingAsset。radio可选不等于能播放，不计功能通过 |
| 50 | cAudio3 | exposed | original.cAudio3 | originalVolume / OriginalAudio.setSoundVolume | 缺原站种植音效素材，soundStatus=missingAsset。radio可选不等于能播放，不计功能通过 |
| 51 | cAudio4 | exposed | original.cAudio4 | originalVolume / OriginalAudio.setSoundVolume | 缺原站种植音效素材，soundStatus=missingAsset。radio可选不等于能播放，不计功能通过 |
| 52 | lFog | covered | fog.0..10 | original-lFog | 已写列数/UI用例；视觉运动/遮罩是否相符看截图矩阵 |
| 53 | cSoil | covered | display.泥土 | original-cSoil | toggle+document检查；不替代每图视觉差异验收 |
| 54 | rSeed | covered | display.卡槽 | original-rSeed | toggle+document检查；不替代每图视觉差异验收 |
| 55 | tSun | covered | sun.valid; sun.invalid; sun.nonnumeric; sun.negative | original-tSun / original-bSun | 原站parseInt接受数字前缀，Flutter仅整数字符串，输入语义有差异 |
| 56 | bSun | covered | sun.valid; sun.invalid; sun.nonnumeric; sun.negative | original-tSun / original-bSun | 原站parseInt接受数字前缀，Flutter仅整数字符串，输入语义有差异 |
| 57 | rClear | covered | display.小推车 | original-rClear | toggle+document检查；不替代每图视觉差异验收 |
| 58 | rBrain | covered | display.脑子 | original-rBrain | toggle+document检查；不替代每图视觉差异验收 |
| 59 | rCtc | covered | display.继续标识 | original-rCtc | toggle+document检查；不替代每图视觉差异验收 |
| 60 | rWindow1 | implemented-but-unverified | original.rWindow1 | original-rWindow radio / original-window-background-1..3 Image | 现已应用真实原PNG到左PVZ窗口；harness仍只检查radio，不验证实际图/自然尺寸/源截图 |
| 61 | rWindow2 | implemented-but-unverified | original.rWindow2 | original-rWindow radio / original-window-background-1..3 Image | 现已应用真实原PNG到左PVZ窗口；harness仍只检查radio，不验证实际图/自然尺寸/源截图 |
| 62 | rWindow3 | implemented-but-unverified | original.rWindow3 | original-rWindow radio / original-window-background-1..3 Image | 现已应用真实原PNG到左PVZ窗口；harness仍只检查radio，不验证实际图/自然尺寸/源截图 |
| 63 | cMirrorBack | covered | original.cMirrorBack; mirror.export | exportBackground / mirrorBackgrounds | 可检查镜像继承背景和PNG alpha；files仍mock |
| 64 | cPokerBack | covered | original.cPokerBack; mirror.export.poker | pokerWidth / mirrorPokerWidths | 镜像尺寸/PNG尺寸检查 |
| 65 | 植吧扑克 | implemented-but-unverified | link.poker.镜像窗口 | ProjectFiles.openExternal | URL协议mock验证，未执行native导航 |
| 66 | 创建一个1/1比例的镜像窗口 | covered | mirror.create.0 | original-clone-0 | 六倍率创建，另有snapshot/limit/export；拖动仍需独立交互验证 |
| 67 | 创建一个3/4比例的镜像窗口 | covered | mirror.create.1 | original-clone-1 | 六倍率创建，另有snapshot/limit/export；拖动仍需独立交互验证 |
| 68 | 创建一个2/3比例的镜像窗口 | covered | mirror.create.2 | original-clone-2 | 六倍率创建，另有snapshot/limit/export；拖动仍需独立交互验证 |
| 69 | 创建一个1/2比例的镜像窗口 | covered | mirror.create.3 | original-clone-3 | 六倍率创建，另有snapshot/limit/export；拖动仍需独立交互验证 |
| 70 | 创建一个3/2比例的镜像窗口 | covered | mirror.create.4 | original-clone-4 | 六倍率创建，另有snapshot/limit/export；拖动仍需独立交互验证 |
| 71 | 创建一个2/1比例的镜像窗口 | covered | mirror.create.5 | original-clone-5 | 六倍率创建，另有snapshot/limit/export；拖动仍需独立交互验证 |
| 72 | PvZ Toolkit | implemented-but-unverified | link.toolkit.载入导出 | ProjectFiles.openExternal | URL协议mock验证，未执行native导航 |
| 73 | tLoad | covered | transfer.roundtrip; transfer.invalid | inputFormation / outputFormation / WebsiteCodec | source扩展格式需真实source fixtures，非仅自编码往返 |
| 74 | 载入 | covered | transfer.roundtrip; transfer.invalid | inputFormation / outputFormation / WebsiteCodec | source扩展格式需真实source fixtures，非仅自编码往返 |
| 75 | tSave | covered | transfer.roundtrip; transfer.invalid | inputFormation / outputFormation / WebsiteCodec | source扩展格式需真实source fixtures，非仅自编码往返 |
| 76 | 获取 | covered | transfer.roundtrip; transfer.invalid | inputFormation / outputFormation / WebsiteCodec | source扩展格式需真实source fixtures，非仅自编码往返 |
| 77 | 清空 | covered | original.transfer-clear | original-transfer-clear | 同时清空两个controller |
| 78 | sOutput | covered | export.<png/poker>.<ratio>.<background> | exportRatio | 原站sOutput倍率集合须对照源选项，不以存在dropdown等同 |
| 79 | 生成图片 | covered | export.<png/poker>.<ratio>.<background> | 导出 PNG 图片 / exportPng | 真实图片解码/尺寸/角alpha，保存平台mock |
| 80 | ? | covered | original.help | original-help | 帮助文本+dialog开关；URL参数直接载阵功能本身未验证 |
| 81 | sPoker | covered | preset.formation.0..362 | OriginalCatalog.formations dropdown | 全部选择+保留地图应用 |
| 82 | 查看下一个阵 | covered | preset.button.查看下一个阵 | classicContents preset buttons | next用例只检查非空，未验证363尾部回0 |
| 83 | 布阵且更换相应地图 | covered | preset.button.布阵且更换相应地图 | classicContents preset buttons | next用例只检查非空，未验证363尾部回0 |
| 84 | 布阵但保留当前地图 | covered | preset.button.布阵但保留当前地图 | classicContents preset buttons | next用例只检查非空，未验证363尾部回0 |
| 85 | sCobcannon | covered | preset.cob.0..35 | OriginalCatalog.cobLayouts dropdown |  |
| 86 | 局部布局 | covered | preset.cob.0..35 | 局部布局 / applyPartial |  |
| 87 | sGloomshroom | covered | preset.gloom.0..20 | OriginalCatalog.gloomLayouts dropdown |  |
| 88 | 局部布局 | covered | preset.gloom.0..20 | 局部布局 / applyPartial |  |
| 89 | 花盆 | covered | action.花盆 | OriginalActions.apply | 补容器/梯/破南瓜有断言，碾花盆炸荷叶当前按source保存no-op；动态视觉需另验 |
| 90 | 荷叶 | covered | action.荷叶 | OriginalActions.apply | 补容器/梯/破南瓜有断言，碾花盆炸荷叶当前按source保存no-op；动态视觉需另验 |
| 91 | 搭梯 | covered | action.搭梯 | OriginalActions.apply | 补容器/梯/破南瓜有断言，碾花盆炸荷叶当前按source保存no-op；动态视觉需另验 |
| 92 | 碾花盆 | covered | action.碾花盆 | OriginalActions.apply | 补容器/梯/破南瓜有断言，碾花盆炸荷叶当前按source保存no-op；动态视觉需另验 |
| 93 | 炸荷叶 | covered | action.炸荷叶 | OriginalActions.apply | 补容器/梯/破南瓜有断言，碾花盆炸荷叶当前按source保存no-op；动态视觉需另验 |
| 94 | 破南瓜 | covered | action.破南瓜 | OriginalActions.apply | 补容器/梯/破南瓜有断言，碾花盆炸荷叶当前按source保存no-op；动态视觉需另验 |
| 95 | 南瓜 | covered | imitate.南瓜 | OriginalActions.imitate | UI用例仅any目标变色，精确范围由domain测试覆盖 |
| 96 | 荷叶 | covered | imitate.荷叶 | OriginalActions.imitate | UI用例仅any目标变色，精确范围由domain测试覆盖 |
| 97 | 花盆 | covered | imitate.花盆 | OriginalActions.imitate | UI用例仅any目标变色，精确范围由domain测试覆盖 |
| 98 | 非紫卡植物 | covered | imitate.非紫卡植物 | OriginalActions.imitate | UI用例仅any目标变色，精确范围由domain测试覆盖 |
| 99 | 全部植物 | covered | imitate.全部植物 | OriginalActions.imitate | UI用例仅any目标变色，精确范围由domain测试覆盖 |
| 100 | Let's ROCK! | exposed | original.lets-rock | original-lets-rock | source handler触发B58[0]，Flutter切tab2；真实选卡提交意义待源操作取证，用例仅离开seed不足以覆盖 |

## 91 个 imageControls（以数组下标 I 为审查 ID）

| I | 原站 ID/tag | 图片 | 状态 | 当前 case ID | main 入口 / 边界 |
| ---: | --- | --- | --- | --- | --- |
| 0 | iImitater | image/Card/Imitater.png | covered | effect.模仿者 | classicContents effect按钮；true source effect fixture/截图另验，toggle不能替代真实协议验证 |
| 1 | iFrozen | image/Card/Frozen.png | covered | effect.冰冻 | classicContents effect按钮；true source effect fixture/截图另验，toggle不能替代真实协议验证 |
| 2 | iCharm | image/Card/Charm.png | covered | effect.魅惑 | classicContents effect按钮；true source effect fixture/截图另验，toggle不能替代真实协议验证 |
| 3 | iHighlights | image/Card/Highlights.png | covered | effect.高亮 | classicContents effect按钮；true source effect fixture/截图另验，toggle不能替代真实协议验证 |
| 4 | iIZE | image/Card/Dropshadow.png | covered | effect.阴影 | classicContents effect按钮；true source effect fixture/截图另验，toggle不能替代真实协议验证 |
| 5 | iAshes | image/Card/Ashes.png | covered | effect.灰烬 | classicContents effect按钮；true source effect fixture/截图另验，toggle不能替代真实协议验证 |
| 6 | iTran | image/Card/translucent.png | covered | effect.半透明 | classicContents effect按钮；true source effect fixture/截图另验，toggle不能替代真实协议验证 |
| 7 | Peashooter | image/Card/Peashooter.png | covered | card.pea | classicCard / original-card-pea；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 8 | Sunflower | image/Card/Sunflower.png | covered | card.sunflower | classicCard / original-card-sunflower；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 9 | Cherrybomb | image/Card/Cherrybomb.png | covered | card.cherry | classicCard / original-card-cherry；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 10 | Wallnut | image/Card/Wallnut.png | covered | card.wallnut | classicCard / original-card-wallnut；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 11 | Potatomine | image/Card/Potatomine.png | covered | card.potato | classicCard / original-card-potato；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 12 | Snowpea | image/Card/Snowpea.png | covered | card.snow | classicCard / original-card-snow；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 13 | Chomper | image/Card/Chomper.png | covered | card.chomper | classicCard / original-card-chomper；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 14 | Repeater | image/Card/Repeater.png | covered | card.repeater | classicCard / original-card-repeater；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 15 | Puffshroom | image/Card/Puffshroom.png | covered | card.puff | classicCard / original-card-puff；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 16 | Sunshroom | image/Card/Sunshroom.png | covered | card.sunshroom | classicCard / original-card-sunshroom；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 17 | Fumeshroom | image/Card/Fumeshroom.png | covered | card.fume | classicCard / original-card-fume；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 18 | Gravebuster | image/Card/Gravebuster.png | covered | card.gravebuster | classicCard / original-card-gravebuster；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 19 | Hypnoshroom | image/Card/Hypnoshroom.png | covered | card.hypno | classicCard / original-card-hypno；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 20 | Scaredyshroom | image/Card/Scaredyshroom.png | covered | card.scaredy | classicCard / original-card-scaredy；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 21 | Iceshroom | image/Card/Iceshroom.png | covered | card.ice | classicCard / original-card-ice；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 22 | Doomshroom | image/Card/Doomshroom.png | covered | card.doom | classicCard / original-card-doom；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 23 | Lilypad | image/Card/Lilypad.png | covered | card.lily | classicCard / original-card-lily；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 24 | Squash | image/Card/Squash.png | covered | card.squash | classicCard / original-card-squash；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 25 | Threepeater | image/Card/Threepeater.png | covered | card.threepea | classicCard / original-card-threepea；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 26 | Tanglekelp | image/Card/Tanglekelp.png | covered | card.tangle | classicCard / original-card-tangle；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 27 | Jalapeno | image/Card/Jalapeno.png | covered | card.jalapeno | classicCard / original-card-jalapeno；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 28 | Caltrop | image/Card/Caltrop.png | covered | card.spikeweed | classicCard / original-card-spikeweed；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 29 | Torchwood | image/Card/Torchwood.png | covered | card.torch | classicCard / original-card-torch；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 30 | Tallnut | image/Card/Tallnut.png | covered | card.tallnut | classicCard / original-card-tallnut；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 31 | Seashroom | image/Card/Seashroom.png | covered | card.seashroom | classicCard / original-card-seashroom；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 32 | Plantern | image/Card/Plantern.png | covered | card.plantern | classicCard / original-card-plantern；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 33 | Cactus | image/Card/Cactus.png | covered | card.cactus | classicCard / original-card-cactus；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 34 | Blover | image/Card/Blover.png | covered | card.blover | classicCard / original-card-blover；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 35 | Splitpea | image/Card/Splitpea.png | covered | card.splitpea | classicCard / original-card-splitpea；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 36 | Starfruit | image/Card/Starfruit.png | covered | card.starfruit | classicCard / original-card-starfruit；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 37 | Pumpkin | image/Card/Pumpkin.png | covered | card.pumpkin | classicCard / original-card-pumpkin；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 38 | Magnetshroom | image/Card/Magnetshroom.png | covered | card.magnet | classicCard / original-card-magnet；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 39 | Cabbagepult | image/Card/Cabbagepult.png | covered | card.cabbage | classicCard / original-card-cabbage；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 40 | Pot | image/Card/Pot.png | covered | card.pot | classicCard / original-card-pot；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 41 | Cornpult | image/Card/Cornpult.png | covered | card.kernel | classicCard / original-card-kernel；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 42 | Coffeebean | image/Card/Coffeebean.png | covered | card.coffee | classicCard / original-card-coffee；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 43 | Garlic | image/Card/Garlic.png | covered | card.garlic | classicCard / original-card-garlic；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 44 | Umbrellaleaf | image/Card/Umbrellaleaf.png | covered | card.umbrella | classicCard / original-card-umbrella；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 45 | Marigold | image/Card/Marigold.png | covered | card.marigold | classicCard / original-card-marigold；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 46 | Melonpult | image/Card/Melonpult.png | covered | card.melon | classicCard / original-card-melon；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 47 | Gatlingpea | image/Card/Gatlingpea.png | covered | card.gatling | classicCard / original-card-gatling；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 48 | Twinsunflower | image/Card/Twinsunflower.png | covered | card.doubleSun | classicCard / original-card-doubleSun；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 49 | Gloomshroom | image/Card/Gloomshroom.png | covered | card.gloom | classicCard / original-card-gloom；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 50 | Cattail | image/Card/Cattail.png | covered | card.cattail | classicCard / original-card-cattail；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 51 | Wintermelon | image/Card/Wintermelon.png | covered | card.winter | classicCard / original-card-winter；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 52 | GoldMagnet | image/Card/GoldMagnet.png | covered | card.goldmagnet | classicCard / original-card-goldmagnet；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 53 | Spikerock | image/Card/Spikerock.png | covered | card.spike | classicCard / original-card-spike；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 54 | Cobcannon | image/Card/Cobcannon.png | covered | card.cob | classicCard / original-card-cob；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 55 | Zombie | image/Card/Zombie.png | covered | card.zombie | classicCard / original-card-zombie；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 56 | FlagZombie | image/Card/FlagZombie.png | covered | card.flag | classicCard / original-card-flag；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 57 | ConeheadZombie | image/Card/ConeheadZombie.png | covered | card.cone | classicCard / original-card-cone；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 58 | PoleVaultingZombie | image/Card/PoleVaultingZombie.png | covered | card.pole | classicCard / original-card-pole；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 59 | BucketheadZombie | image/Card/BucketheadZombie.png | covered | card.bucket | classicCard / original-card-bucket；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 60 | NewspaperZombie | image/Card/NewspaperZombie.png | covered | card.newspaper | classicCard / original-card-newspaper；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 61 | ScreenDoorZombie | image/Card/ScreenDoorZombie.png | covered | card.screen | classicCard / original-card-screen；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 62 | FootballZombie | image/Card/FootballZombie.png | covered | card.football | classicCard / original-card-football；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 63 | DancingZombie | image/Card/DancingZombie.png | covered | card.dancer | classicCard / original-card-dancer；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 64 | BackupDancer | image/Card/BackupDancer.png | covered | card.backup | classicCard / original-card-backup；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 65 | DuckyTubeZombie | image/Card/DuckyTubeZombie.png | covered | card.ducky | classicCard / original-card-ducky；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 66 | SnorkelZombie | image/Card/SnorkelZombie.png | covered | card.snorkel | classicCard / original-card-snorkel；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 67 | Zomboni | image/Card/Zomboni.png | covered | card.zomboni | classicCard / original-card-zomboni；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 68 | DolphinRiderZombie | image/Card/DolphinRiderZombie.png | covered | card.dolphin | classicCard / original-card-dolphin；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 69 | JackinTheBoxZombie | image/Card/JackinTheBoxZombie.png | covered | card.jack | classicCard / original-card-jack；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 70 | BalloonZombie | image/Card/BalloonZombie.png | covered | card.balloon | classicCard / original-card-balloon；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 71 | DiggerZombie | image/Card/DiggerZombie.png | covered | card.digger | classicCard / original-card-digger；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 72 | PogoZombie | image/Card/PogoZombie.png | covered | card.pogo | classicCard / original-card-pogo；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 73 | ZombieYeti | image/Card/ZombieYeti.png | covered | card.yeti | classicCard / original-card-yeti；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 74 | BungiZombie | image/Card/BungiZombie.png | covered | card.bungee | classicCard / original-card-bungee；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 75 | LadderZombie | image/Card/LadderZombie.png | covered | card.ladderZombie | classicCard / original-card-ladderZombie；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 76 | Catapult | image/Card/Catapult.png | covered | card.catapult | classicCard / original-card-catapult；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 77 | Gargantuar | image/Card/Gargantuar.png | covered | card.gargantuar | classicCard / original-card-gargantuar；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 78 | Redeyed_Gargantuar | image/Card/Redeyed_Gargantuar.png | covered | card.Redeyed_Gargantuar | classicCard / original-card-Redeyed_Gargantuar；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 79 | Imp | image/Card/Imp.png | covered | card.imp | classicCard / original-card-imp；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 80 | Ladder | image/Card/Ladder.png | covered | card.ladder | classicCard / original-card-ladder；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 81 | Tombstones | image/Card/Tombstone.png | covered | card.grave | classicCard / original-card-grave；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 82 | Rake | image/Card/Rake.png | covered | card.rake | classicCard / original-card-rake；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 83 | Stripe | image/Card/Stripe.png | covered | card.Stripe | classicCard / original-card-Stripe；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 84 | Crater | image/Card/Crater.png | covered | card.crater | classicCard / original-card-crater；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 85 | ScaryPot | image/Card/ScaryPot.png | covered | card.ScaryPot | classicCard / original-card-ScaryPot；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 86 | SnowFlakes | image/Card/SnowFlakes.png | covered | card.SnowFlakes | classicCard / original-card-SnowFlakes；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 87 | BungeeTarget | image/Card/BungeeTarget.png | covered | card.BungeeTarget | classicCard / original-card-BungeeTarget；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 88 | Ice | image/Card/Ice.png | covered | card.Ice | classicCard / original-card-Ice；实际点击卡片落棋盘；外表帧、锚点及截图另验 |
| 89 | canZombie | image/blank.png | notExposed | — | DIY canvas点击种植未实现 |
| 90 | Imitater | image/Card/Imitater.png | notExposed | — | seed chooser模仿者弹窗/目标卡片未实现 |

## 计数与验收边界

controls：{'covered': 78, 'notExposed': 6, 'implemented-but-unverified': 11, 'exposed': 6}。imageControls：{'covered': 89, 'notExposed': 2}。此计数只是逐项映射结果，不是功能通过率。

一个控件下仍可能有多个分支、全部下拉选项、确认取消、失败路径、刷新持久化和每图视觉差异。covered只说明有入口相关测试；上述缺口不能被其他大量地图/预设case稀释。所有源界面截图需按相同操作、相同数据、相同视口比对，尤其seed/DIY、音频、rWindow和清空确认目前不能标OK。

补充：窗口样式源DOM证据 `/tmp/pvz-parity/window-style-dom.json` 已确认window1/2/3背景。此次下载window2/3真实原图806×630（window1为808×632），见 `docs/parity-window-download.md`。样式切换的端到端覆盖仍需绘制像素或Image资源断言，radio本身通过不足。


## 下一轮明确实施与验证清单

- 复刻seed chooser模仿者目标卡流程；取证Let’s ROCK提交前后可见tab、卡槽、已选卡保留，编写提交/取消/重新选卡断言。
- 获得原站种植音效素材后接实际播放；新主副engine分别切音乐音量、共享同一播放器，验证不会重启音乐/互相覆盖。
- 给single/batch下拉稳定不同key，按原站固定10/9标签清单、默认项、每项独立切换及混合对象格源结果验收；分类导航按原label点击并检查显示卡片集合。
- 窗口样式用实际Image asset key/自然尺寸断言，补三款截图对比；保留原生独立结构的新用户要求。
- 执行新版清空确认/取消以及全部对象混合格、只读、撤销恢复；确认提示文案对齐。
- 新双engine全量运行现有case，追加主副状态冲突、canonical落盘、library deactivate、工具箱X隐藏再开、mainAction弹窗前置、文件sheet依附当前窗的真实native验收。
- 未实现DIYTime和动态canvas/iframe应明确保留notExposed，不可在完成声明中略去。
