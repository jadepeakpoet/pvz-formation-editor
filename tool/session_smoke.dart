// Real Flutter engine, temporary SQLite. No draft UI: each command is archived.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'package:pvz_formation_editor/storage/native_sqlite.dart';

void check(bool value, String why) {
  if (!value) throw StateError(why);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = <String>[];
  Future<void> test(
      String name,
      Future<void> Function(FormationRepository, String, List<EditorSession>)
          body) async {
    final dir = await Directory.systemTemp.createTemp('pvz-auto-archive-');
    final path = '${dir.path}/library.sqlite';
    final repo = await FormationRepository.open(path);
    final sessions = <EditorSession>[];
    try {
      await body(repo, path, sessions);
      results.add(name);
      stdout.writeln('pass: $name');
    } finally {
      for (final s in sessions) {
        s.dispose();
      }
      await repo.close();
      await dir.delete(recursive: true);
    }
  }

  try {
    await test('blank-deferred-save-and-explicit-unique-names',
        (repo, path, sessions) async {
      final a = EditorSession(repo), b = EditorSession(repo);
      sessions.addAll([a, b]);
      await Future.wait([a.flush(), b.flush()]);
      check((await repo.listArchives()).isEmpty,
          'default empty documents stay transient');
      await Future.wait([a.flush(forceSave: true), b.flush(forceSave: true)]);
      check((await repo.listDrafts()).isEmpty, 'no new draft records');
      check((await repo.listArchives()).length == 2,
          'explicitly saved empty documents archived');
      check({a.name, b.name}.containsAll({'新建阵型', '新建阵型（2）'}),
          'explicit saves keep unique names');
      check(a.matchesArchive && a.saveState == '已保存', 'saved association');
    });
    await test('rapid-command-history-includes-undo-redo-rename',
        (repo, path, sessions) async {
      final s = EditorSession(repo);
      sessions.add(s);
      await s.flush(forceSave: true);
      s.execute('one', s.document.copy(sunValue: 1));
      s.execute('two', s.document.copy(sunValue: 2));
      s.undo();
      s.redo();
      s.rename('重命名');
      await s.flush(forceSave: true);
      check(s.error == null && s.matchesArchive, 'final command persisted');
      final versions = await repo.listVersions(s.sourceArchiveId!);
      check(
          versions.length == 5, 'each of five commands retains previous head');
      check(
          versions.map((v) => v.document['sunValue']).toList().join(',') ==
              '2,1,2,1,9990',
          'exact immutable intermediate history');
      check((await repo.listArchives()).single.name == '重命名',
          'rename same archive');
      check((await repo.listDrafts()).isEmpty, 'history never creates drafts');
    });
    await test('readonly-and-secondary-sessions-do-not-autosave',
        (repo, path, sessions) async {
      final ro = EditorSession(repo, readOnly: true),
          remote = EditorSession(repo, persistDraft: false);
      sessions.addAll([ro, remote]);
      ro.execute('blocked', ro.document.copy(sunValue: 1));
      remote.execute('replica', remote.document.copy(sunValue: 2));
      await Future.wait(
          [ro.flush(forceSave: true), remote.flush(forceSave: true)]);
      check((await repo.listArchives()).isEmpty,
          'nonowning sessions never persist');
    });
    await test('autosave-preserves-user-metadata',
        (repo, path, sessions) async {
      final s = EditorSession(repo);
      sessions.add(s);
      await s.flush(forceSave: true);
      final id = s.sourceArchiveId!;
      await repo.updateArchiveMetadata(id,
          note: 'note', tags: ['tag'], favorite: true);
      s.execute('edit', s.document.copy(sunValue: 50));
      await s.flush(forceSave: true);
      final a = (await repo.listArchives()).single;
      check(a.note == 'note' && a.tags.single == 'tag' && a.favorite,
          'autosave preserves metadata');
    });
    await test('saveas-adopts-canonical-name-without-duplicate-save',
        (repo, path, sessions) async {
      final s = EditorSession(repo);
      sessions.add(s);
      await s.flush(forceSave: true);
      final old = s.sourceArchiveId!;
      final copy = await repo.saveArchive(
          id: 'copy', name: '另存名', document: s.document.toJson());
      await s.markArchived(copy.id, s.document.fingerprint, name: copy.name);
      check(s.name == '另存名' && (await repo.listVersions('copy')).isEmpty,
          'adoption adds no duplicate version');
      s.execute('after saveas', s.document.copy(sunValue: 123));
      await s.flush(forceSave: true);
      check(
          (await repo.listVersions('copy')).length == 1, 'new target history');
      check(
          (await repo.listArchives())
                  .firstWhere((a) => a.id == old)
                  .document['sunValue'] ==
              9990,
          'old target unchanged');
    });
    await test('conflicting-edit-and-rename-do-not-overwrite',
        (repo, path, sessions) async {
      final a = EditorSession(repo);
      sessions.add(a);
      await a.flush(forceSave: true);
      final b = EditorSession(repo,
          document: a.document,
          name: a.name,
          sourceArchiveId: a.sourceArchiveId,
          savedFingerprint: a.savedFingerprint);
      sessions.add(b);
      a.rename('A新名');
      await a.flush(forceSave: true);
      b.execute('stale', b.document.copy(sunValue: 1));
      await b.flush(forceSave: true);
      check(b.error != null && b.document.sunValue == 1,
          'stale in-memory edits retained with error');
      check(
          (await repo.listArchives()).single.name == 'A新名' &&
              (await repo.listArchives()).single.document['sunValue'] == 9990,
          'stale snapshot never overwrites');
    });
    await test('write-failure-keeps-all-snapshots-for-ordered-retry',
        (repo, path, sessions) async {
      final s = EditorSession(repo);
      sessions.add(s);
      await s.flush(forceSave: true);
      final db = NativeSqlite(path);
      db.query(
          "CREATE TRIGGER reject_update BEFORE UPDATE ON archives BEGIN SELECT RAISE(ABORT,'offline'); END");
      s.execute('one', s.document.copy(sunValue: 1));
      s.execute('two', s.document.copy(sunValue: 2));
      await s.flush(forceSave: true);
      check(
          s.error != null &&
              (await repo.listVersions(s.sourceArchiveId!)).isEmpty,
          'failure rollback preserves baseline');
      db.query('DROP TRIGGER reject_update');
      db.close();
      await s.flush(forceSave: true);
      check(
          s.error == null &&
              (await repo.listVersions(s.sourceArchiveId!)).length == 2,
          'retry saves both snapshots');
    });
    await test(
        'persisted-history-restore-reloads-baseline-without-extra-version',
        (repo, path, sessions) async {
      final s = EditorSession(repo);
      sessions.add(s);
      await s.flush(forceSave: true);
      s.execute('edit', s.document.copy(sunValue: 17));
      await s.flush(forceSave: true);
      final restored = await repo.saveArchive(
          id: s.sourceArchiveId!,
          updateId: s.sourceArchiveId,
          name: '恢复名',
          document: Formation(sunValue: 9).toJson(),
          preserveMetadata: true);
      final count = (await repo.listVersions(restored.id)).length;
      await s.reloadSavedArchive(restored);
      await s.flush(forceSave: true);
      check(
          s.document.sunValue == 9 &&
              s.name == '恢复名' &&
              s.canUndo &&
              s.undoDepth == 2 &&
              !s.canRedo,
          'adopt head while retaining open-tab history');
      check((await repo.listVersions(restored.id)).length == count,
          'reload adds no duplicate history');
      s.execute('after restore', s.document.copy(sunValue: 10));
      await s.flush(forceSave: true);
      check(
          s.error == null &&
              (await repo.listVersions(restored.id)).length == count + 1,
          'next edit uses restored optimistic baseline');
    });
    await test('unique-name-increments-existing-fullwidth-suffix',
        (repo, path, sessions) async {
      await repo.saveArchive(
          id: 'a', name: '阵型', document: Formation().toJson());
      await repo.saveArchive(
          id: 'b', name: '阵型（2）', document: Formation().toJson());
      check(await repo.uniqueDocumentName('阵型') == '阵型（3）', 'root suffix');
      check(await repo.uniqueDocumentName('阵型（2）') == '阵型（3）',
          'already suffixed name');
      check(
          await repo.uniqueDocumentName('新建阵型',
                  reservedNames: ['新建阵型', '新建阵型（2）']) ==
              '新建阵型（3）',
          'open tabs reserve names');
    });
    final legacyDir =
        await Directory.systemTemp.createTemp('pvz-session-legacy-');
    final legacyPath = '${legacyDir.path}/db.sqlite';
    var legacyRepo = await FormationRepository.open(legacyPath);
    final legacy = DraftRecord(
        id: 'legacy',
        name: '旧草稿',
        mapId: 'pool',
        document: Formation(sunValue: 13).toJson(),
        revision: 7);
    await legacyRepo.saveDraft(legacy);
    await legacyRepo.close();
    final legacyDb = NativeSqlite(legacyPath);
    legacyDb.query('PRAGMA user_version=3');
    legacyDb.close();
    legacyRepo = await FormationRepository.open(legacyPath);
    final legacySession = EditorSession.fromDraft(legacyRepo, legacy);
    await legacySession.flush(forceSave: true);
    check(
        legacySession.error == null &&
            (await legacyRepo.listArchives()).length == 1 &&
            (await legacyRepo.listDrafts()).isEmpty,
        'legacy session adopts migrated archive without duplicate');
    legacySession.execute(
        'legacy edit', legacySession.document.copy(sunValue: 14));
    await legacySession.flush(forceSave: true);
    check(
        (await legacyRepo.listVersions(legacySession.sourceArchiveId!))
                .length ==
            1,
        'legacy next edit appends archive history');
    legacySession.dispose();
    await legacyRepo.close();
    await legacyDir.delete(recursive: true);
    results.add('legacy-session-adopts-migrated-archive-without-duplicate');
    await File('/tmp/pvz-session-autosave-report.json')
        .writeAsString(jsonEncode({
      'pass': results,
      'draftUI': 'removed',
      'scope':
          'real engine/temporary SQLite; command-level immutable archive history'
    }));
    stdout.writeln('PASS ${results.length} auto-archive session groups');
    exit(0);
  } catch (e, stack) {
    stderr.writeln('$e\n$stack');
    exit(1);
  }
}
