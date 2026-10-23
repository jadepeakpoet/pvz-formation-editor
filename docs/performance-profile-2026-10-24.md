# 性能采样与优化尝试（2026-10-24）

## 范围与环境

以 `e0ea15c` 为优化前源码基线，改动集中在画板几何和铲除命中检测。Apple Silicon macOS，Flutter 3.19.2 / Dart 3.3.0，真实 `flutter_tester` 引擎、Debug JIT、800×600 离屏软件渲染。没有读取或修改用户存档；数据库使用可自动删除的独立临时目录。

本机 Profile 引擎的 `gen_snapshot_arm64` 实际为 x86_64 可执行文件，直接执行 `--version` 返回 `bad CPU type in executable`。本轮是 Debug CPU sampling 和工作负载计时，不是 Flutter Profile/AOT 发布性能、原生 GPU 帧率或真机验收；未安装 Rosetta 或改动系统工具链。

## CPU profile

独立于前后计时，运行优化前已编译的相同基准，启用引擎 `--enable-dart-profiling`，经仅监听本机的 Dart VM Service `getCpuSamples` 取得一次有效快照：18,632 个样本，1,000µs 采样周期，覆盖约 28.05 秒。快照包含初始化、绘制和部分智能命中阶段，不覆盖全部流程。读取范围应覆盖 VM 的单调时钟时间戳，不能假设从零开始的前十几分钟就是本次运行区间。

| 调用链 | Inclusive ticks | 占样本比例 |
| --- | ---: | ---: |
| `ShovelTargets.at` | 7,502 | 40.3% |
| `BoardGeometry.hitPieces` | 5,543 | 29.8% |
| `BoardGeometry.pieceBounds` | 5,274 | 28.3% |
| `BoardGeometry.pieceCenter` | 4,574 | 24.5% |
| List `any` | 3,381 | 18.1% |
| List `indexOf` | 1,611 | 8.6% |

Inclusive 样本有嵌套，不能相加，也不等于函数自身 CPU 时间。结合代码确认：每个植物/南瓜的坐标计算都扫描全部对象找同格花盆；智能铲除还会构造不会使用的格内对象列表，其排序比较器反复 `indexOf`。

采样脚本在目标退出时的最后一次 RPC 遇到连接关闭；上述数据来自此前成功保存的快照，不把失败的末次读取当作完整 profile。原始采样仅保存在临时目录，避免将其中的绝对源码路径、进程信息和本机 VM Service 地址提交入库。

## 改动

- `BoardGeometry` 为绑定的不可变文档延迟创建花盆 `(row, col)` 集合；同一几何对象的绘制和命中检测重复查询复用它。匹配保持精确同格，只有 Plant/Shell 受抬高影响；新文档建立新集合，不维护全局缓存。
- 智能铲除直接执行像素命中，不再进行无用的格内筛选、格子路径命中及排序。分类铲除按逻辑格筛选全部匹配对象，仍保留跨格植物与南瓜附属梯子的处理；返回集合不依赖排序。
- 补充真实引擎回归：泳池/屋顶、花盆与相邻格、植物/南瓜/咖啡豆/梯子的抬高差异、移除花盆后的新文档、跨格分类铲除、南瓜附属梯子及画板外点击。
- 通用 UI smoke 原先查找文字“撤销/恢复”，但现有工具栏已是纯图标；改为真实点击对应图标，保留原有整次拖动撤销/重做断言，不改产品界面。

## 同场景前后对比

使用未修改的 `tool/performance_smoke.dart`，先编译优化前 kernel，再编译优化后 kernel；两个无采样进程依次运行，计时期间不并行构建、测试或运行其他基准。表内绘制场景先预热一次，智能命中按原脚本不单独预热；nearest-rank 中位数。表内80/500/1500 对象场景各 7 个样本，5000 对象场景各 3 个样本。5000 对象是 54 格上的密集叠放压力样本，不代表常规阵型规模。

单位：ms；变化为 `(优化后 / 优化前 - 1)`。

