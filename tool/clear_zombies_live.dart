// Native regression: clearing zombies must retain the existing plants and scene.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/placement_layout.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final pid = int.parse(Platform.environment['PVZ_GAME_PID']!);
  final report = <String, dynamic>{};
  final original = await GameBridge.readFormation(pid, includeZombies: true);
  try {
    final target = PlacementLayout.prepare(LibraryPresets.all[59].document,
        includeZombies: true).document;
    final before = await GameBridge.applyFormation(pid, target, original);
    final plants = before.runtimePieces.where((p) => !p.containsKey('zombieType')).toList();
    final zombies = before.runtimePieces.where((p) => p.containsKey('zombieType')).length;
    if (zombies == 0) throw StateError('Fixture has no zombies');
    final cleared = await GameBridge.clearZombies(pid);
    final after = await GameBridge.readFormation(pid, includeZombies: true);
    final afterPlants = after.runtimePieces.where((p) => !p.containsKey('zombieType')).toList();
    if (cleared != zombies || after.runtimePieces.any((p) => p.containsKey('zombieType')) ||
        jsonEncode(plants) != jsonEncode(afterPlants) || before.formation.sunValue != after.formation.sunValue ||
        before.formation.mapId != after.formation.mapId) {
      throw StateError('Clear changed plants, scene, sunlight, or failed to remove zombies');
    }
    if (await GameBridge.clearZombies(pid) != 0) throw StateError('Empty clear count');
    report.addAll({'status': 'pass', 'cleared': cleared,
      'plantRuntimeUnchanged': true, 'emptyClear': true});
  } catch (error, stack) {
    report.addAll({'status': 'fail', 'error': '$error\n$stack'});
  } finally {
    final current = await GameBridge.readFormation(pid, includeZombies: true);
    await GameBridge.applyFormation(pid, original.formation, current);
    report['originalRestored'] = true;
    await File(Platform.environment['PVZ_CLEAR_REPORT']!).writeAsString(jsonEncode(report));
  }
  exit(report['status'] == 'pass' ? 0 : 1);
}
