# 官网与文档

先运行 `python tool/package_windows_release.py` 打包完整 Windows Release，再运行 `python website/build.py` 生成 website/dist。官网只提供应用绿色包下载，源码入口统一指向 GitHub；构建脚本不会发布源码压缩包。

运行 `node website/test-download.mjs` 验证完整 ZIP SHA256、跨分段 Range、后缀下载、无效范围和 HEAD。

发布：`wrangler pages deploy website/dist --project-name xmpvz --branch main`。

官网：https://xmpvz.pages.dev，文档：/docs/，下载校验值：/downloads/SHA256SUMS.txt。

Pages 单个静态文件有大小限制。构建脚本将 ZIP 分成 8 MiB 静态片段，由 advanced-mode Worker 流式返回一个普通 ZIP，并支持 Range 续传；用户只需点击下载，无需手动合并。`_routes.json` 仅让 ZIP 下载路径调用 Worker，官网和文档使用静态资源服务。不要将开发目录或用户数据加入 dist。

Worker 的 ASSETS 绑定用法参考：https://developers.cloudflare.com/pages/functions/advanced-mode/。
