# PC endless-save research and experimental placement import

The [jspvz home page](http://jspvz.com/) links to its [resource page](http://jspvz.com/download.htm). The resource catalog exposes **Win电脑版存档** at [1代PC版游戏存档](http://jspvz.com/ResDownload/1_PC_Save.htm). That page explicitly separates gold/silver profile progress from endless battle saves and instructs users to rename endless files to `game*_13.dat`. It lists 1.0.0.1051 separately from 1.2.0.1065/1073. This is original PC binary save data, not the browser clone's JSON or ArrayDesign text.

## Primary structural evidence

Read-only public sources consulted:

- [SaveGame.cpp](https://github.com/map220v/LawnCPP/blob/pvz_windows-dx8/Lawn/System/SaveGame.cpp): length-prefixed header/board records, v2 FEEDDEAD magic, DataArray serialization order, final magic.
- [Board.h](https://github.com/map220v/LawnCPP/blob/pvz_windows-dx8/Lawn/Board.h): paused-tail origin 0x164, scene 0x554c, sun 0x5560, board extent 0x57b0.
- [Board.cpp](https://github.com/map220v/LawnCPP/blob/pvz_windows-dx8/Lawn/Board.cpp): standard row and grid terrain initialization.
- [Plant.h](https://github.com/map220v/LawnCPP/blob/pvz_windows-dx8/Lawn/Plant.h), [GameObject.h](https://github.com/map220v/LawnCPP/blob/pvz_windows-dx8/Lawn/GameObject.h), [GridItem.h](https://github.com/map220v/LawnCPP/blob/pvz_windows-dx8/Lawn/GridItem.h): seed/grid coordinates, sleeping/imitater/dead/on-board flags, field offsets.
- [DataArray.h](https://github.com/map220v/LawnCPP/blob/pvz_windows-dx8/Sexy.TodLib/DataArray.h): trailing generation/index IDs identify allocated slots.
- [ConstEnums.h](https://github.com/map220v/LawnCPP/blob/pvz_windows-dx8/ConstEnums.h): six standard background indices, original plant indices and grid item kinds.

The primary [Plant.cpp](https://github.com/map220v/LawnCPP/blob/pvz_windows-dx8/Lawn/Plant.cpp) transformation routine confirms that converted imitater plants have a normal seed ID and imitater marker 48; an unconverted seed ID 48 retains its target plant ID instead. Both representations are tested.

The current Windows 1051 process bridge independently uses plant stride 0x14c and grid stride 0xec. The source's compile-date CRC is not treated as a verified 1051 build identifier; the importer returns the file's opaque `buildDate` unchanged and requires the supported record structure instead. No GPL implementation was copied; the extractor is independently written from the serialized field layout.

## Import contract and limits

`GameSaveCodec.decode(List<int>)` returns `GameSaveImport { Formation formation, List<String> warnings, int buildDate }`. It accepts at most 32 MiB and never writes files or attaches to a running game, so offline parsing works on every host platform.

The extractor checks header/version, exact board-tail size, six supported scene/terrain matrices, bounded record lengths and array counts, expected first-six array strides, allocated-slot IDs/counts, boolean fields and placement bounds. It reads 48 plant types, converted/unconverted imitater, sleeping state, sun, graves, craters, ladders and rakes. Unsupported grid objects, plants or modified terrain are rejected explicitly. Freed/dead/squished/off-board plants and dead grid objects are not placements.

This is a **placement extractor**, not a full game-save validator or emulator. Particle/reanimation/trail/attachment arrays are checked for framing/count/slot-ID consistency, but their runtime structures and following animation/cursor/seedbank/challenge/music body are not reconstructed or semantically validated; only a minimum trailing body and terminal magic are required. Wave counts, health, cooldowns, zombies, projectiles, coins, lawnmowers and effects are intentionally omitted and reported in warnings. A filename alone cannot prove the embedded battle was endless: mode is chosen by the original game's file slot, not this serialized board prefix.

## Actual-file acceptance status

The jspvz page's exact [合集 V3.0b download](https://pan.baidu.com/s/1rG3Gx) and [五行缺土 download](https://pan.baidu.com/s/1w0l0H) were fetched as public HTML. Their public listings identify `存档合集V3.0b.rar` (720439 bytes) and `五行缺土.rar` (142677 bytes). No direct archive download URL was exposed in these unauthenticated pages. The resource site's advertised direct mirror forwards to `https://pvz.766788.xyz/ziyuan/`, which returned HTTP 404. Bounded GitHub searches did not locate a public raw 1051 `game1_13.dat` fixture. No downloaded executable was run and no login was attempted.

Tests therefore use explicitly synthetic vectors constructed from the primary schema, not real game captures. Five focused tests cover six scenes, all 48 plant IDs, sleeping/imitater, four grid object kinds, skipped dead objects, unchanged input, malformed headers/sizes/terrain/IDs/flags/coordinates and truncation/size bounds. Actual Windows 1051 file acceptance remains **not run** and the UI must label this import experimental. Source-supported structure tests must not be represented as live-game acceptance.
