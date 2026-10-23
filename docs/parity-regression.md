# Classic-function regression audit, 2026-10-20

This audit executed the existing original-function tests without changing production main/native code. The full UI compile was frozen **before** the subsequent toolbox/library sidebar fusion. It covers unchanged classic controls inside the single-engine fallback shell; it does not certify the new sidebar shell. Main source SHA256 at compile baseline: `a15105f10b6935a2b22229e8d7ced3f1a5e7ff14754c3742a725522c9e572fea`. Harness SHA256: `62a34ec84eac4882de727621d08f8e6bad9d1dc86f7127814bba7028832b45db`.

## Executed results

- Domain/storage/backups/layouts/presets/seeds/Website/Toolkit/exchange/experimental-save suites: **695 passing**, zero failures. `dart test` explicitly selected all 12 pure-Dart `*_test.dart` suites; `board_painter_test.dart` requires Flutter and was not passed off as a pure-Dart test. Log: `/tmp/pvz-regression-domain.log`.
- Exhaustive classic UI: **755 declared and executed**, including **420 presets**. Initial execution: 753 pass, two failures because the old headless assets omitted `window2.png` and `window3.png`. Both source images exist. Focused recheck with the latest completed native-build assets passed both. The original failures are preserved, and latest results are **755 pass**. Four shard reports: `/tmp/pvz-regression-ui-{0,1,2,3}/report.json`; recheck: `/tmp/pvz-regression-skin-recheck/report.json`; summary: `/tmp/pvz-regression-ui-summary.json`.
- Screenshot audit: every declared case occurs exactly once; zero missing cases, duplicate IDs, missing PNGs or incorrect dimensions. Initial evidence includes **781 full + 781 toolbox + 781 desktop PNGs** (additional intermediate states explain counts above 755). Full viewport 1240×800, actual toolbox crop 410×640, desktop crop 1224×640. Two focused rechecks have their own six additional images.
- Seven real-engine focused programs completed successfully: `session_smoke`, `empty_draft_smoke` (3), `editor_tabs_smoke` (12), `tabs_workspace_smoke` (5), `live_output_smoke` (6), `formation_io_smoke` (7 reported groups), and `game_save_import_smoke` (8). Session smoke reports behavioral groups rather than a machine case count, so no invented aggregate count is assigned. Logs: `/tmp/pvz-regression-<name>.log`; result list: `/tmp/pvz-regression-focused.json`; copied JSON evidence: `/tmp/pvz-regression-focused-evidence/`.
- Updated `tool/window_bridge_smoke.dart` for the new `initialize` metadata map, `setSidebarVisible`, `selectSidebarMode` and `sidebarStateChanged` contract. Added metadata forwarding, invalid-mode/no-send and late-generation sidebar event tests. **31/31 pass**, analyzer clean. This uses an explicitly simulated native channel, not actual native windows. Evidence: `/tmp/pvz-window-bridge-report.json`, `/tmp/pvz-regression-window-bridge.log`.

## Reproduction

Compile real-engine entry points with the matching Flutter frontend server as documented in `docs/parity-ui.md`. Run `tool/parity_ui.dart` using four disjoint shards (`PVZ_PARITY_SHARD_COUNT=4`, index 0–3). Each process was bounded to 1200 seconds; no timeout occurred. Focused entry points were bounded to 180 seconds each.

Run the delivered evidence verifier:

```sh
python3 tool/parity_regression_report.py /tmp/pvz-regression-ui-0 /tmp/pvz-regression-ui-1 /tmp/pvz-regression-ui-2 /tmp/pvz-regression-ui-3 --recheck /tmp/pvz-regression-skin-recheck --output /tmp/pvz-regression-ui-summary.json
```

The verifier checks manifests, case uniqueness/completeness, actual PNG signatures/dimensions and explicit recheck provenance. It preserves initial failures. It performs no alignment, resizing, pixel tolerance or original-reference comparison.

## Boundaries and remaining acceptance

No native focus/screenshot automation was run in this audit. Native file panels, clipboard, external URLs and bridge transport use declared substitutes. Native sidebar fusion requires its separate latest focused/native acceptance. Windows process read/write, a real 1051 `.dat` fixture, audible sound and full source-site pixel parity are **not run or not established**, never counted as passes here. The known 469-reference strict visual differences from the earlier renderer audit are not erased by these functional results.

Primary-source review found independent missing behavior beyond the existing classic suite: source seed chooser/mimic overlay, plant1/plant2/water sound assets, and 650 ms soil/water birth lifecycle. These are separate implementation/acceptance lanes. Source `ImgSpriter` applies frames at 0,100,200,300,400,500 ms and removes at 650 ms; soil visibility does not gate audio. The standalone seed module has separate evidence and is not implicitly covered by the old 755-case compile.
