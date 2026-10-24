import 'dart:convert';
import 'dart:io';
import 'dart:ui' as engine;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/domain/placement_layout.dart';
import 'package:pvz_formation_editor/domain/zombie_layout.dart';
import 'package:pvz_formation_editor/domain/zombie_game_state.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';
import 'package:pvz_formation_editor/platform/game_writes.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

import 'live_preset_apply_smoke.dart' as ui;

@pragma('vm:entry-point')
Future<void> toolboxMain() => app.toolboxMain();
@pragma('vm:entry-point')
Future<void> libraryMain() => app.libraryMain();

String signature(Formation document) {
  final rows =
      document.pieces
          .map(
            (p) => ZombieLayout.gameType(p.type) != null
                ? '${p.type}:${p.row}:${(ZombieLayout.x(p) * 4).round()}'
                : '${p.type}:${p.row}:${p.col}:${p.asleep}:${p.effects.contains('模仿者')}',
          )
          .toList()
        ..sort();
  return jsonEncode([document.mapId, rows]);
}

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OriginalAssets.ensureLoaded();
  final output = File(Platform.environment['PVZ_ZOMBIE_REPORT']!);
  final report = <String, dynamic>{'cases': <String>[]};
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  final repo = await FormationRepository.open(':memory:');
  final writes = GameWrites(Directory.systemTemp);
  GameFormationSnapshot? before;
  var needsRestore = false;
  EditorSession? editorSession;
  int? gamePid;
  Future<void> save() => output.writeAsString(jsonEncode(report));
  try {
    final requested = int.tryParse(Platform.environment['PVZ_GAME_PID'] ?? '');
    final game = (await GameBridge.listGames()).firstWhere(
      (g) => g.canWrite && (requested == null || g.pid == requested),
    );
    gamePid = game.pid;
    before = await GameBridge.readFormation(game.pid, includeZombies: true);
    report['initial'] = before.toJson();
    await save();
    var rejectedCustomMap = false;
    try {
      await GameBridge.channel.invokeMethod<dynamic>('applyFormation', {
        'pid': game.pid,
        'target': {'map': 'day6', 'sunValue': before.formation.sunValue,
          'pieces': [{'type': 0, 'row': 5, 'col': 0, 'asleep': false, 'imitater': false}]},
        'expectedBefore': before.toJson(),
      });
      needsRestore = true;
    } on PlatformException catch (error) {
      rejectedCustomMap = error.message?.contains('扩展地图') == true;
    }
    check(rejectedCustomMap, 'Native validation must identify the unsupported map before coordinates');
    final unchanged = await GameBridge.readFormation(game.pid, includeZombies: true);
    check(signature(unchanged.formation) == signature(before.formation), 'Rejected custom map must leave the game untouched');
    (report['cases'] as List).add('custom-six-row-map-rejected-without-changing-game');
    if (Platform.environment['PVZ_ZOMBIE_VALIDATE_ONLY'] == '1') {
      report['status'] = 'pass';
      report['originalRestored'] = true;
      report['noGameMutation'] = true;
      report['flutterErrors'] = errors;
      await save();
      await repo.close();
      exit(0);
    }
    final restoreFile = Platform.environment['PVZ_ZOMBIE_RESTORE_FILE'];
    if (restoreFile != null) {
      final saved = jsonDecode(await File(restoreFile).readAsString()) as Map;
      final original = GameFormationSnapshot.fromJson(
        Map<Object?, Object?>.from(saved['initial'] as Map),
      );
      needsRestore = true;
      await writes.apply(game.pid, original.formation, includeZombies: true);
      final restored = await GameBridge.readFormation(
        game.pid,
        includeZombies: true,
      );
      check(
        signature(restored.formation) == signature(original.formation),
        'Original board restored',
      );
      report['status'] = 'pass';
      report['originalRestored'] = true;
      before = null;
      await save();
      exit(0);
    }
    report['initial'] = before.toJson();
    await save();
    // Validate every captured appearance before changing the board so restoration
    // also covers an existing stable zombie layout.
    for (final piece in before.formation.pieces) {
      if (ZombieLayout.gameType(piece.type) != null) ZombieGameState.of(piece);
    }
    final types = ObjectSpec.all
        .where((s) => ZombieLayout.gameType(s.id) != null)
        .toList();
    final dense = Formation(
      mapId: 'day',
      pieces: [
        for (var i = 0; i < types.length; i++)
          Piece(
            id: 'z-$i',
            type: types[i].id,
            row: i % 5,
            col: i % 9,
            layer: types[i].layer,
          ),
      ],
    );
    needsRestore = true;
    await writes.apply(game.pid, dense);
    final denseRead = await GameBridge.readFormation(
      game.pid,
      includeZombies: true,
    );
    check(
      signature(denseRead.formation) == signature(dense),
      'All supported zombie types read back at their intended positions',
    );
    report['zombieTypes'] = types.length;
    (report['cases'] as List).add('all-zombie-types');

    final statePieces = <Piece>[];
    for (final entry in ZombieGameState.profiles.entries) {
      final type = WebsiteCodec.typeForIndex(entry.key + 0x50)!;
      for (final state in entry.value) {
        final x = 100.0 + statePieces.length * 5;
        final row = state.pool ? 2 : 0;
        statePieces.add(
          Piece(
            id: 'state-${statePieces.length}',
            type: type,
            row: row,
            col: ZombieLayout.column(x),
            layer: ObjectSpec.byId(type).layer,
            frameRow: state.row,
            frameCol: state.col,
            websiteFields: ZombieLayout.positionFields(
              type,
              row,
              ZombieLayout.column(x),
              x,
              frameRow: state.row,
              frameCol: state.col,
            ),
          ),
        );
      }
    }
    await writes.apply(game.pid, Formation(mapId: 'pool', pieces: statePieces));
    final stateRead = await GameBridge.readFormation(
      game.pid,
      includeZombies: true,
    );
    for (final piece in statePieces) {
      final type = ZombieLayout.gameType(piece.type)!;
      final raw = stateRead.runtimePieces.singleWhere(
        (p) =>
            p['zombieType'] == type &&
            p['row'] == piece.row &&
            ((p['x'] as num) - ZombieLayout.gameX(piece)).abs() < .01,
      );
      final expected = ZombieGameState.of(piece).toJson();
      for (final key in expected.keys.where((k) => k != 'hidden')) {
        check(
          raw[key] == expected[key],
          '${piece.type} ${piece.frameRow},${piece.frameCol}: $key expected ${expected[key]} got ${raw[key]}',
        );
      }
      final restored = stateRead.formation.pieces.singleWhere(
        (p) =>
            p.type == piece.type &&
            p.row == piece.row &&
            (ZombieLayout.x(p) - ZombieLayout.x(piece)).abs() < .01,
      );
      check(
        jsonEncode(ZombieGameState.of(restored).toJson()) ==
            jsonEncode(expected),
        'Read frame must retain the actual state for ${piece.type}',
      );
      for (final prefix in expected['hidden'] as List<String>) {
        check(
          (raw['hiddenTracks'] as List).any(
            (name) => (name as String).startsWith(prefix),
          ),
          'Carried object is still visible: ${piece.type}/$prefix',
        );
      }
    }
    report['zombieStates'] = statePieces.length;
    (report['cases'] as List).add(
      'all-zombie-appearance-states-and-render-layers',
    );

    runApp(
      MaterialApp(home: app.LibraryPage(repository: repo, showTitle: false)),
    );
    await ui.settle();
    await ui.settle();
    final dynamic library =
        (ui.find((w) => w is app.LibraryPage).single as StatefulElement).state;
    for (final index in [59, 81, 303]) {
      final preset = LibraryPresets.all[index];
      final field = ui
          .find((w) => w.key == const ValueKey('library-search'))
          .single;
      final editor =
          ui
                  .find(
                    (w) =>
                        w is EditableText &&
                        w.controller == (field.widget as TextField).controller,
                  )
                  .single
              as StatefulElement;
      (editor.state as EditableTextState).updateEditingValue(
        TextEditingValue(
          text: preset.name,
          selection: TextSelection.collapsed(offset: preset.name.length),
        ),
      );
      await ui.settle();
      await ui.tapKey('library-item-preset:${preset.id}');
      await ui.tapKey('library-apply-game');
      for (var i = 0; i < 250 && library.applyingArchiveToGame == true; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final actual = await GameBridge.readFormation(
        game.pid,
        includeZombies: true,
      );
      final expected = PlacementLayout.prepare(
        preset.document,
        includeZombies: true,
      ).document;
      check(
        signature(actual.formation) == signature(expected),
        'Preset ${preset.id} complete UI apply/readback',
      );
      if (index == 59) {
        final dolphin = actual.formation.pieces.singleWhere(
          (p) => p.type == 'dolphin',
        );
        check(
          ZombieLayout.x(dolphin) == 287 &&
              dolphin.frameRow == 1 &&
              dolphin.frameCol == 2,
          'Dolphin remains at the original left-side anchor in swimming state',
        );
      }
      final readCode = FormationExchange.encodeGameRead(actual.formation);
      final roundtrip = FormationExchange.decode(readCode);
      check(
        signature(roundtrip) == signature(actual.formation),
        'Full game code retains zombies and positions',
      );
      (report['cases'] as List).add('preset-$index-full-ui-and-code');
      await save();
      ScaffoldMessenger.of(ui.find((w) => w is app.LibraryPage).single)
          .clearSnackBars();
    }
    editorSession = EditorSession(
      repo,
      persistDraft: false,
      document: LibraryPresets.all[81].document,
      readOnly: true,
    );
    final mainCapture = GlobalKey();
    runApp(
      RepaintBoundary(
        key: mainCapture,
        child: MaterialApp(
          home: app.EditorPage(
            session: editorSession,
            libraryPath: ':memory:',
            continueArchive: (_) async {},
          ),
        ),
      ),
    );
    await ui.settle();
    await ui.settle();
    final dynamic editorPage =
        (ui.find((w) => w is app.EditorPage).single as StatefulElement).state;
    for (
      var i = 0;
      i < 100 && editorPage.windowHandshakeComplete != true;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final picker =
        ui
                .find((w) => w.key == const ValueKey('board-picker-toggle'))
                .single
                .renderObject
            as RenderBox;
    final applyButton =
        ui
                .find((w) => w.key == const ValueKey('board-apply-game'))
                .single
                .renderObject
            as RenderBox;
    final toolbox =
        ui
                .find((w) => w.key == const ValueKey('main-sidebar-toolbox'))
                .single
                .renderObject
            as RenderBox;
    check(
      picker.localToGlobal(Offset.zero).dx <
              applyButton.localToGlobal(Offset.zero).dx &&
          applyButton.localToGlobal(Offset.zero).dx <
              toolbox.localToGlobal(Offset.zero).dx,
      'Main game action is between seed slots and toolbox',
    );
    await ui.tapKey('board-apply-game');
    for (var i = 0; i < 200 && editorPage.gameBusy == true; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final fromMain = await GameBridge.readFormation(
      game.pid,
      includeZombies: true,
    );
    check(
      signature(fromMain.formation) == signature(editorSession.document),
      'Main play button applies the current complete formation',
    );
    final screenshot =
        await (mainCapture.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage();
    try {
      final png = await screenshot.toByteData(
        format: engine.ImageByteFormat.png,
      );
      await File('${output.parent.path}/main-ui.png')
          .writeAsBytes(png!.buffer.asUint8List());
    } finally {
      screenshot.dispose();
    }
    (report['cases'] as List).add('main-play-button-and-native-layout');
    final last = await GameBridge.readFormation(game.pid, includeZombies: true);
    final zombies = last.formation.pieces
        .where((p) => ZombieLayout.gameType(p.type) != null)
        .toList();
    await writes.apply(game.pid, Formation(mapId: last.formation.mapId));
    final afterPlants = await GameBridge.readFormation(
      game.pid,
      includeZombies: true,
    );
    check(
      signature(
            afterPlants.formation.copy(
              pieces: afterPlants.formation.pieces
                  .where((p) => ZombieLayout.gameType(p.type) != null)
                  .toList(),
            ),
          ) ==
          signature(last.formation.copy(pieces: zombies)),
      'Legacy plant-only apply preserves existing zombies',
    );
    (report['cases'] as List).add('legacy-plant-only-compatibility');
    check(errors.isEmpty, 'No Flutter errors: $errors');
    report['status'] = 'pass';
  } catch (e, st) {
    report['status'] = 'fail';
    report['error'] = '$e\n$st';
  } finally {
    if (needsRestore && before != null && gamePid != null) {
      try {
        await writes.apply(gamePid, before.formation, includeZombies: true);
        final restored = await GameBridge.readFormation(
          gamePid,
          includeZombies: true,
        );
        report['originalRestored'] =
            signature(restored.formation) == signature(before.formation);
      } catch (e) {
        report['restoreError'] = '$e';
      }
    }
    report['flutterErrors'] = errors;
    await save();
    editorSession?.dispose();
    await repo.close();
  }
  stdout.writeln(
    jsonEncode({
      'status': report['status'],
      'error': report['error'],
      'restored': report['originalRestored'],
    }),
  );
  exit(
    report['status'] == 'pass' && report['originalRestored'] == true ? 0 : 1,
  );
}
