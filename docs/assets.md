# 原站素材

2026-10-20，通过原站页面的图片资源导出接口，保存了初始248张图片以及全部26种地图对应的底图、透明叠加层。文件在 `assets/original/image/`，URL和本地路径保留在 `assets/original/manifest.json`；地图配置在 `maps.json`，97个DOM外观模板的帧尺寸和锚点在 `sprites.json`。

来源：<http://jspvz.com/ArrayDesign/>。

地图和角色渲染优先使用本地图片，PNG导出先等待图片解码完成。原站不存在的应用对象仍用程序绘制。图片加载的是指定静态帧，不能据此声称原站全部动态效果已复刻。内置背景音乐和种植音效，使用本地静态音频文件。

2026-10-23：顶部铲子区新增 ShovelBank.png，根据原版游戏素材核对，未修改原图。位置与铲子相对偏移参照 PvZ Portable；资源来源、哈希及使用边界见 [种植覆盖与叠加](planting-rules.md)。
