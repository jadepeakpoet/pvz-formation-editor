# 图片与工作区资源管理

阵图使用 Flutter Canvas。图片加载分为元数据、地图与工具图、植物帧、卡片和列表缩略图。

- 启动读取索引与当前文档需要的资源，植物外观按当前帧解码。
- 相同帧通过像素内容标识复用，同图的多个对象共享资源。
- 外观选择器按可见格位裁切植物帧，使用小尺寸图片与 Flutter 图片缓存；临时精灵图在裁切完成后释放。
- 切换外观时保留上一完整画面，等待新帧及附加图层齐备后一次切换；临时保留资源随切换结束释放。
- 原图与变体使用有容量预算的缓存；并发解码、临时导出及可见图片分别管理。
- 名阵与自定义存档缩略图首次可见时按画面内容生成，Windows 在独立编码 isolate 中压缩为本地 256×192 WebP，并兼容旧 PNG；列表滚动复用磁盘缓存和当前可见图片，解码缓存预算为 4 MiB。其余平台暂用 PNG。
- 工作区恢复只读取需要打开的文档，名阵列表通过轻量索引提供筛选与预览。

实现入口：`lib/editor/original_assets.dart`、`image_resources.dart`、`lib/library/thumbnail_store.dart`、`formation_thumbnail.dart` 和 `lib/platform/image_memory.dart`。
