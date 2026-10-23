# Windows 原版 1051 游戏接入

实现阶段：原生代码与平台协议已实现；本机为 macOS，尚未完成 Windows 构建、真实进程读取、应用、撤销验收。便携 C++ 检查仅验证指令编码和参数顺序，不能替代真实游戏测试。

## 公开依据

- https://github.com/lmintlcx/pvztoolkit/blob/master/src/pvz.cpp ：版本探测、GetLineup、SetLineup、asm_put_plant、ClearAllPlants。
- https://github.com/lmintlcx/pvztoolkit/blob/master/src/data.cpp ：1051 地址表。
- https://github.com/lmintlcx/pvztoolkit/blob/master/src/toolkit.cpp ：userdata 存档目录位置。

参考仓库仅克隆在 `/tmp/pvztoolkit-reference` 供事实核对。没有把其 GPL 实现文件纳入产品；本模块独立实现 Win32 平台协议、检查、资源生命周期和 x86 指令编码。

## 范围与边界

只读适配 PE32 x86、模块基址 `0x400000`、PE 时间戳 `0x49ecf563` 的原版 1.0.0.1051；其他版本列为未适配，不尝试猜地址。只读需选卡或战斗场景。植物数组每条 `0x14c`，道具每条 `0xec`，容量最大 4096 并校验对象类型与坐标，读取结束复核 Board 指针。

写入目前限定同场地、生存无尽（模式 11 至 15）、最多 512 个普通植物，包含睡莲、花盆、南瓜和咖啡豆。覆盖前后任一方含模仿者、道具、白天蘑菇、睡眠状态，或目标带缩放、透明度、翻转、图像特效则拒绝。不是将整个植物内存结构覆盖过去；调用游戏自己的删除和植物构造函数。主动拒绝跨场地与我是僵尸，避免未适配的场景转换和外观构造。

本模块保存的是布阵组成、位置、阳光、模仿者及睡眠属性；不宣称保存整场游戏的生命、波次、计时器、冷却等即时状态。便携备份服务必须在调用写入前持久保存完整 `snapshot.toJson()`。

## 调用事实

- Lawn 全局指针 `0x6a9ec0`；Board 偏移 `0x768`。
- UI `Lawn+0x7fc`；模式 `Lawn+0x7f8`；帧时长 `Lawn+0x454`。
- 场地 `Board+0x554c`；阳光 `Board+0x5560`。
- 删除植物 `0x4679b0`：栈参数植物指针。
- 创建植物 `0x40d120`：EAX 为行号，栈参数 Board、列、类型、模仿目标（本阶段固定 -1）。调用前依次 push -1、类型、列、Board。
- 主循环阻断位置 `0x552014`：原字节 DB，操作期间暂改 FE；恢复 DB 并复核。

写入前检查上述主循环字节，同时将创建、删除入口各 32 字节与磁盘对应可执行节匹配；磁盘 PE 同样校验时间戳、位数和基址。这是磁盘/运行内存一致性检查，**不是官方 EXE SHA 白名单证明**。不支持运行时入口跳转或补丁的程序。

## 时序与失败处理

1. 调用方读快照并持久备份，传入同一快照为 expectedBefore。
2. 原生重新识别进程、校验代码与内容、模式、场地，暂时阻断游戏主循环。
3. 等待两帧后重读 Board，比较组成、场地、阳光；与备份不一致则拒绝，尚未清除对象。
4. 同一远程调用流先删除、再按底座 / 普通植物 / 南瓜 / 咖啡顺序创建，保留通用寄存器并以 ret 4 返回。
5. 重读并比较目标组成、阳光，再恢复和验证主循环字节。
6. 五秒超时不释放仍在执行的代码、不提前恢复主循环；后台等待线程完成后恢复字节、释放资源。恢复重试三次并检查实际字节和页面保护；无法确认恢复时继续锁定写入并提示重新启动游戏，不能当作成功。期间拒绝再次应用。错误明确提示可能部分应用，调用方保留备份。此操作不宣称跨进程事务原子性。

## 平台协议

通道 `pvz_formation_editor/game`：

- `listGames`：pid/title/executable/version/timestamp/canRead/canWrite。
- `readFormation {pid}`：pid/version/map/sunValue/pieces；植物含 type/row/col/imitater/asleep，道具含 gridType/row/col。
- `applyFormation {pid,target,expectedBefore}`：原生返回 before/after，Dart 返回 after 快照。调用方应先持久保存 expectedBefore，撤销也需重新读取与备份当前阵型再调用相同应用流程。
- `saveFolders {pid}`：返回实际存在的游戏旁 userdata 和 ProgramData 内 PopCap 对应目录。
- `listSaveFiles {pid}`：path/directory/relativePath/size/modifiedAt。最多 4096 文件、目录深度 8，跳过重解析点。

## 已执行与未执行

已执行：Dart 静态分析；`clang++ -std=c++17 -Wall -Wextra -Werror -I windows/runner tool/game_x86_smoke.cpp -o /tmp/pvz-game-x86-test` 与运行，验证 EAX 行参数、栈参数顺序、向前/向后 call 位移、删除调用和 ret 4；另用纯 C++ PE fixture 验证两次检查共享文件句柄仍分别从 DOS 头定位、构造/删除入口 RVA 映射，以及错误版本、架构、非可执行或超界节拒绝。

未执行：Windows 原生编译；真实 1051 检测、读取、应用、备份恢复与撤销；异常线程及权限真实验收。本机没有 MinGW/Windows SDK，macOS 的通过不能标记为 Windows 通过。
