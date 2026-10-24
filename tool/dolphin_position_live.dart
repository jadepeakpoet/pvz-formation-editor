// Focused native acceptance for the dolphin's atlas/game coordinate boundary.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/zombie_layout.dart';
import 'package:pvz_formation_editor/domain/placement_layout.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final pid = int.parse(Platform.environment['PVZ_GAME_PID']!);
  final reportFile = File(Platform.environment['PVZ_DOLPHIN_REPORT']!);
  final before = await GameBridge.readFormation(pid, includeZombies: true);
  final report = <String, dynamic>{'initial': before.toJson()};
  await reportFile.writeAsString(jsonEncode(report));
  try {
    final target = PlacementLayout.prepare(LibraryPresets.all[59].document,
        includeZombies: true).document;
    final after = await GameBridge.applyFormation(pid, target, before);
    final dolphin = after.formation.pieces.singleWhere((p) => p.type == 'dolphin');
    final raw = after.runtimePieces.singleWhere((p) => p['zombieType'] == 14);
    if (ZombieLayout.x(dolphin) != 287 || dolphin.frameRow != 1 || dolphin.frameCol != 2 ||
        (raw['x'] as num).toDouble() != 97 || raw['eating'] != true || raw['animation'] != 'anim_eat' ||
        (raw['renderOffsetY'] as num?)?.toDouble() != 42) {
      throw StateError('Dolphin coordinate/state verification failed');
    }
    final pumpkin = after.runtimePieces.singleWhere((p) => p['type'] == 30 && p['row'] == 2 && p['col'] == 0);
    if ((pumpkin['eatenFlashCountdown'] as int? ?? 0) <= 0) {
      throw StateError('Pumpkin chew highlight was not initialized');
    }
    report.addAll({'status': 'pass', 'editorX': 287, 'nativeCanvasX': raw['x'],
      'actorX': (raw['x'] as num) - 40, 'frame': [dolphin.frameRow, dolphin.frameCol],
      'eating': raw['eating'], 'pumpkinFlash': pumpkin['eatenFlashCountdown'],
      'renderOffsetY': raw['renderOffsetY'],
      'leftApplied': true});
  } catch (error, stack) {
    report.addAll({'status': 'fail', 'error': '$error\n$stack'});
    final current = await GameBridge.readFormation(pid, includeZombies: true);
    await GameBridge.applyFormation(pid, before.formation, current);
    report['originalRestored'] = true;
  }
  await reportFile.writeAsString(jsonEncode(report));
  exit(report['status'] == 'pass' ? 0 : 1);
}
