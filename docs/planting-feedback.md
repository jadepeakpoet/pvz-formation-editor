# 种植音效与泥土／水花反馈

原始证据：[main.js](http://jspvz.com/ArrayDesign/main.js) 的 `GrowSoil`、`AddSoil`、`ImgSpriter`，以及 [页面地图选项](http://jspvz.com/ArrayDesign/)。公开正文只作为协议与行为参考，没有执行或复制脚本实现。

素材沿用原站公开的 [plant1.mp3](http://jspvz.com/ArrayDesign/audio/plant1.mp3)、[plant2.mp3](http://jspvz.com/ArrayDesign/audio/plant2.mp3)、[plant_water.mp3](http://jspvz.com/ArrayDesign/audio/plant_water.mp3)，放入 `assets/original/audio/`。三个文件 SHA256 分别为：

- plant1：`abbb1224833979da76767d7bece0cbf672704a8655d9b2736f056d99850f52c0`
- plant2：`0515cb527e61e4549022303edc8f7addb8069e37b3f935e29a86ad4d79e37d41`
- plant_water：`9e0e2354429af5c200fb7d9e0d459a786c9bf47ba4eaa2a0afb9e2f8d1ec66ed`

手工种植时陆地随机选 plant1/plant2，水格选 plant_water；Prop 和三种推车不触发，禁用地形没有反馈。关闭“泥土”只隐藏视觉，不关闭种植音效。音量为 0 时不请求播放。三种音源全部配置完成后才能播放，避免首次水格种植抢在水音源初始化之前。

`GrowthEffect` 沿用原始六帧贴图：立即显示第 0 帧，100/200/300/400/500ms 对应后续帧，650ms 删除。计时器只重绘，不进入阵图、自动保存、撤销历史或跨引擎状态。切换地图、标签页和销毁时清理；静态 PNG 导出省略瞬时粒子。同一格在650ms内重复种植会合并为最近一次粒子，仍有别于原站同时创建多个节点。

macOS 原生音频处理器由主窗口、工具箱与存档库引擎共用，每种音源最多三个 `AVAudioPlayer` 声道。实际播放状态、源选择与静音验证见 `/tmp/pvz-planting-native-report.json`；真实 Flutter 指针与生命周期验证见 `/tmp/pvz-planting-feedback-report.json`。这不代表 Windows/Linux 原生音频通过，也不替代人工听感与全部原站动画像素验收。


种植悬停预览同时展示本次种植将自动补上的荷叶或花盆，底座固定在对应逻辑格内，植物继续跟随指针。预览复用实际种植的冲突和补底座规则：现有底座不重复显示，遵守水生植物例外及荷叶／花盆设置；多格植物逐格预览缺失的底座。悬停不修改文档或撤销历史，辅助关闭的导出不包含底座预览。
