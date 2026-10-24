# 图片与工作区资源管理

阵图使用 Flutter Canvas。图片加载分为元数据、地图与工具图、植物帧、卡片和列表缩略图。

- 启动读取索引与当前文档需要的资源，植物外观按当前帧解码。
- 相同帧通过像素内容标识复用，同图的多个对象共享资源。
- 外观选择器临时使用对应植物的完整精灵图，关闭后释放。
- 原图与变体使用有容量预算的缓存；并发解码、临时导出及可见图片分别管理。
- 363 张包内 WebP 缩略图为 256×192，合计约 7.49 MiB；列表解码缓存预算为 4 MiB。
- 自定义缩略图按画面内容生成，存为本地文件；列表滚动复用压缩文件和当前可见图片。
- 工作区恢复只读取需要打开的文档，名阵列表通过轻量索引提供筛选与预览。

实现入口：`lib/editor/original_assets.dart`、`image_resources.dart`、`lib/library/thumbnail_store.dart`、`formation_thumbnail.dart` 和 `lib/platform/image_memory.dart`。
