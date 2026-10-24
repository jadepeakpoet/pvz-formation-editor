# 桌面窗口桥接

Windows 和 macOS 通过 `pvz_formation_editor/windows` 方法通道协调主画面与侧窗。主编辑器维护权威文档，侧窗发送编辑命令并接收最新状态。

| 操作 | 通道方法 |
| --- | --- |
| 主窗口初始化 | `initialize` |
| 侧窗就绪握手 | `ready` |
| 发布文档与选项 | `publishState` / `receiveState` |
| 侧窗请求编辑 | `editState` / `applyToolboxState` |
| 显示侧窗 | `setToolboxVisible` |
| 侧窗请求主动作 | `mainAction` |
| 停用当前文档 | `deactivate` |

共享侧窗切换存档仓库与工具页签，保持界面状态。通道使用状态序号和生命周期检查协调异步消息，主窗口的正常关闭流程等待文档保存后退出。

实现位于 `lib/platform/window_bridge.dart` 及 Windows/macOS 原生 runner；测试入口包括 `tool/window_bridge_smoke.dart` 与原生窗口测试工具。
