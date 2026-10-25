import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/layouts.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';

List<String> shape(Formation f) => f.pieces.map((p) => '${p.type}:${p.row}:${p.col}').toList()..sort();
List<Piece> cannons(int row, String base) => [
  for (final col in [0, 2, 7]) ...[
    Piece(id: 'c-$row-$col', type: 'cob', row: row, col: col, layer: 10),
    for (final cell in [col, col + 1]) Piece(id: 'b-$row-$cell',
        type: base, row: row, col: cell, layer: 0),
  ],
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final pid = int.parse(Platform.environment['PVZ_GAME_PID']!);
  final file = File(Platform.environment['PVZ_CANNON_SUPPORT_REPORT']!);
  final before = await GameBridge.readFormation(pid, includeZombies: true);
  final report = <String, dynamic>{'cases': <Map<String, dynamic>>[]};
  try {
    Future<void> apply(Formation target, String name) async {
      final current = await GameBridge.readFormation(pid, includeZombies: true);
      final returned = await GameBridge.applyFormation(pid, target, current);
      final read = await GameBridge.readFormation(pid, includeZombies: true);
      if (read.formation.mapId != target.mapId || shape(read.formation).join('|') != shape(target).join('|') ||
          shape(returned.formation).join('|') != shape(target).join('|'))
        throw StateError('Game shape mismatch: $name');
      (report['cases'] as List).add({'name': name, 'objects': read.formation.pieces.length,
          'cannons': read.formation.pieces.where((p) => p.type == 'cob').length});
    }
    for (final map in ['day', 'night', 'pool', 'fog', 'roof', 'moonRoof']) {
      final source = Formation(mapId: map, pieces: cannons(0, 'pot'));
      await apply(OriginalActions.apply(source, '碾花盆'), '$map/crush-front-pots');
    }
    for (final map in ['pool', 'fog']) {
      final source = Formation(mapId: map, pieces: cannons(2, 'lily'));
      await apply(OriginalActions.apply(source, '炸荷叶'), '$map/remove-front-lilies');
      final mixed = Formation(mapId: map, pieces: [...cannons(0, 'pot'), ...cannons(2, 'lily')]);
      final first = OriginalActions.apply(mixed, '碾花盆');
      await apply(first, '$map/mixed-crush-land-only');
      await apply(OriginalActions.apply(first, '炸荷叶'), '$map/mixed-remove-water-only');
    }
    report['status'] = 'pass';
  } catch (error, stack) {
    report.addAll({'status': 'fail', 'error': '$error\n$stack'});
  } finally {
    final current = await GameBridge.readFormation(pid, includeZombies: true);
    await GameBridge.applyFormation(pid, before.formation, current);
    final restored = await GameBridge.readFormation(pid, includeZombies: true);
    report['originalRestored'] = before.formation.mapId == restored.formation.mapId &&
        shape(before.formation).join('|') == shape(restored.formation).join('|');
    await file.writeAsString(jsonEncode(report));
  }
  exit(report['status'] == 'pass' && report['originalRestored'] == true ? 0 : 1);
}
