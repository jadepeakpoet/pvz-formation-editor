import 'dart:io';
import 'dart:convert';
import 'package:pvz_formation_editor/domain/archive_bundle.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/library/archive_files.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

void check(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

Future<void> main() async {
  final directory = await Directory.systemTemp.createTemp('pvz-batch-import-');
  final repo =
      await FormationRepository.open('${directory.path}/library.sqlite');
  try {
    final original = Formation();
    final different = original.copy(sunValue: 1234);
    await repo.saveArchive(
        id: 'existing', name: '阵型', document: original.toJson());
    final entries = [
      ArchiveBundleEntry('阵型', 'different metadata', [], false, original),
      ArchiveBundleEntry('阵型', 'keep note', ['tag'], true, different),
      ArchiveBundleEntry('别的名字', '', [], false, different),
      ArchiveBundleEntry('阵型', '', [], false, original.copy(sunValue: 2222)),
    ];
    final result = await ArchiveFiles.importEntries(repo, entries);
    check(result.imported == 2 && result.skipped == 2 && result.renamed == 2,
        'mixed duplicate/name conflict result: $result');
    final rows = await repo.listArchives();
    check(rows.length == 3 && rows.map((a) => a.name).toSet().length == 3,
        'unique archive names');
    final imported = rows.singleWhere((a) => a.note == 'keep note');
    check(imported.favorite && imported.tags.single == 'tag',
        'metadata preserved');
    final exported = ArchiveBundle.encode(rows);
    final repeat = await ArchiveFiles.importCollection(repo, exported);
    check(repeat.imported == 0 && repeat.skipped == 3, 'roundtrip skips all');
    final malformed = jsonDecode(exported);
    malformed['archives'].add({'name': 'bad'});
    try {
      await ArchiveFiles.importCollection(repo, jsonEncode(malformed));
      throw StateError('expected malformed rejection');
    } on FormatException {/* Whole file validated before writes. */}
    check(
        (await repo.listArchives()).length == 3, 'invalid file wrote nothing');
    await File('${Directory.systemTemp.path}/pvz-archive-import-report.json').writeAsString(jsonEncode({
      'status': 'pass',
      'checks': [
        'same content skip independent of name',
        'within-file duplicates skip',
        'same name different content renamed',
        'metadata preserved',
        'export/import roundtrip skips all',
        'whole collection validated before writes'
      ],
      'result': result.toString(),
      'names': rows.map((a) => a.name).toList(),
    }));
    stdout.writeln('Archive import checks PASS: $result');
    await repo.close();
    await directory.delete(recursive: true);
    exit(0);
  } catch (e, st) {
    stderr.writeln('$e\n$st');
    await repo.close();
    exit(1);
  }
}
