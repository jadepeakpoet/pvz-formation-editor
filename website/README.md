# 官网与文档

## 访问统计后台

后台地址：`https://xmpvz.pages.dev/admin/`。参照 MaydayStar，使用 Pages Worker + 独立 D1 数据库，管理员密码登录。公开页面不放后台入口。

生产初始密码仅保存在本机 `website/.admin-password.production`，不在聊天、日志、源代码或网站静态目录中发布。`python website/init_admin.py --reset` 可生成新密码、密码哈希和会话密钥；将 `build/checks/analytics-secrets.json` 通过 `wrangler pages secret bulk ... --project-name xmpvz` 上传后，重新部署生效，同时使旧会话失效。密码与会话 Secret 只存于 Git 忽略文件和 Cloudflare Secret。

统计页面浏览量、按随机浏览器标识去重的访客、会话、每日趋势、来源域名、国家/地区、下载与加群链接点击。下载点击不代表下载完成。报表为北京时间，提供 7/30/90 天筛选，保留最近 400 天。尊重 Do Not Track / Global Privacy Control，不保存原始 IP、URL 查询参数、阵型、账号或表单内容。关闭存储的浏览器使用临时标识，去重可能不准确。预览域名不自动采集；桌面应用不采集。

新数据库不能补记接入前的访问。Cloudflare 原有边缘请求指标或已启用的 Web Analytics 应单独查看，不能作为新后台的真实历史访客导入。

初始化：`wrangler d1 migrations apply xmpvz-analytics --remote --config website/wrangler.jsonc`。
验证：`node website/test-analytics.mjs`（真实 SQLite、认证/签名/来源校验、重复请求去重、跨日 UV、限速、隐私字段、客户端拒绝追踪与存储禁用），以及下述下载测试。

部署须在 `website` 目录运行 `wrangler pages deploy dist --project-name xmpvz --branch main`，让 Wrangler 自动读取当前目录的配置，确保 D1 的 `DB` 绑定保留（Pages deploy 不接受自定义配置路径）。`_routes.json` 只将 `/api/*` 和 ZIP 路径交给 Worker；页面仍由静态资源服务。

先运行 `python tool/package_windows_release.py` 打包完整 Windows Release，再运行 `python website/build.py` 生成 website/dist。官网只提供应用绿色包下载，源码入口统一指向 GitHub；构建脚本不会发布源码压缩包。

运行 `node website/test-download.mjs` 验证完整 ZIP SHA256、跨分段 Range、后缀下载、无效范围和 HEAD。

发布：`wrangler pages deploy website/dist --project-name xmpvz --branch main`。

官网：https://xmpvz.pages.dev，文档：/docs/，下载校验值：/downloads/SHA256SUMS.txt。

Pages 单个静态文件有大小限制。构建脚本将 ZIP 分成 8 MiB 静态片段，由 advanced-mode Worker 流式返回一个普通 ZIP，并支持 Range 续传；用户只需点击下载，无需手动合并。`_routes.json` 仅让 ZIP 下载路径调用 Worker，官网和文档使用静态资源服务。不要将开发目录或用户数据加入 dist。

Worker 的 ASSETS 绑定用法参考：https://developers.cloudflare.com/pages/functions/advanced-mode/。
