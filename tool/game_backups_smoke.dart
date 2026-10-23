// Real filesystem + native-channel contract tests, not live Windows acceptance.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';
import 'package:pvz_formation_editor/platform/game_backups.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Map<Object?, Object?> wire(Formation formation) => {
      'pid': 1051,
      'version': '1.0.0.1051 en',
      'map': formation.mapId,
      'sunValue': formation.sunValue,
      'pieces': formation.pieces
          .map((p) => {
                'type': WebsiteCodec.plantIds.indexOf(p.type),
                'row': p.row,
                'col': p.col,
                'imitater': p.effects.contains('模仿者'),
                'asleep': p.asleep,
              })
          .toList(),
    };
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await Directory.systemTemp.createTemp('pvz-game-backups-');
  var current = Formation(
      mapId: 'day',
      sunValue: 50,
      pieces: [Piece(id: 'p', type: 'pea', row: 0, col: 0, layer: 10)]);
  var writes = 0;
  var failWrite = false;
  final results = <String>[];
  late GameBackups store;
  Future<GameFormationSnapshot> read(int pid) async =>
      GameFormationSnapshot.fromJson(wire(current));
  Future<GameFormationSnapshot> write(
      int pid, Formation target, GameFormationSnapshot before) async {
    final backups = await Directory('${directory.path}/memory')
        .list()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    check(backups.isNotEmpty, 'Backup must exist before native write');
    var matched = false;
    for (final file in backups) {
      try {
        final snapshot = await store.load(file.path);
        if (snapshot.formation.sunValue == before.formation.sunValue) {
          matched = true;
        }
      } on FormatException {/* An older backup was deliberately corrupted. */}
    }
    check(matched, 'Durable backup contains exact original sun before write');
    check(before.formation.sunValue == current.sunValue,
        'Expected snapshot is fresh');
    writes++;
    if (failWrite) throw StateError('Injected native write failure');
    current = target;
    return read(pid);
  }

  store = GameBackups(Directory('${directory.path}/memory'),
      read: read, write: write);
  try {
    final first = await store.apply(1051, current.copy(sunValue: 100));
    check(
        current.sunValue == 100 &&
            (await store.load(first.backupPath)).formation.sunValue == 50,
        'Exact prewrite saved');
    results.add('durable exact backup before write');
    final restored = await store.undo(1051, first.backupPath);
    check(
        current.sunValue == 50 &&
            (await store.load(restored.backupPath)).formation.sunValue == 100,
        'Undo retains redo snapshot');
    results.add('undo creates redo backup');
    final beforeWrongPid = writes;
    try {
      await store.undo(9999, restored.backupPath);
      throw StateError('Must reject another process');
    } on StateError catch (e) {
      check(
          e.toString().contains('另一个游戏进程'), 'PID mismatch has explicit error');
    }
    check(
        writes == beforeWrongPid, 'Another process cannot receive this backup');
    results.add('undo rejects backup from another process');
    check(
        (await store.list(1051)).contains(first.backupPath) &&
            (await store.list(9999)).isEmpty,
        'Recovery history only lists matching process backups');
    results.add('durable recovery history grouped by process');
    final blocker = File('${directory.path}/blocked');
    await blocker.writeAsString('file');
    final blocked = GameBackups(Directory('${blocker.path}/child'),
        read: read, write: write);
    final beforeCount = writes;
    try {
      await blocked.apply(1051, current.copy(sunValue: 999));
      throw StateError('Must fail backup');
    } on FileSystemException {
      check(writes == beforeCount, 'Failed backup aborts before native call');
    }
    results.add('backup failure prevents native write');
    failWrite = true;
    try {
      await store.apply(1051, current.copy(sunValue: 999));
      throw StateError('Must fail write');
    } on GameWriteFailure catch (e) {
      check((await store.load(e.backupPath)).formation.sunValue == 50,
          'Failure retains usable original');
    }
    failWrite = false;
    results.add('native failure retains usable backup');
    final raw = jsonDecode(await File(first.backupPath).readAsString()) as Map;
    raw['payload'] = (raw['payload'] as String).replaceFirst('50', '51');
    await File(first.backupPath).writeAsString(jsonEncode(raw));
    final beforeCorruption = writes;
    try {
      await store.undo(1051, first.backupPath);
      throw StateError('Must reject corruption');
    } on FormatException {
      check(writes == beforeCorruption, 'Corrupt backup cannot reach write');
    }
    results.add('corrupt backup rejected before write');
    await Future.wait([
      store.apply(1051, current.copy(sunValue: 200)),
      store.apply(1051, current.copy(sunValue: 300))
    ]);
    check(current.sunValue == 300, 'Queued writes preserve order');
    results.add('per-process writes serialized with fresh snapshots');
    final sleeping = GameFormationSnapshot.fromJson({
      'pid': 1051,
      'version': '1.0.0.1051 en',
      'map': 'day',
      'sunValue': 50,
      'pieces': [
        {'type': 8, 'row': 0, 'col': 0, 'imitater': false, 'asleep': true}
      ]
    });
    check(
        sleeping.formation.pieces.single.asleep &&
            GameFormationSnapshot.fromJson(sleeping.toJson())
                .formation
                .pieces
                .single
                .asleep,
        'Sleep state retained');
    results.add('game sleep state preserved by snapshot');
    await File('/tmp/pvz-game-backups-report.json').writeAsString(jsonEncode({
      'pass': results,
      'scope': 'real filesystem, injected game adapter; not live game memory'
    }));
    stdout.writeln('PASS ${results.length}: ${results.join('; ')}');
    await directory.delete(recursive: true);
    exit(0);
  } catch (e, st) {
    stderr.writeln('$e\n$st');
    exit(1);
  }
}
