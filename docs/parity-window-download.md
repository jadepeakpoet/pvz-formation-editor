# 原站窗口样式原图

依据 `/tmp/pvz-parity/window-style-dom.json`，原站 rWindow1/2/3 设置左侧 `tWindow` CSS background 为 `image/window1.png` / `window2.png` / `window3.png`。tWindow区域为810×635，board固定在left3/top27处800×600；背景图天然尺寸与区域不应混淆。

本次通过浏览器实际原生图片文档的唯一 `img[src]` 调用 `downloadMedia()` 下载 window2/3，等待明确文件存在后复制到 `assets/original/image/`，无重编码、无拼图。

| 文件 | 来源 | 尺寸 | SHA-256 |
| --- | --- | --- | --- |
| window1.png | http://jspvz.com/ArrayDesign/image/window1.png | 808×632 | 4f52870acef662a6841bcedf6318381bff60b3366cc29f0b579518ae4c2d3671 |
| window2.png | http://jspvz.com/ArrayDesign/image/window2.png | 806×630 | b251c6bfd388006d9fb0b82bf007342dbefa1c4e3f14cfe814c68b0640084519 |
| window3.png | http://jspvz.com/ArrayDesign/image/window3.png | 806×630 | 9fda0a86320bc7706921ef5c41436333c8b7e9f6f80da36040c8843ff6b0efb6 |

window1为此前已有原图，window2/3为此次新增。只完成素材获取，不把原图存在当作样式已绘制或已通过截图对比。
