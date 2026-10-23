import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/storage/file_backups.dart';

Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));
void main() {
  late Directory dir;
  late String path;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pvz-backups-');
    path = '${dir.path}/formation.txt';
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  test(
      'new file atomic save has no backup, replacement preserves original and manifest',
      () async {
    expect(await FileBackups.replace(path, bytes('first')), isNull);
    final backup = await FileBackups.replace(path, bytes('second'));
    expect(await File(path).readAsString(), 'second');
    expect(await File(backup!).readAsString(), 'first');
    final manifest =
        jsonDecode(await File('$backup.json').readAsString()) as Map;
    expect(manifest['originalPath'], path);
    expect(manifest['bytes'], 5);
    expect((await dir.list().toList()).where((f) => f.path.contains('pvz-tmp')),
        isEmpty);
  });
  test('restore creates redo backup and validates target identity', () async {
    await FileBackups.replace(path, bytes('first'));
    final backup = await FileBackups.replace(path, bytes('second'));
    final redo = await FileBackups.restoreBackup(backup!, path);
    expect(await File(path).readAsString(), 'first');
    expect(await File(redo!).readAsString(), 'second');
    await FileBackups.restoreBackup(redo, path);
    expect(await File(path).readAsString(), 'second');
    await expectLater(
        FileBackups.restoreBackup(backup, '${dir.path}/other.txt'),
        throwsFormatException);
  });
  test('invalid or oversized write leaves existing bytes unchanged', () async {
    await File(path).writeAsString('keep');
    expect(() => FileBackups.replace(path, Uint8List(FileBackups.maxBytes + 1)),
        throwsFormatException);
    expect(await File(path).readAsString(), 'keep');
    await expectLater(FileBackups.replace(dir.path, bytes('bad')),
        throwsA(isA<FileSystemException>()));
    expect(await File(path).readAsString(), 'keep');
    expect((await dir.list().toList()).length, 1);
  });
  test('symlink target is rejected and linked original remains untouched',
      () async {
    await File(path).writeAsString('keep');
    final link = '${dir.path}/link.txt';
    await Link(link).create(path);
    await expectLater(FileBackups.replace(link, bytes('bad')),
        throwsA(isA<FileSystemException>()));
    expect(await File(path).readAsString(), 'keep');
    expect(await Link(link).exists(), isTrue);
  });
  test(
      'concurrent explicit saves serialize and retain every overwritten version',
      () async {
    await File(path).writeAsString('original');
    final backups = await Future.wait([
      FileBackups.replace(path, bytes('a')),
      FileBackups.replace(path, bytes('b'))
    ]);
    expect(await File(path).readAsString(), 'b');
    expect(await File(backups[0]!).readAsString(), 'original');
    expect(await File(backups[1]!).readAsString(), 'a');
    expect(backups[0], isNot(backups[1]));
  });
  test('oversized existing file rejects replacement before mutation', () async {
    await File(path).writeAsBytes(Uint8List(FileBackups.maxBytes + 1));
    await expectLater(
        FileBackups.replace(path, bytes('bad')), throwsFormatException);
    expect(await File(path).length(), FileBackups.maxBytes + 1);
  });
  test('corrupted same-length backup cannot overwrite the target', () async {
    await File(path).writeAsString('first');
    final backup = await FileBackups.replace(path, bytes('later'));
    await File(backup!).writeAsString('wrong');
    await expectLater(
        FileBackups.restoreBackup(backup, path), throwsFormatException);
    expect(await File(path).readAsString(), 'later');
  });
}
