import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Explicit file saves use sibling backups, so recovery works without app data.
class FileBackups {
  static const maxBytes = 8 * 1024 * 1024;
  static final _random = Random.secure();
  static final Map<String, Future<void>> _queues = {};
  static Future<T> _serial<T>(String path, Future<T> Function() action) async {
    final previous = _queues[path] ?? Future<void>.value();
    final next = previous.then((_) => action());
    final completion =
        next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _queues[path] = completion;
    try {
      return await next;
    } finally {
      if (identical(_queues[path], completion)) _queues.remove(path);
    }
  }

  static Future<void> _validateTarget(String path) async {
    if (!File(path).isAbsolute) throw ArgumentError('文件路径必须为绝对路径');
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw FileSystemException('只能保存到普通文件，不能覆盖链接或目录', path);
    }
    final parent = File(path).parent;
    if (!await parent.exists()) {
      throw FileSystemException('保存目录不存在', parent.path);
    }
  }

  static Future<Uint8List> _readLimited(File file) async {
    if (await file.length() > maxBytes) {
      throw const FormatException('文件超过 8 MiB');
    }
    final result = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (result.length + chunk.length > maxBytes) {
        throw const FormatException('文件超过 8 MiB');
      }
      result.add(chunk);
    }
    return result.takeBytes();
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _checksum(List<int> bytes) {
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

  /// Returns the recovery file path when replacing an existing file.
  static Future<String?> replace(String path, Uint8List bytes) {
    if (bytes.length > maxBytes) throw const FormatException('文件超过 8 MiB');
    final stable = Uint8List.fromList(bytes);
    return _serial(path, () async {
      await _validateTarget(path);
      final target = File(path);
      final original =
          await target.exists() ? await _readLimited(target) : null;
      final stamp =
          '${DateTime.now().toUtc().microsecondsSinceEpoch}-${_random.nextInt(0x7fffffff)}';
      final temporary = File('$path.pvz-tmp-$stamp');
      String? backup;
      try {
        await temporary.create(exclusive: true);
        await temporary.writeAsBytes(stable, flush: true);
        if (original != null) {
          backup = '$path.pvz-backup-$stamp.bak';
          final backupFile = File(backup);
          await backupFile.create(exclusive: true);
          await backupFile.writeAsBytes(original, flush: true);
          await File('$backup.json').writeAsString(
              jsonEncode({
                'schemaVersion': 1,
                'originalPath': path,
                'createdAt': DateTime.now().toUtc().toIso8601String(),
                'bytes': original.length,
                'crc32': _checksum(original)
              }),
              flush: true);
        }
        await _validateTarget(path);
        final current =
            await target.exists() ? await _readLimited(target) : null;
        if (original == null
            ? current != null
            : current == null || !_same(original, current)) {
          throw FileSystemException('文件已被其他程序修改，未覆盖；请重新打开或另存为', path);
        }
        await temporary.rename(path);
        return backup;
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
  }

  /// Restoring is itself backed up, allowing the restoration to be undone.
  static Future<String?> restoreBackup(
      String backupPath, String targetPath) async {
    if (await FileSystemEntity.type(backupPath, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FileSystemException('备份不是普通文件', backupPath);
    }
    final manifest =
        jsonDecode(await File('$backupPath.json').readAsString()) as Map;
    if (manifest['schemaVersion'] != 1 ||
        manifest['originalPath'] != targetPath) {
      throw const FormatException('备份与目标文件不匹配');
    }
    final bytes = await _readLimited(File(backupPath));
    if (manifest['bytes'] != bytes.length) {
      throw const FormatException('备份长度不匹配');
    }
    if (manifest['crc32'] != _checksum(bytes)) {
      throw const FormatException('备份校验失败');
    }
    return replace(targetPath, bytes);
  }
}
