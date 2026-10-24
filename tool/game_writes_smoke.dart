// Injected adapter checks; not live Windows game acceptance.
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';
import 'package:pvz_formation_editor/platform/game_writes.dart';

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
  final directory = await Directory.systemTemp.createTemp('pvz-game-writes-');
  var current = Formation(mapId: 'day', sunValue: 50);
  var failRead = false;
  var writes = 0;
  Future<GameFormationSnapshot> read(int pid) async {
    if (failRead) throw StateError('Read failed');
    return GameFormationSnapshot.fromJson(wire(current));
  }

  Future<GameFormationSnapshot> write(
      int pid, Formation target, GameFormationSnapshot before) async {
    check(before.formation.sunValue == current.sunValue,
        'Fresh consistency snapshot');
    writes++;
    current = target;
    return read(pid);
  }

  final first = GameWrites(directory, read: read, write: write);
  final second = GameWrites(directory, read: read, write: write);
  try {
    await Future.wait([
      first.apply(1051, current.copy(sunValue: 100)),
      second.apply(1051, current.copy(sunValue: 200))
    ]);
    check(writes == 2 && current.sunValue == 200,
        'Writes across panels are serialized');
    check((await directory.list().toList()).isEmpty, 'No history backup files');
    failRead = true;
    var rejected = false;
    try {
      await first.apply(1051, current);
    } on StateError {
      rejected = true;
    }
    check(rejected && writes == 2, 'Failed read prevents write');
    stdout.writeln(
        'PASS: fresh snapshot, shared serialization, no backups, read failure');
    await directory.delete();
    exit(0);
  } catch (e, st) {
    stderr.writeln('$e\n$st');
    exit(1);
  }
}
