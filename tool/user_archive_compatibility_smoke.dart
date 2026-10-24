// Runs only against SQLite backup copies supplied by the test runner.
import 'dart:convert';
import 'dart:io';
import 'package:pvz_formation_editor/domain/archive_bundle.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/library/archive_files.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final manifest = File(Platform.environment['PVZ_ARCHIVE_COPIES'] ??
      'build/checks/user-archive-compatibility/sources.json');
  final sources = jsonDecode(await manifest.readAsString()) as List;
  final results = <Map<String, dynamic>>[];
  for (final source in sources) {
    final repo = await FormationRepository.open(source['copy'] as String);
    final archives = await repo.listArchives();
    var histories = 0;
    for (final archive in archives) {
      final document = Formation.fromJson(archive.document);
      check(FormationExchange.decode(FormationExchange.encode(document,
          format: FormationFormat.project)).fingerprint == document.fingerprint,
          'Project roundtrip: ${archive.id}');
      final versions = await repo.listVersions(archive.id);
      for (final version in versions) {
        final old = Formation.fromJson(version.document);
        check(FormationExchange.decode(FormationExchange.encode(old,
            format: FormationFormat.project)).fingerprint == old.fingerprint,
            'History roundtrip: ${version.id}');
        histories++;
      }
      final session = EditorSession(repo, id: archive.id, name: archive.name,
          document: document, sourceArchiveId: archive.id,
          savedFingerprint: document.fingerprint);
      final edited = document.copy(sunValue: document.sunValue == 12345 ? 12346 : 12345);
      session.execute('Compatibility edit', edited);
      await session.flush();
      check(session.error == null &&
          Formation.fromJson((await repo.archiveById(archive.id))!.document)
              .fingerprint == edited.fingerprint, 'Autosave: ${archive.id}');
      session.undo();
      await session.flush();
      check(Formation.fromJson((await repo.archiveById(archive.id))!.document)
          .fingerprint == document.fingerprint, 'Undo save: ${archive.id}');
      session.dispose();
    }
    if (archives.isNotEmpty) {
      final exported = ArchiveBundle.encode(await repo.listArchives());
      final temp = await Directory.systemTemp.createTemp('pvz-user-archive-import-');
      final target = await FormationRepository.open('${temp.path}/import.sqlite');
      await ArchiveFiles.importCollection(target, exported);
      final imported = await target.listArchives();
      final unique = archives.map((a) => ArchiveBundle.importFingerprint(
          Formation.fromJson(a.document))).toSet();
      check(imported.length == unique.length, 'Batch import count');
      for (final archive in archives) {
        final matches = imported.where((a) => ArchiveBundle.importFingerprint(
            Formation.fromJson(a.document)) == ArchiveBundle.importFingerprint(
            Formation.fromJson(archive.document)));
        check(matches.isNotEmpty, 'Batch import content');
      }
      await target.close();
    }
    await repo.close();
    final reopened = await FormationRepository.open(source['copy'] as String);
    final reread = await reopened.listArchives();
    check(reread.length == archives.length, 'Reopen count');
    for (final archive in archives) {
      final current = reread.singleWhere((a) => a.id == archive.id);
      check(Formation.fromJson(current.document).fingerprint ==
          Formation.fromJson(archive.document).fingerprint &&
          current.name == archive.name && current.note == archive.note &&
          jsonEncode(current.tags) == jsonEncode(archive.tags) &&
          current.favorite == archive.favorite, 'Reopen data and metadata');
    }
    await reopened.close();
    results.add({'archives': archives.length, 'historicalVersions': histories,
      'status': 'pass'});
  }
  final report = {'status': 'pass', 'databases': results};
  await File('${manifest.parent.path}/report.json').writeAsString(jsonEncode(report));
  stdout.writeln(jsonEncode(report));
  exit(0);
}
