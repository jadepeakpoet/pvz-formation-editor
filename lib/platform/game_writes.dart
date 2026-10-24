import 'dart:io';

import '../domain/formation.dart';
import '../domain/placement_layout.dart';
import '../domain/zombie_layout.dart';
import 'game_bridge.dart';

/// Serializes live writes. Only the current consistency snapshot is retained.
class GameWrites {
  final Directory directory;
  final bool _nativeRead;
  final Future<GameFormationSnapshot> Function(int) read;
  final Future<GameFormationSnapshot> Function(
    int,
    Formation,
    GameFormationSnapshot,
  ) write;
  static final Map<int, Future<void>> _operations = {};
  GameWrites(
    this.directory, {
    Future<GameFormationSnapshot> Function(int)? read,
    Future<GameFormationSnapshot> Function(
      int,
      Formation,
      GameFormationSnapshot,
    )? write,
  })  : _nativeRead = read == null,
        read = read ?? GameBridge.readFormation,
        write = write ?? GameBridge.applyFormation;
  Future<GameFormationSnapshot> apply(
    int pid,
    Formation target, {
    bool includeZombies = false,
    bool clearZombies = false,
  }) {
    final full = clearZombies || includeZombies || ZombieLayout.contains(target);
    final layout = PlacementLayout.prepare(
      target,
      includeZombies: full,
    ).document;
    GameBridge.validateTarget(layout);
    final operation = (_operations[pid] ?? Future<void>.value()).then((
      _,
    ) async {
      final current = _nativeRead && full
          ? await GameBridge.readFormation(pid, includeZombies: true)
          : await read(pid);
      return write(pid, layout, current);
    });
    _operations[pid] = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }

  Future<int> clearZombies(int pid) {
    final operation = (_operations[pid] ?? Future<void>.value()).then(
        (_) => GameBridge.clearZombies(pid));
    _operations[pid] = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  static String checksum(List<int> bytes) {
    var value = 0xffffffff;
    for (final byte in bytes) {
      value ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        value = (value >>> 1) ^ ((value & 1) == 0 ? 0 : 0xedb88320);
      }
    }
    return ((value ^ 0xffffffff) & 0xffffffff)
        .toRadixString(16)
        .padLeft(8, '0');
  }
}
