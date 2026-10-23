# 原站地图背景资源核对

2026-10-20 核对原站捕获目录 `assets/original_catalog.json` 与 `BoardMap.background`。取原站 option value 第一个逗号前的字段，再按 `||` 分割并选最终项；26 个映射全部精确一致。`custom` 是本地额外地图，不计入原站 26 项。

| 编号 | 地图 ID | 原站最终背景文件 | 当前资源状态 | SHA-256 |
| ---: | --- | --- | --- | --- |
| 0 | pool | `background3.png` | 本次原图下载 | 26950ab17287a28633b9b9f4b9aa428cefb940674d1772024d87adac506686d9 |
| 1 | fog | `background4.png` | 本次原图下载 | 0574781f1765f830642fab8740d671ba5867b204e434d07f5eb218c3dd074def |
| 2 | day | `background1.jpg` | 存在 | 0c3ab5483d2d318433ead223935ac8094c7ac06c065a445bc106c4acf8fe5df1 |
| 3 | night | `background2.jpg` | 存在 | eefca4c5e08823c4feff453efd1089d1226f3ebe8c0b3705057bde880db0f26e |
| 4 | roof | `background5.jpg` | 存在 | 5769edf7b52077600ace6a90591babd22219f0ae9ca9cea7f554b367927a43b4 |
| 5 | moonRoof | `background6boss.jpg` | 存在 | 90726dfd15ab7ca1917e110b3909574a29d6a7b71323d6a94c9b0f1e1f5df61f |
| 6 | day6 | `D6E.jpg` | 存在 | da831bac417a0812272b755835ec479473b10c8238ad4051035b117ef97fec26 |
| 7 | night6 | `N6E.jpg` | 存在 | be47cb1753064c972b020ac85ff2ad6e87f311953895dec7d30a17a34f91b668 |
| 8 | roof6 | `R6E.jpg` | 存在 | 3dedaec82826a0fb96ac0ddacb8faf4eedb75a3513f40c16e48097f60eb62bca |
| 9 | moonRoof6 | `M6E.jpg` | 存在 | 1fa32ee8b0e4ec912aad794bb2327ec445e7bbb2300e298c250f0a331eefab03 |
| 10 | highland | `highland.gif` | 存在 | ff8af1c0ceb52980921dc64a1c1ad8aa8fefe9256290d46995b2e19c4f60ba4b |
| 11 | day3 | `background1unsodded2.jpg` | 存在 | 74505353b2fa9380b1cddd35c61b9c1d9000fe4a312d30519a6a86e108e686f1 |
| 12 | night3 | `N3E.jpg` | 存在 | c4df5062393573fc914415406e471acfdd2a60ba336b216cc36005e08f5e7474 |
| 13 | day1 | `background1unsodded_1.jpg` | 存在 | 9044793cdee192a84cb74307fb4fd65ea7a31bd4be4b693c0ca769ae30df3377 |
| 14 | night1 | `N1E.jpg` | 存在 | 2173514d5e77e280aaf0773bcc5cecfa0624a912cf178f6fb9c3b96f303234b6 |
| 15 | barren | `background1unsodded.jpg` | 存在 | a2b6433be7e2b62f152d7413f05ea58d67fe8d182c0015a824754e9b63d8d286 |
| 16 | barrenNight | `N0E.jpg` | 存在 | dd7118605d21c1b6f556f8308566eef4c48d756e7507814483e2269d8500958b |
| 17 | greenhouse | `Background_Greenhouse.jpg` | 存在 | 6401adf29a2dbc3e19ed9fac77ff0fd587c0b1039b06b2726cf5f35496057b8c |
| 18 | mushroomGarden | `Background_MushroomGarden.jpg` | 存在 | 694def2aa89f658de5c36971eaea0ce1bbdc6393ddd035faa4e76f845f77d147 |
| 19 | aquarium | `aquarium1.jpg` | 存在 | 3145446586ed2222d888ea90f5e9b908e6965d70ab86828e12ffb34a7ea0de02 |
| 20 | allWater | `background7.jpg` | 存在 | 5268d268563deb2efc6ca305750af7337723b2cdefe1c1013c63d63617e9eb52 |
| 21 | flood | `background8.jpg` | 存在 | 9250cabc720383ae9be37a8c8ab35b694729eb0a06d79ca7f8421630a9dfead0 |
| 22 | reversal | `background9.jpg` | 存在 | c4c5ed479d931c081c2bf0423e0686a539847749aa596b1ee8987dfd4f11eced |
| 23 | fogShimmer | `background10.png` | 本次原图下载 | 041f4bd37adaed33280282b4f64dc834b33e36070d98d6742978339448e12246 |
| 24 | mushroomGardenRestricted | `Background_MushroomGarden.jpg` | 存在 | 694def2aa89f658de5c36971eaea0ce1bbdc6393ddd035faa4e76f845f77d147 |
| 25 | greenhouseRestricted | `Background_Greenhouse.jpg` | 存在 | 6401adf29a2dbc3e19ed9fac77ff0fd587c0b1039b06b2726cf5f35496057b8c |

## 来源与获取证据

- 来源统一为 `http://jspvz.com/ArrayDesign/image/<文件名>`，名称来自原站 map option，不从其他地图推测或合成。
- 23 项已存在的资源来自此前原站浏览器下载包；`/tmp/pvz-map-bundles.json` 记录每个地图对应 manifest 路径。比如白天泳池源包 `/var/folders/nt/dg2f94x104qdlly949xn5m4w0000gn/T/browser-use/assets/f1eb361b-c7b5-4ec5-8b1a-10d6d001c4df/manifest.json` 仅包含 `background3.jpg` 与 `background3_.png`，不含最终 `background3.png`。
- 本次补齐的三张最终图为 `background3.png`、`background4.png`、`background10.png`。普通页面实际用 JPG 背景和 `_` PNG 前景，最终 PNG 没有进入已观察到的 pageAssets 库存。不能将前景或拼接结果冒充最终原图。
- Chrome 实际打开 `http://jspvz.com/ArrayDesign/image/background3.png` 时，原生图片文档标题为 `background3.png (1400×600)`，证明该原图存在。该原生图片文档的 pageAssets inventory 为空。
- 子代理命令行 `curl -I --max-time 10 http://jspvz.com/ArrayDesign/image/background3.png` 返回 `Could not resolve host`（受限环境），没有成功下载。不将此记为源站不存在。
- 最终采用浏览器原生图片页面的唯一 `img[src]` 调用 `downloadMedia()`，实际下载到用户 Downloads，再复制到 assets/original/image。三个原生文档标题均确认为 1400×600，下载完成后验证 PNG 文件签名和尺寸，并记录上表 SHA-256。没有重编码、拼图或近似素材。

本次未修改 `main.dart`、地图定义或 `pubspec.yaml`。

最终验证：26/26 原站地图最终背景文件均存在，26/26 BoardMap.background 与原站 option 最终项精确一致。新增文件仅为上述三张原站 PNG。
