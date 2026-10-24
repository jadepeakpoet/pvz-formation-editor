// Optional live Windows acceptance; restores the captured formation in finally.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/plant_game_state.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';

String composition(Formation f) => (f.pieces
        .map((p) =>
            '${p.type}:${p.row}:${p.col}:${p.asleep}:${p.effects.contains('模仿者')}:${PlantGameState.of(p)}')
        .toList()
      ..sort())
    .join('|');
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final output = File(Platform.environment['PVZ_MUSHROOM_REPORT']!);
  final report = <String, dynamic>{};
  GameFormationSnapshot? before;
  try {
    final games = await GameBridge.listGames();
    final pid = int.tryParse(Platform.environment['PVZ_MUSHROOM_PID'] ?? '');
    final game =
        games.firstWhere((g) => g.canWrite && (pid == null || g.pid == pid));
    before = await GameBridge.readFormation(game.pid);
    final types = Piece.mushroomTypes.toList()..remove('seashroom');
    final pieces = [
      for (var i = 0; i < types.length; i++)
        Piece(
            id: types[i],
            type: types[i],
            row: 0,
            col: i,
            layer: 10,
            frameRow: Piece.defaultPlantFrame(types[i]).$1),
      Piece(id: 'lily', type: 'lily', row: 2, col: 0, layer: 0),
      Piece(id: 'sea', type: 'seashroom', row: 2, col: 0, layer: 10),
      Piece(id: 'cob', type: 'cob', row: 1, col: 0, layer: 10),
      Piece(id: 'potato', type: 'potato', row: 1, col: 2, layer: 10),
      Piece(id: 'nut', type: 'wallnut', row: 1, col: 3, layer: 10, frameCol: 2),
      Piece(
          id: 'tall', type: 'tallnut', row: 1, col: 4, layer: 10, frameCol: 2),
      Piece(
          id: 'cactus', type: 'cactus', row: 1, col: 5, layer: 10, frameRow: 2),
      Piece(
          id: 'garlic', type: 'garlic', row: 1, col: 6, layer: 10, frameCol: 2),
      Piece(id: 'spike', type: 'spike', row: 1, col: 7, layer: 10, frameCol: 1),
      Piece(
          id: 'bigSun',
          type: 'sunshroom',
          row: 1,
          col: 8,
          layer: 10,
          frameRow: 1,
          frameCol: 2),
    ];
    final target = Formation(mapId: 'pool', pieces: pieces);
    final result = await GameBridge.applyFormation(game.pid, target, before);
    final readback = await GameBridge.readFormation(game.pid);
    if (composition(result.formation) != composition(target) ||
        composition(readback.formation) != composition(target)) {
      throw StateError('Live mushroom sleep/readback mismatch');
    }
    final loadedRuntime =
        result.runtimePieces.singleWhere((p) => p['type'] == 47);
    if (loadedRuntime['plantState'] != 37 ||
        loadedRuntime['stateCountdown'] != 0 ||
        loadedRuntime['bodyFrameStart'] is! int) {
      throw StateError(
          'Loaded cannon is not already ready with an animation before resuming');
    }
    final empty = target.copy(pieces: [
      for (final p in target.pieces)
        p.type == 'cob'
            ? p.copy(frameCol: 2)
            : {'fume', 'gloom', 'magnet'}.contains(p.type)
                ? p.copy(frameRow: 0)
                : p
    ]);
    final emptyResult =
        await GameBridge.applyFormation(game.pid, empty, readback);
    if (composition(emptyResult.formation) != composition(empty)) {
      throw StateError('Empty cannon or stable plant state readback mismatch');
    }
    final emptyRuntime =
        emptyResult.runtimePieces.singleWhere((p) => p['type'] == 47);
    if (emptyRuntime['plantState'] != 35 ||
        emptyRuntime['stateCountdown'] != 0 ||
        loadedRuntime['bodyFrameStart'] == emptyRuntime['bodyFrameStart']) {
      throw StateError(
          'Empty cannon must have zero cooldown and a different animation');
    }
    report.addAll({
      'status': 'pass',
      'testedMushrooms': types.length + 1,
      'stablePlantStates': 8,
      'loadedCannonReadyBeforeResume': true,
      'emptyCannonStartsCharging': true,
      'loadedAnimationFrameStart': loadedRuntime['bodyFrameStart'],
      'emptyAnimationFrameStart': emptyRuntime['bodyFrameStart'],
      'explicitDefaultAwakeMushroomsCanSleep': true,
      'sleepingIce':
          readback.formation.pieces.singleWhere((p) => p.type == 'ice').asleep,
      'sleepingDoom':
          readback.formation.pieces.singleWhere((p) => p.type == 'doom').asleep
    });
  } catch (e, st) {
    report.addAll({'status': 'failed', 'error': '$e', 'stack': '$st'});
  } finally {
    if (before != null) {
      try {
        final current = await GameBridge.readFormation(before.pid);
        final restored = await GameBridge.applyFormation(
            before.pid, before.formation, current);
        report['originalRestored'] =
            composition(restored.formation) == composition(before.formation);
        if (report['originalRestored'] != true) report['status'] = 'failed';
      } catch (e) {
        report.addAll({'status': 'failed', 'restoreError': '$e'});
      }
    }
    await output.writeAsString(jsonEncode(report), flush: true);
  }
  exit(report['status'] == 'pass' ? 0 : 1);
}
