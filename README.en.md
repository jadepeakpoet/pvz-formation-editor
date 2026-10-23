# PVZ Formation Editor

[简体中文](README.md) | [English](README.en.md)

Author and maintainer: **yuexiaomeng** · [Authors](AUTHORS) · [Acknowledgments](ACKNOWLEDGMENTS.md)

An offline Plants vs. Zombies formation editor built with Flutter widgets and Canvas. It includes Windows, macOS, Linux, Android and iOS projects. Editing does not require a server, account or access to game memory. The interface supports Simplified Chinese and English; some plant and preset names retain their original names.

## Features

- Place plants, zombies and effects on 26 maps, with appearance and layer controls.
- Browse preset formations and partial layouts; select up to ten seed cards.
- Use batch selection, removal, undo and redo, and automatic support placement.
- Save working drafts automatically and manage archives, tags, favorites and historical versions in SQLite.
- Preview historical versions and restore them while preserving earlier history.
- Import and export supported reference-site formation strings, complete project files and `PVZF1:` text.
- Preview, export and copy PNG images; open up to three independent mirror windows.

This is not a complete reproduction of the reference website. See the [feature comparison](docs/feature-parity.md) and [behavior notes](docs/behavior.md) for supported behavior and limitations (Chinese).

## Development

The recorded development baseline is Flutter **3.19.2 stable**, Dart **3.3.0**. The package requires Dart >=3.3; dependencies are locked in `pubspec.lock`.

```sh
flutter pub get
flutter run -d macos
```

Choose your actual target device or desktop platform. Build on the corresponding host:

```sh
flutter build macos
flutter build windows
flutter build linux
flutter build apk
flutter build ios --no-codesign
```

macOS and iOS require Xcode and CocoaPods. Android requires the Android SDK and JDK 17 compatible with Gradle 7.6.3. Windows requires the Flutter desktop toolchain and system `winsqlite3.dll`. Linux requires the Flutter GTK build dependencies, `libsqlite3.so.0`, `zenity` for file dialogs and appropriate CJK fonts. Release signing and store distribution are not configured.

When replacing a running macOS build, use `swift tool/restart_macos_app.swift <app-bundle-path>` so the existing instance can save and quit normally.

## Usage and data

Open a recent draft or start a blank board, select objects from the catalog, then save an archive or export a project. Settings include language, map, sun, seed slots and display options. The default export directory is `PVZ Formation Editor` inside Documents and can be changed in settings.

Desktop shortcuts: Ctrl/Cmd+Z to undo, Ctrl/Cmd+Shift+Z or Ctrl+Y to redo, Ctrl/Cmd+S to save, Delete/Backspace to remove selected objects and Esc to clear selection. Text fields retain normal editing behavior.

Drafts save after a 700 ms debounce. Only a successful SQLite commit is shown as saved. Forced termination may lose pending changes. Archives are separate snapshots; drafts do not overwrite them automatically. Undo history is retained for an open tab, but does not survive restart.

- `*.pvzf.json` preserves a complete formation document and resource manifest version, rather than the entire archive library.
- `PVZF1:` is a Base64URL project representation, distinct from the reference site's format.
- Reference-site strings support verified map/object IDs and effects; unsupported fields are rejected.
- PNG files are static images and cannot replace editable backups.

The database is `formations.sqlite` in the application support directory. The library information panel shows its exact local path. To back up all drafts, archive metadata and history, quit normally and copy the database together with any companion journal/WAL/SHM files. Preserve the current data before restoring a complete backup with the app closed. There is no one-click full-library backup/merge UI.

Project imports are limited to 8 MiB and 5,000 objects, validated before replacing the current document, and do not execute code. Custom image assets are not supported.

## Verification

```sh
flutter analyze
dart test test/formation_test.dart test/storage_test.dart test/website_codec_test.dart test/original_catalog_test.dart test/layout_actions_test.dart
FLUTTER_SDK=/path/to/flutter ./tool/check.sh
```

The Unix/macOS check script runs analysis, Dart/SQLite tests, a Flutter debug bundle build and engine smoke checks. Set `FLUTTER_ENGINE_DIR` if needed. These checks do not establish platform package or physical-device acceptance.

Previous records report a successful macOS Debug build and launch. Android packaging was blocked by a Gradle download DNS failure. Windows, Linux and iOS have not been built or run in those records. See [validation history](docs/progress.md) and [macOS notes](docs/macos-run.md); these are historical results, not a new validation of this documentation change.

## Source layout

`lib/domain` contains immutable documents, validation, layouts and codecs; `lib/editor` handles commands, autosave and rendering; `lib/storage` contains the SQLite repository and migrations; `lib/platform` and native runners provide platform integration; `lib/main.dart` contains the library and editor UI.

## Credits

Thanks to PopCap Games, the authors and maintainers of the [jspvz formation editor](http://jspvz.com/ArrayDesign/), and the contributors to Flutter, Dart and the open-source dependencies used here. See [acknowledgments](ACKNOWLEDGMENTS.md) and [asset provenance](docs/assets.md).
