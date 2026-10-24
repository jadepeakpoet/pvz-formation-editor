import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/domain/placement_layout.dart';
import 'package:pvz_formation_editor/domain/zombie_layout.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';
import 'package:pvz_formation_editor/platform/game_writes.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

import 'live_preset_apply_smoke.dart' as ui;

String signature(Formation document) {
  final rows = document.pieces
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
  int? gamePid;
  Future<void> save() => output.writeAsString(jsonEncode(report));
  try {
    final requested = int.tryParse(Platform.environment['PVZ_GAME_PID'] ?? '');
    final game = (await GameBridge.listGames()).firstWhere(
      (g) => g.canWrite && (requested == null || g.pid == requested),
    );
    gamePid = game.pid;
    before = await GameBridge.readFormation(game.pid, includeZombies: true);
    final restoreFile = Platform.environment['PVZ_ZOMBIE_RESTORE_FILE'];
    if (restoreFile != null) {
      final saved = jsonDecode(await File(restoreFile).readAsString()) as Map;
      final original = GameFormationSnapshot.fromJson(
        Map<Object?, Object?>.from(saved['initial'] as Map),
      );
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
    // This acceptance run restores a plant layout, so require no active zombies
    // rather than approximating the user's pre-existing moving zombie states.
    check(
      !ZombieLayout.contains(before.formation),
      'Start with a paused board without active zombies',
    );
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

    runApp(
      MaterialApp(home: app.LibraryPage(repository: repo, showTitle: false)),
    );
    await ui.settle();
    await ui.settle();
    final dynamic library =
        (ui.find((w) => w is app.LibraryPage).single as StatefulElement).state;
    for (final index in [59, 81, 303]) {
      final preset = LibraryPresets.all[index];
      final field =
          ui.find((w) => w.key == const ValueKey('library-search')).single;
      final editor = ui
          .find(
            (w) =>
                w is EditableText &&
                w.controller == (field.widget as TextField).controller,
          )
          .single as StatefulElement;
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
    if (before != null && gamePid != null) {
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
