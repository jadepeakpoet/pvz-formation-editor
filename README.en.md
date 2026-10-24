# PVZ Formation Editor

<img src="assets/branding/app-logo.png" width="128" alt="PVZ Formation Editor logo">

[简体中文](README.md) | [English](README.en.md)

**Plants as pieces. Formation as an art.** An offline desktop editor built with Flutter widgets and Canvas.

**v1.0.0** · [Website](https://xmpvz.pages.dev/en/) · [User guide](https://xmpvz.pages.dev/en/docs/) · [Windows x64 portable download](https://xmpvz.pages.dev/downloads/PvZ-Formation-Editor-1.0.0-windows-x64.zip) · [Join QQ group 425175276](https://qm.qq.com/q/BbkV57ELaa)

Author: **越小梦 (yuexiaomeng)** · [Authors](AUTHORS) · [Acknowledgments](ACKNOWLEDGMENTS.md)

The primary reference is [jspvz ArrayDesign](http://jspvz.com/ArrayDesign/) by **LonelyStar (囧丫乙)**. This project adapts its functionality and UI for local use, adding archive management, desktop interaction and live game integration. Technical references: [PvZ Toolkit](https://pvz.lmintlcx.com/toolkit/) by lmintlcx and [PvZ-Portable](https://github.com/wszqkzqk/PvZ-Portable) by wszqkzqk and contributors.

## Windows release

The current published package is **Windows v1.0.0**, built and launched for verification. Other platforms have source projects, but no corresponding release package from this run.

| Item | Details |
| --- | --- |
| App version | 1.0.0 |
| OS / architecture | Windows 10 / Windows 11, x64 |
| Package | Release ZIP, no installation required |
| Executable | `pvz_formation_editor.exe` |
| Runtime | App-local MSVC runtime included; retain all DLL files and the `data` folder |
| Game integration | Original Windows PvZ 1.0.0.1051, Survival Endless modes 11–15 |
| Local data | User application-support folder; moving the ZIP/app folder does not move archives |
| Updating | Quit the previous version normally, extract the new package and run it; export archives before migrating devices |

**[Download Windows v1.0.0 x64](https://xmpvz.pages.dev/downloads/PvZ-Formation-Editor-1.0.0-windows-x64.zip)** · [SHA-256 checksums](https://xmpvz.pages.dev/downloads/SHA256SUMS.txt) · [Windows user guide](https://xmpvz.pages.dev/en/docs/)

This release includes independent windows, improved Windows CJK typography, autosave when opening presets, batch archive import/export, and live-game support for Imitaters, ladders, graves and rakes. See the verification scope below; mods and other game versions are not guaranteed to work.

## Download and features

On Windows 10 / 11 x64, fully extract the ZIP and run `pvz_formation_editor.exe`. Keep the DLL files and `data` folder alongside it. No installation is needed. See [SHA256 checksums](https://xmpvz.pages.dev/downloads/SHA256SUMS.txt). Source code is available in this GitHub repository; the website does not provide source archives.

- Independent main board and sidebar; the Windows main window can be minimized on its own. Main window: 810×695; sidebar: 410×695.
- Sidebar tabs: Archive Library, Layout Presets, Plant Encyclopedia, Mirrors, Load / Export and Settings. The encyclopedia is selected on first use.
- Edit 26 maps with plants, zombies, objects, seed slots, appearance/layers, batch selection/removal, undo/redo and PNG export.
- Browse 363 complete presets and partial layouts; create up to three read-only mirror snapshots.
- Search, tag, batch-select, import, export, deduplicate and inspect archive history. Favorites are temporarily hidden; existing favorite data is retained.
- Default export folder: Documents/PvzFormationEditor. Soil splashes are off by default.
- The app supports Simplified Chinese and English. The website language selector supports Follow system, 简体中文 and English, and remembers your choice.

## Autosave

Edits are saved automatically to local archives. The main toolbar shows autosave status; failed writes are shown explicitly and can be retried.

- Opening a preset in the current or a new tab immediately saves editable work. An identical saved formation is reused to avoid duplicate records.
- A pristine blank page is not archived until an effective edit. Read-only previews do not create archives.
- Subsequent edits update the same archive and preserve earlier versions. Rapid edits, renames, undo and redo use a serialized save queue.
- Reopening restores saved documents. Open tabs retain undo history, but the undo stack does not survive closing or restarting.
- Ctrl/Cmd+S submits a save; Save As creates an independent copy. Exported files are separate copies and must be exported again to update them.

## Live game integration

Currently supported: **original Windows version 1.0.0.1051, Survival Endless modes 11–15**. Start the game and enter a level first.

1. Read from game, above the Load / Export input box, fills the formation code. Load into editor then opens it for editing.
2. Copy the current code or choose Apply to game to replace the in-game layout while preserving the current sun amount.
3. Archive/preset details place Apply to game beside Copy Toolkit code. Each item's More menu provides the same direct action.

Regular plants, Imitaters, sleeping states, graves, ladders, rakes and six scene types are supported. Scaling, flipping, graphical effects, decorative zombies and I, Zombie mode are not supported. Other game versions/mods are not guaranteed to work.

**All 363 presets were attempted against a live game: 360 matched on readback; three containing web-only decorative content were rejected.** The user's 86-object historical formation code also passed a real write/readback check. All apply entry points were checked separately and the original game layout was restored afterward. See the [full validation record](docs/game-integration/all-presets-validation.md) and [Windows notes](docs/game-integration/windows-1051.md).

Injection-history/rollback has been removed. Archive version history and game-save file backups remain available.

## Import, export and data

- PvZ Toolkit and reference-site formation codes preserve the layout their respective formats can represent; unsupported content is reported.
- Complete projects (`*.pvzf.json` / `PVZF1:`) preserve the formation document, object appearance/states and display settings.
- Collections (`*.pvzlib.json`) preserve names, notes, tags and complete formations, but not all version history. Repeated content is skipped; conflicting names with different content are renamed.
- PNG is a static image, not an editable backup.
- Experimental PC Endless save import extracts a formation, not the full battle state, and never replaces the source `.dat` file.

The database is `formations.sqlite` in the user application-support directory (database version 4, document version 1). Portable means no installation, not app-local data storage. Back up the complete database and any companion journal/WAL/SHM files after quitting normally; preserve current data before restoring.

Imports are limited to 8 MiB and 5,000 objects. The entire file is validated before writes; malformed/oversized files and canceled operations leave existing content unchanged. Custom image assets are not supported.

## Development

Recorded baseline: Flutter **3.19.2 stable**, Dart **3.3.0**, dependencies locked in `pubspec.lock`.

```sh
flutter pub get
flutter run -d windows
flutter build windows --release
```

Build on the corresponding host. Windows requires Visual Studio 2022 C++ desktop tools and system `winsqlite3.dll`; macOS/iOS require Xcode and CocoaPods; Android uses JDK 17, the Android SDK and Gradle 7.6.3; Linux requires Flutter GTK dependencies, `libsqlite3.so.0`, `zenity` and CJK fonts.

When replacing a running macOS build, use `swift tool/restart_macos_app.swift <app-bundle-path>` so the previous instance can save and quit normally.

`tool/package_windows_release.py` packages the Windows Release and app-local MSVC runtimes (`--build` and `--crt` override paths). Build the website with `python website/build.py`, and check full downloads/range requests with `node website/test-download.mjs`. See [website deployment notes](website/README.md).

## Verification

```sh
flutter analyze
dart test test/toolkit_codec_test.dart test/archive_bundle_test.dart test/archive_dedup_test.dart test/formation_exchange_test.dart test/file_backups_test.dart test/game_save_codec_test.dart test/website_codec_test.dart
```

Analysis and the 63 tests above passed. Real Flutter engine checks cover file/project/code round trips, collection import/export, deduplication, malformed/oversized/canceled input, autosave and reopening. Windows Release was built and launched; live game acceptance is documented above.

macOS has historical build/launch records but was not rebuilt in this run. Linux/iOS have not received physical-device acceptance; Android packaging was previously blocked by Gradle download connectivity. Platform projects are not a claim of available release binaries. Native dialogs, power loss and all game versions have not been fully validated.

## Source and license

`lib/domain`: documents, validation, layouts and codecs; `lib/editor`: commands, autosave and rendering; `lib/storage`: SQLite and migrations/history; `lib/platform` and native runners: files, windows and game integration; `website`: the website and user guide.

Project source code is licensed under [GNU GPL v3.0](LICENSE). Copyright (C) 2026 越小梦. Game assets and third-party dependencies retain their own rights and license notices; see [Acknowledgments](ACKNOWLEDGMENTS.md) and [asset provenance](docs/assets.md).