| 场景 | 优化前中位数 | 优化后中位数 | 耗时变化 |
| --- | ---: | ---: | ---: |
| `board.80.record` | 0.916 | 0.979 | +6.9% |
| `board.80.recordAndRaster` | 19.267 | 19.028 | -1.2% |
| `board.500.record` | 1.917 | 1.595 | -16.8% |
| `board.500.recordAndRaster` | 78.257 | 80.100 | +2.4% |
| `board.1500.record` | 4.193 | 2.992 | -28.6% |
| `board.1500.recordAndRaster` | 223.991 | 224.010 | +0.0% |
| `board.5000.record` | 14.422 | 10.899 | -24.4% |
| `board.5000.recordAndRaster` | 724.948 | 728.558 | +0.5% |
| `shovel.5000objects.1000smartHits` | 7496.034 | 2678.678 | -64.3% |

1000 次智能命中从 7,496.034ms 降为 2,678.678ms，约由 7.50ms/次降至 2.68ms/次。5000 对象画指令记录约减少 24%；包含软件栅格化的整体绘制时间没有明显改善。80 对象指令记录略慢、500 对象软件栅格结果略慢，均为单进程一轮的观测，不能据此声称所有场景均加速。当前瓶颈仍包括密集素材的软件栅格化。

两份完整基准状态均 `complete`，最终校验和均为 `775075`。这只是结果一致性的粗检查，不能替代功能/像素测试。SQLite 队列 flush 单样本由 3,685.827ms 变为 4,090.709ms；本次未改动存储，未将此单样本差异归因于优化，也不声称存储有收益。

## 复现与证据

先用当前可写 SDK 执行 `flutter pub get --offline`（缓存齐全时），再构建资源。基准使用已有脚本，无需修改用户偏好：

```sh
flutter build bundle --debug --no-pub
"$FLUTTER_SDK/bin/cache/dart-sdk/bin/dart" \
  "$FLUTTER_SDK/bin/cache/dart-sdk/bin/snapshots/frontend_server.dart.snapshot" \
  --sdk-root "$FLUTTER_SDK/bin/cache/artifacts/engine/common/flutter_patched_sdk" \
  --target=flutter --packages .dart_tool/package_config.json \
  --output-dill /tmp/pvz-performance.dill tool/performance_smoke.dart
PVZ_PERFORMANCE_OUTPUT=/tmp/pvz-performance.json \
  "$FLUTTER_ENGINE_DIR/flutter_tester" --disable-vm-service --run-forever \
  --enable-software-rendering --flutter-assets-dir=build/flutter_assets \
  /tmp/pvz-performance.dill
```

设置 `FLUTTER_SDK` 和 `FLUTTER_ENGINE_DIR` 为实际 SDK 与宿主引擎目录。采样运行另开进程，去掉 `--disable-vm-service`，添加 `--enable-dart-profiling --disable-vm-service-publication`，通过该进程日志中的本机 VM Service 地址读取 CPU 样本；采样运行不作为前后耗时比较值。

本次原始文件（仅本机临时目录）：

- `/tmp/pvz-performance-before-2026-10-24.json` 与同名 `.log`。
- `/tmp/pvz-performance-after-2026-10-24.json` 与同名 `.log`。
- `/tmp/pvz-cpu-before-full.json`、`/tmp/pvz-cpu-before.log`。
- `/tmp/pvz-profile-check.log`、`/tmp/pvz-planting-profile.log`、`/tmp/pvz-ui-profile.log`。

## 回归验证

- `FLUTTER_SDK=/tmp/pvz-flutter-sdk ./tool/check.sh`：资源目录检查、静态分析、56 项 Dart/SQLite 测试、debug bundle 构建、render smoke 与 10 组 session smoke 均通过。首轮通用 UI smoke 为 10/11，通过期间无 FlutterError；唯一失败是旧脚本寻找已经改为纯图标的“撤销”文字。
- 修正两处 UI 脚本的点击目标后，仅重跑 UI 引擎 smoke；11/11 组通过，FlutterError 为 0。
- `tool/planting_support_smoke.dart`：17/17 组通过，含透明像素、翻转/缩放/外表帧、跨行重叠、智能铲除手势及撤销、南瓜附属梯子。
- 没有构建或启动新的 macOS 原生应用，没有做其他平台、GPU 帧率或真机验收。
