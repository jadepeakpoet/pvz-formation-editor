# 素材与图片资源

地图、植物、僵尸、卡片和音效主要参考 [jspvz 网页布阵器](http://jspvz.com/ArrayDesign/)。来源 URL 和本地路径记录在 `assets/original/manifest.json`；地图图层在 `maps.json`，外观帧尺寸与锚点在 `sprites.json`。

## 本地渲染

地图与角色图片由 Canvas 绘制。植物外观以当前帧按需裁切，相同像素内容复用同一缓存项；图鉴卡片、模仿者效果与编辑命中掩码分别管理。

`assets/original/frame_index.json` 记录帧坐标与像素去重索引，`tool/prepare_sprite_index.py` 用于生成元数据。包内只保存原始精灵图，不携带预裁切图片与命中掩码。运行时按需裁切当前外观，批次内共享临时精灵图并在裁切完成后释放；裁切结果使用有容量限制的缓存，命中掩码按需从帧的透明度生成。外观选择器也使用小尺寸运行时帧。

`assets/original/thumbnails` 随包保存 363 张 256×192 WebP 缩略图，合计约 7.49 MiB。`tool/prepare_builtin_thumbnails.dart` 和 `tool/compress_builtin_thumbnails.py` 提供生成流程。自定义阵型缩略图按画面内容生成并缓存到本地。

## 应用图标与权利

应用图标使用 `assets/branding/app-logo.png`，各平台图标与生成说明见 [branding](../assets/branding/README.md)。

植物大战僵尸相关素材的权利属于原权利人；项目源码与素材分别适用各自的许可声明。第三方项目与作者见 [鸣谢](../ACKNOWLEDGMENTS.md)。
