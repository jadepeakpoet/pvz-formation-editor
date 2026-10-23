# Flutter real-engine parity acceptance

`tool/parity_ui.dart` runs inside the real `flutter_tester` engine, without a VM service or a local test socket. It sends pointer down/up events to laid-out UI elements; offscreen targets are revealed using `Scrollable.ensureVisible`. It does not invoke widget button callbacks as a substitute for clicking.

Each case catches its own errors, records pass/fail, and captures a complete 1240×800 screenshot plus the actual toolbox crop and a 1224×640 desktop crop (board origin minus original board offset 3,27; no scaling). The JSON report is flushed after every case. A failed case therefore cannot hide the remaining coverage. `PVZ_PARITY_OUTPUT` defaults to `/tmp/pvz-parity-ui`; `PVZ_PARITY_FILTER` optionally selects stable case IDs using a regular expression. A filtered run only reports selected cases, and is not evidence of full acceptance.

Volume controls assert both the selected radio and the audio service volume. Headless tests record audio availability separately and do not claim audible playback.

The native file platform and clipboard are replaced with controlled in-memory method-channel handlers. PNG dimensions, saved bytes and clipboard contents are asserted. This validates the Flutter UI-to-platform contract and **does not** validate a native operating-system file panel.

## Run

First build Flutter assets with the installed SDK. Then compile and run, adjusting SDK/engine architecture paths if needed:

```sh
/tmp/pvz-flutter-sdk/bin/cache/dart-sdk/bin/dart /tmp/pvz-flutter-sdk/bin/cache/dart-sdk/bin/snapshots/frontend_server.dart.snapshot --sdk-root /tmp/pvz-flutter-sdk/bin/cache/artifacts/engine/common/flutter_patched_sdk --target=flutter --packages .dart_tool/package_config.json --output-dill /tmp/pvz-parity-ui.dill tool/parity_ui.dart
/tmp/pvz-flutter-sdk/bin/cache/artifacts/engine/darwin-x64/flutter_tester --disable-vm-service --run-forever --enable-software-rendering --flutter-assets-dir=build/flutter_assets /tmp/pvz-parity-ui.dill
```

## Case families

- `tab.*`: six toolbox tabs.
- `map.*`: all 26 maps; selecting alone must not change the document, and the two source apply buttons independently test reset/keep policies. `map-download.*` downloads each staged map and compares its saved filename and bytes with the original map asset.
- `category.*`, `card.*`: every category and each catalog card placed by pointer.
- `preset.formation.*`, `preset.cob.*`, `preset.gloom.*`: every 363/36/21 dropdown option selected and explicitly applied, preserving the map; choosing alone must not change the board.
- `preset.button.*`: full-layout change-map/keep-map/next actions.
- `appearance.manual.*`, `grow-mode.*`, `effect.*`, `flip.*`: appearance selection, seven effect toggles and two flip toggles applied to selected objects.
- `shovel.*`, `quick.*`: all shovel filters and batch selection shortcuts.
- `action.*`, `imitate.*`: six layout and five imitation actions.
- `display.*`, `fog.*`, `sun.*`: all display toggles, eleven fog counts coupled with visibility, and sunshine input that changes the document only when the source apply button is pressed.
- `transfer.*`, `export.png.*`: load/get/copy/clear, malformed input, project and PVZF1 transfer, four PNG scales with/without background.
- `card.capacity-remove`: ten-card capacity and removal.
- `mirror.*`: six scales, background toggle/close, PNG export and three-window limit, and frozen snapshots after a real source clear action.
- `history.*`, `session.*`: undo, redo, actual draft flush/restore, read-only guards.

The source website inventory lives at `docs/parity/original-controls.json`. Screenshots are evidence of the state actually reached, not a claim of pixel equality. Source-site comparison and remaining unmapped original controls must be reviewed before reporting complete 1:1 acceptance.

`original.*` reserves explicit cases for the source volume, skin, download, poker width, help, and Lets ROCK controls. A missing exposed control is reported as `notImplemented`, not omitted or counted as passing.

## Preserved milestone, before native toolbox-window redesign

The user subsequently prioritized a fixed main window with a reserved PVZ title area and a real independent toolbox window. The current harness targets the earlier embedded-toolbox contract. Its evidence remains valid for that contract; it is not acceptance of the new native window structure. Further large runs are paused pending the new window/synchronization test contract.

Completed real-engine evidence under `/tmp`:

| Report directory | Pass | Fail | Not implemented |
| --- | ---: | ---: | ---: |
| `pvz-parity-final-presets-a` | 140 | 0 | 0 |
| `pvz-parity-final-presets-b` | 140 | 0 | 0 |
| `pvz-parity-final-presets-c` | 140 | 0 | 0 |
| `pvz-parity-latest2` | 287 | 0 | 2 |

The 420 preset cases click each dropdown option, explicitly apply it, compare full website-code geometry/frame/effect output, and capture the complete interface plus actual 410×640 toolbox and 1224×640 desktop crops. Combined with `latest2`, these are 709 distinct executed cases: 707 passing and two `notImplemented` observations for help/Lets ROCK in that compiled snapshot. Those buttons were subsequently implemented in production and their new test cases are written, but the updated implementations have not yet been executed by this harness.

The separately preserved `pvz-parity-settings` report has 53 passing cases; `pvz-parity-current2` has 44; `pvz-parity-final-probe` has 20. These overlap the larger runs and must not be added as distinct coverage.

Written changes still requiring execution after the new window contract is settled include independent batch filters, both-string clear, external-link channel requests, updated clear confirmation, 26 original-map downloads with exact bytes/image decode, newly separated opacity protocol checks, filter mutual exclusion, and the subsequent production changes. The later opacity/codec revision is not covered by the preserved 420 UI run. Source map tests exclude the app-only `custom` map because it has no original map asset or original-site index.

Audio observations in the headless run were `music=unsupportedPlatform`, `plantingSound=missingAsset`; audible native playback was not tested. File save/pick, clipboard and external navigation use explicitly declared in-memory platform substitutes. Window-style cases validate radio selection and capture evidence; source visual behavior remains a separate acceptance step.

## Current production snapshot rerun

The full suite was rerun after the native bridge/window changes using four exhaustive shards. Set `PVZ_PARITY_SHARD_COUNT=4` and `PVZ_PARITY_SHARD_INDEX=0..3`; a stable case-ID hash assigns each declared case to exactly one shard. Each report retains the full declared manifest, shard settings and actually executed cases. The completed union equals all **755 declared cases**, including all **420 presets**, with zero missing or duplicate IDs and every case's main screenshot present. Report directories are `/tmp/pvz-parity-native-stage-0` through `-3`.

The initial full execution produced 752 pass/3 fail. One test still expected an obsolete transfer-tab heading; the corrected assertion passed in `/tmp/pvz-parity-native-stage-recheck`. The other two failures were missing `window2.png`/`window3.png` in the stale headless asset bundle, although the source assets and new native bundle contained them. All three window styles passed using the latest real native-build assets in `/tmp/pvz-parity-native-stage-style-recheck`. Original failures remain intact. `/tmp/pvz-parity-native-stage-summary.json` records initial results, recheck provenance and **755/755 latest passing cases**, without claiming the initial run was all green.

These headless tests exercise the current production controls inside the legacy single-engine shell, with explicit file/clipboard/link substitutes. They do not replace the actual two-engine native acceptance recorded in [window-bridge.md](window-bridge.md), and successful state/screenshots alone do not establish pixel equality with every source-site reference.
