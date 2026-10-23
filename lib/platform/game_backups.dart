import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../domain/formation.dart';
import '../storage/file_backups.dart';
import 'game_bridge.dart';

class GameWriteResult {
  final GameFormationSnapshot after;
  final String backupPath;
  GameWriteResult(this.after, this.backupPath);
}

class GameWriteFailure implements Exception {
  final Object cause;
  final String backupPath;
  GameWriteFailure(this.cause, this.backupPath);
  @override
  String toString() => '$cause\n原阵型备份：$backupPath';
}

/// A durable backup must finish before the native adapter may change the game.
class GameBackups {
  final Directory directory;
  final Future<GameFormationSnapshot> Function(int) read;
  final Future<GameFormationSnapshot> Function(
      int, Formation, GameFormationSnapshot) write;
  final Map<int, Future<void>> _pending = {};
  GameBackups(this.directory,
      {Future<GameFormationSnapshot> Function(int)? read,
      Future<GameFormationSnapshot> Function(
              int, Formation, GameFormationSnapshot)?
          write})
      : read = read ?? GameBridge.readFormation,
        write = write ?? GameBridge.applyFormation;

  Future<GameWriteResult> apply(int pid, Formation target) {
    final previous = _pending[pid] ?? Future<void>.value();
    final operation = previous.then((_) async {
      final before = await read(pid);
      await directory.create(recursive: true);
      final payload = jsonEncode({
        'format': 'pvz-game-memory-backup',
        'version': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'before': before.toJson(),
        'target': target.toJson(),
      });
      final path = '${directory.path}/game-$pid-${newId()}.json';
      final content = utf8.encode(payload);
      await FileBackups.replace(
          path,
          Uint8List.fromList(utf8.encode(jsonEncode(
              {'payload': payload, 'checksum': checksum(content)}))));
      // Failure to create the integrity-protected backup aborts before write.
      try {
        final after = await write(pid, target, before);
        return GameWriteResult(after, path);
      } catch (e) {
        throw GameWriteFailure(e, path);
      }
    });
    _pending[pid] =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  Future<GameFormationSnapshot> load(String path) async {
    final file = File(path);
    if (await file.length() > FileBackups.maxBytes) {
      throw const FormatException('游戏备份过大');
    }
    final envelope = jsonDecode(await file.readAsString()) as Map;
    final payload = envelope['payload'] as String;
    if (checksum(utf8.encode(payload)) != envelope['checksum']) {
      throw const FormatException('游戏备份校验失败，未写入游戏');
    }
    final record = jsonDecode(payload) as Map;
    if (record['format'] != 'pvz-game-memory-backup' ||
        record['version'] != 1) {
      throw const FormatException('不是支持的游戏内存备份');
    }
    return GameFormationSnapshot.fromJson(
        Map<Object?, Object?>.from(record['before'] as Map));
  }

  Future<GameWriteResult> undo(int pid, String backupPath) async {
    final original = await load(backupPath);
    if (original.pid != pid) {
      throw StateError('此备份属于另一个游戏进程，未写入游戏');
    }
    final current = await read(pid);
    if (current.version != original.version ||
        current.formation.mapId != original.formation.mapId) {
      throw StateError('游戏版本或场地已变化，请回到原场地后恢复');
    }
    // Undo itself creates another backup, so the user can undo the restore too.
    return apply(pid, original.formation);
  }

  Future<List<String>> list(int pid) async {
    if (!await directory.exists()) return [];
    final files = <File>[];
    await for (final item in directory.list()) {
      if (item is File &&
          item.uri.pathSegments.last.startsWith('game-$pid-') &&
          item.path.endsWith('.json')) {
        try {
          if ((await load(item.path)).pid == pid) files.add(item);
        } on FormatException {
          /* Invalid backups cannot be offered for restore. */
        }
      }
    }
    final dated = <(String, DateTime)>[];
    for (final file in files) {
      dated.add((file.path, await file.lastModified()));
    }
    dated.sort((a, b) => b.$2.compareTo(a.$2));
    return dated.map((e) => e.$1).toList();
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
