import 'dart:io';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'package:pvz_formation_editor/storage/native_sqlite.dart';

void main() {
  test(
      'v3 legacy drafts migrate without overwriting collision or linked archive',
      () async {
    final dir = await Directory.systemTemp.createTemp('pvz-v4-migrate-');
    final path = '${dir.path}/db.sqlite';
    var repo = await FormationRepository.open(path);
    try {
      final oldDoc = Formation(sunValue: 1).toJson(),
          draftDoc = Formation(sunValue: 2).toJson();
      await repo.saveArchive(id: 'collision', name: '旧阵', document: oldDoc);
      await repo.setPresetFavorite('original-0', true);
      final d = DraftRecord(
          id: 'collision',
          name: '旧阵',
          mapId: 'pool',
          document: draftDoc,
          revision: 3,
          sourceArchiveId: 'collision');
      await repo.saveDraft(d);
      await repo.close();
      final db = NativeSqlite(path);
      db.query('PRAGMA user_version=3');
      db.close();
      repo = await FormationRepository.open(path);
      expect(await repo.listDrafts(), isEmpty);
      final archives = await repo.listArchives();
      expect(archives.length, 2);
      expect(archives.firstWhere((a) => a.id == 'collision').document, oldDoc);
      final mapped = await repo.archiveForLegacyDraft('collision');
      expect(mapped, isNot('collision'));
      final migrated = archives.firstWhere((a) => a.id == mapped);
      expect(migrated.document, draftDoc);
      expect(migrated.name, '旧阵（2）');
      expect(await repo.listVersions('collision'), isEmpty);
      expect(await repo.listFavoritePresets(), {'original-0'});
      await repo.close();
      repo = await FormationRepository.open(path);
      expect((await repo.listArchives()).length, 2);
      expect(await repo.archiveForLegacyDraft('collision'), mapped);
    } finally {
      await repo.close();
      await dir.delete(recursive: true);
    }
  });
  test(
      'v4 reopens migrate late old-engine drafts without overwriting mapped edits',
      () async {
    final dir = await Directory.systemTemp.createTemp('pvz-late-v4-draft-');
    final path = '${dir.path}/db.sqlite';
    var repo = await FormationRepository.open(path);
    try {
      final first = Formation(sunValue: 1).toJson();
      await repo.saveDraft(DraftRecord(
          id: 'late',
          name: '旧窗口',
          mapId: 'pool',
          document: first,
          revision: 1));
      await repo.close();
      repo = await FormationRepository.open(path);
      expect(await repo.listDrafts(), isEmpty);
      final originalId = await repo.archiveForLegacyDraft('late');
      expect(originalId, 'late');
      // The current app edits its migrated archive while the old process still
      // owns a stale snapshot with the same legacy ID.
      final edited = Formation(sunValue: 9).toJson();
      await repo.saveArchive(
          id: originalId!,
          updateId: originalId,
          name: '当前窗口',
          document: edited);
      final beforeVersions =
          (await repo.listVersions(originalId)).map((v) => v.id).toList();
      final late = Formation(sunValue: 2).toJson();
      await repo.saveDraft(DraftRecord(
          id: 'late', name: '旧窗口', mapId: 'pool', document: late, revision: 2));
      await repo.close();
      repo = await FormationRepository.open(path);
      expect(await repo.listDrafts(), isEmpty);
      final all = await repo.listArchives();
      expect(all.length, 2);
      expect(all.firstWhere((a) => a.id == originalId).document, edited);
      expect(all.firstWhere((a) => a.id == originalId).name, '当前窗口');
      expect((await repo.listVersions(originalId)).map((v) => v.id).toList(),
          beforeVersions);
      final latestId = await repo.archiveForLegacyDraft('late');
      expect(latestId, isNot(originalId));
      expect(all.firstWhere((a) => a.id == latestId).document, late);
      await repo.close();
      repo = await FormationRepository.open(path);
      expect((await repo.listArchives()).length, 2);
      expect(await repo.archiveForLegacyDraft('late'), latestId);
      final db = NativeSqlite(path);
      expect(db.query('PRAGMA user_version').single['user_version'], 4);
      db.close();
    } finally {
      await repo.close();
      await dir.delete(recursive: true);
    }
  });
  test('identical late flush is reused without overwriting metadata or history',
      () async {
    final dir = await Directory.systemTemp.createTemp('pvz-identical-late-');
    final path = '${dir.path}/db.sqlite';
    var repo = await FormationRepository.open(path);
    try {
      final draft = DraftRecord(
          id: 'late',
          name: '旧窗口',
          mapId: 'pool',
          document: Formation().toJson(),
          revision: 1);
      await repo.saveDraft(draft);
      await repo.close();
      repo = await FormationRepository.open(path);
      await repo.updateArchiveMetadata('late', favorite: true);
      await repo.saveDraft(DraftRecord(
          id: draft.id,
          name: draft.name,
          mapId: draft.mapId,
          document: draft.document,
          revision: 2));
      await repo.close();
      repo = await FormationRepository.open(path);
      expect((await repo.listArchives()).length, 1);
      expect((await repo.listArchives()).single.favorite, isTrue);
      expect(await repo.listVersions('late'), isEmpty);
      expect(await repo.listDrafts(), isEmpty);
    } finally {
      await repo.close();
      await dir.delete(recursive: true);
    }
  });
  test('snapshot optimistic guards and metadata preservation are atomic',
      () async {
    final dir = await Directory.systemTemp.createTemp('pvz-archive-guard-');
    final repo = await FormationRepository.open('${dir.path}/db.sqlite');
    try {
      final document = Formation();
      await repo.saveArchive(
          id: 'a',
          name: 'A',
          document: document.toJson(),
          note: 'keep',
          tags: ['tag']);
      await expectLater(
          repo.saveArchive(
              id: 'a',
              updateId: 'a',
              name: 'stale',
              document: document.copy(sunValue: 1).toJson(),
              expectedFingerprint: 'wrong'),
          throwsStateError);
      expect(await repo.listVersions('a'), isEmpty);
      await repo.saveArchive(
          id: 'a',
          updateId: 'a',
          name: 'B',
          document: document.copy(sunValue: 2).toJson(),
          expectedFingerprint: document.fingerprint,
          expectedName: 'A',
          preserveMetadata: true);
      final saved = (await repo.listArchives()).single;
      expect(saved.note, 'keep');
      expect(saved.tags, ['tag']);
      expect((await repo.listVersions('a')).length, 1);
      await expectLater(
          repo.saveArchive(
              id: 'a',
              updateId: 'a',
              name: 'stale',
              document: saved.document,
              expectedName: 'A'),
          throwsStateError);
      expect((await repo.listVersions('a')).length, 1);
    } finally {
      await repo.close();
      await dir.delete(recursive: true);
    }
  });
  test('library rename metadata also retains a restorable previous head',
      () async {
    final dir = await Directory.systemTemp.createTemp('pvz-rename-history-');
    final repo = await FormationRepository.open('${dir.path}/db.sqlite');
    try {
      await repo.saveArchive(
          id: 'a', name: '旧名', document: Formation().toJson());
      await repo.updateArchiveMetadata('a', name: '新名');
      expect((await repo.listVersions('a')).single.name, '旧名');
      await repo.updateArchiveMetadata('a', name: '新名');
      await repo.updateArchiveMetadata('a', favorite: true);
      expect((await repo.listVersions('a')).length, 1);
    } finally {
      await repo.close();
      await dir.delete(recursive: true);
    }
  });
}
