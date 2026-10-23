import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'package:pvz_formation_editor/storage/native_sqlite.dart';

Map<String, dynamic> document([int value = 0]) => {
      'schemaVersion': 1,
      'mapId': 'pool',
      'objects': [
        {'id': 'a', 'row': 2, 'column': 3, 'layer': 0},
        {'id': 'b', 'row': 2, 'column': 3, 'layer': 1, 'width': 2}
      ],
      'value': value
    };
DraftRecord draft(String id, int revision, {String? source}) => DraftRecord(
    id: id,
    name: '测试',
    mapId: 'pool',
    document: document(revision),
    revision: revision,
    sourceArchiveId: source);
void main() {
  late Directory directory;
  late String path;
  late FormationRepository repo;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pvz-storage-');
    path = '${directory.path}/formations.sqlite';
    repo = await FormationRepository.open(path);
  });
  tearDown(() async {
    await repo.close();
    await directory.delete(recursive: true);
  });
  test('persist overlapping and spanning objects across reopen', () async {
    await repo.saveDraft(draft('a', 1));
    await repo.close();
    repo = await FormationRepository.open(path);
    expect((await repo.listArchives()).single.document, document(1));
    expect(await repo.listDrafts(), isEmpty);
  });
  test('serialized writes reject stale revisions and never mix drafts',
      () async {
    final results = await Future.wait([
      repo.saveDraft(draft('a', 3)),
      repo.saveDraft(draft('b', 2)),
      repo.saveDraft(draft('a', 1))
    ]);
    expect(results, [true, true, false]);
    final drafts = await repo.listDrafts();
    expect(drafts.firstWhere((r) => r.id == 'a').revision, 3);
    expect(drafts.firstWhere((r) => r.id == 'b').revision, 2);
  });
  test('thumbnail attaches only to the exact live revision', () async {
    await repo.saveDraft(draft('a', 1));
    expect(await repo.saveDraftThumbnail('a', 1, 'first'), true);
    expect((await repo.listDrafts()).single.thumbnail, 'first');
    await repo.saveDraft(draft('a', 2));
    expect(await repo.saveDraftThumbnail('a', 1, 'stale'), false);
    expect((await repo.listDrafts()).single.thumbnail, isNull);
    await repo.deleteDraft('a');
    expect(await repo.saveDraftThumbnail('a', 2, 'deleted'), false);
    expect(await repo.listDrafts(), isEmpty);
  });
  test('delete tombstone survives reopen and rejects delayed save', () async {
    await repo.saveDraft(draft('a', 1));
    await repo.deleteDraft('a');
    expect(await repo.saveDraft(draft('a', 100)), false);
    await repo.close();
    repo = await FormationRepository.open(path);
    expect(await repo.saveDraft(draft('a', 101)), false);
    expect(await repo.listDrafts(), isEmpty);
  });
  test(
      'archives are isolated, updates retain versions and deletion detaches drafts',
      () async {
    await repo.saveArchive(id: 'archive', name: 'A', document: document(1));
    await repo.saveDraft(draft('draft', 2, source: 'archive'));
    expect((await repo.listArchives()).single.document, document(1));
    await repo.saveArchive(id: 'other', name: 'B', document: document(2));
    expect(
        (await repo.listArchives())
            .firstWhere((a) => a.id == 'archive')
            .document,
        document(1));
    await repo.saveArchive(
        id: 'ignored', updateId: 'archive', name: 'C', document: document(3));
    expect((await repo.listVersions('archive')).single.document, document(1));
    await repo.deleteDraft('draft');
    expect(await repo.listArchives(), hasLength(2));
    await repo.saveDraft(draft('independent', 4, source: 'archive'));
    await repo.deleteArchive('archive');
    final surviving = (await repo.listDrafts()).single;
    expect(surviving.document, document(4));
    expect(surviving.sourceArchiveId, isNull);
  });
  test(
      'restore appends current revision and retains selected history and metadata',
      () async {
    final first = await repo.saveArchive(
        id: 'history',
        name: 'Original',
        note: 'old note',
        tags: ['old'],
        document: document(1));
    await repo.saveArchive(
        id: 'ignored',
        updateId: 'history',
        name: 'Current',
        note: 'new note',
        tags: ['new'],
        document: document(2));
    await repo.updateArchiveMetadata('history', favorite: true);
    final selected = (await repo.listVersions('history')).single;
    final current = (await repo.listArchives()).single;
    final restored = await repo.restoreArchiveVersion(
        archiveId: 'history',
        versionId: selected.id,
        expectedFingerprint: jsonEncode(current.document),
        expectedName: current.name);
    expect(restored.id, first.id);
    expect(restored.createdAt, first.createdAt);
    expect(restored.updatedAt.isAfter(current.updatedAt), isTrue);
    expect(restored.favorite, isTrue);
    expect(restored.name, 'Original');
    expect(restored.note, 'new note');
    expect(restored.tags, ['new']);
    expect(restored.document, document(1));
    final versions = await repo.listVersions('history');
    expect(versions, hasLength(2));
    expect(versions.first.document, document(2));
    expect(versions.first.name, 'Current');
    expect(versions.first.note, 'new note');
    expect(versions.first.tags, ['new']);
    expect(versions.last.id, selected.id);
    expect(versions.last.document, selected.document);
    final repeated = await repo.restoreArchiveVersion(
        archiveId: 'history', versionId: selected.id);
    expect(repeated.updatedAt.isAfter(restored.updatedAt), isTrue);
    final repeatedVersions = await repo.listVersions('history');
    expect(repeatedVersions, hasLength(3));
    expect(repeatedVersions.first.document, document(1));
    expect(repeatedVersions.last.id, selected.id);
    expect(repeatedVersions.map((v) => v.id).toSet(), hasLength(3));
    await repo.close();
    repo = await FormationRepository.open(path);
    expect((await repo.listVersions('history')).map((v) => v.id),
        repeatedVersions.map((v) => v.id));
    expect((await repo.listArchives()).single.document, document(1));
  });

  test(
      'restore followed by save and metadata updates keeps future-clock history ordered',
      () async {
    await repo.saveArchive(
        id: 'history', name: 'Original', document: document(1));
    await repo.saveArchive(
        id: 'ignored',
        updateId: 'history',
        name: 'Current',
        document: document(2));
    final selected = (await repo.listVersions('history')).single;
    await repo.close();
    final future = DateTime.now().millisecondsSinceEpoch + 86400000;
    final sqlite = NativeSqlite(path);
    sqlite.query("UPDATE archives SET updated_at=$future WHERE id='history'");
    sqlite.query(
        "UPDATE archive_versions SET created_at=${future + 10} WHERE archive_id='history'");
    sqlite.close();
    repo = await FormationRepository.open(path);
    final restored = await repo.restoreArchiveVersion(
        archiveId: 'history', versionId: selected.id);
    expect(restored.updatedAt.millisecondsSinceEpoch, greaterThan(future + 10));
    final saved = await repo.saveArchive(
        id: 'ignored',
        updateId: 'history',
        name: 'Current',
        document: document(2));
    expect(saved.updatedAt.isAfter(restored.updatedAt), isTrue);
    var versions = await repo.listVersions('history');
    expect(versions.map((v) => v.document['value']), [1, 2, 1]);
    expect(versions.first.createdAt, saved.updatedAt);
    await repo.updateArchiveMetadata('history', note: 'Newest note');
    var current = (await repo.listArchives()).single;
    expect(current.updatedAt.isAfter(saved.updatedAt), isTrue);
    versions = await repo.listVersions('history');
    expect(versions.map((v) => v.document['value']), [2, 1, 2, 1]);
    expect(versions.first.createdAt, current.updatedAt);
    final metadataUpdated = current.updatedAt;
    await repo.updateArchiveMetadata('history', favorite: true);
    current = (await repo.listArchives()).single;
    expect(current.updatedAt.isAfter(metadataUpdated), isTrue);
    expect(current.favorite, isTrue);
    expect(await repo.listVersions('history'), hasLength(4));
    final newest = await repo.saveArchive(
        id: 'ignored',
        updateId: 'history',
        name: 'Current',
        document: document(3),
        preserveMetadata: true);
    expect(newest.updatedAt.isAfter(current.updatedAt), isTrue);
    versions = await repo.listVersions('history');
    expect(versions.first.createdAt, newest.updatedAt);
    expect(versions.first.note, 'Newest note');
    for (var i = 1; i < versions.length; i++) {
      expect(versions[i - 1].createdAt.isAfter(versions[i].createdAt), isTrue);
    }
  });

  test('restore resolves historical names against other current archives',
      () async {
    await repo.saveArchive(
        id: 'history', name: 'Shared', document: document(1));
    await repo.saveArchive(
        id: 'ignored',
        updateId: 'history',
        name: 'Renamed',
        document: document(2));
    await repo.saveArchive(id: 'other', name: 'Shared', document: document(3));
    final selected = (await repo.listVersions('history')).single;
    final restored = await repo.restoreArchiveVersion(
        archiveId: 'history', versionId: selected.id);
    expect(restored.name, 'Shared（2）');
    expect((await repo.listArchives()).singleWhere((a) => a.id == 'other').name,
        'Shared');
    expect((await repo.listVersions('history')).last.name, 'Shared');
  });

  test(
      'restore rejects missing, foreign and stale versions without changing history',
      () async {
    await repo.saveArchive(id: 'history', name: 'A', document: document(1));
    await repo.saveArchive(
        id: 'ignored', updateId: 'history', name: 'B', document: document(2));
    final selected = (await repo.listVersions('history')).single;
    await repo.saveArchive(id: 'other', name: 'Other', document: document(3));
    final current =
        (await repo.listArchives()).singleWhere((a) => a.id == 'history');
    Future<void> unchanged() async {
      final live =
          (await repo.listArchives()).singleWhere((a) => a.id == 'history');
      expect(live.document, current.document);
      expect(live.name, current.name);
      expect(live.updatedAt, current.updatedAt);
      expect(
          (await repo.listVersions('history')).map((v) => v.id), [selected.id]);
      expect(await repo.listVersions('other'), isEmpty);
    }

    await expectLater(
        repo.restoreArchiveVersion(archiveId: 'history', versionId: 'missing'),
        throwsStateError);
    await unchanged();
    await expectLater(
        repo.restoreArchiveVersion(archiveId: 'other', versionId: selected.id),
        throwsStateError);
    await unchanged();
    await expectLater(
        repo.restoreArchiveVersion(
            archiveId: 'history',
            versionId: selected.id,
            expectedFingerprint: jsonEncode(document(1))),
        throwsStateError);
    await unchanged();
    await expectLater(
        repo.restoreArchiveVersion(
            archiveId: 'history',
            versionId: selected.id,
            expectedName: 'stale'),
        throwsStateError);
    await unchanged();
    await expectLater(
        repo.restoreArchiveVersion(
            archiveId: 'missing', versionId: selected.id),
        throwsStateError);
    await unchanged();
    await repo.deleteArchive('history');
    await expectLater(
        repo.restoreArchiveVersion(
            archiveId: 'history', versionId: selected.id),
        throwsStateError);
    expect((await repo.listArchives()).map((a) => a.id), ['other']);
    expect(await repo.listVersions('history'), isEmpty);
  });

  test('failed archive update leaves snapshot and version history intact',
      () async {
    await repo.saveArchive(id: 'a', name: 'A', document: document());
    await expectLater(
        repo.saveArchive(
            id: 'x',
            updateId: 'a',
            name: 'broken',
            document: {'schemaVersion': 'invalid'}),
        throwsFormatException);
    expect((await repo.listArchives()).single.name, 'A');
    expect(await repo.listVersions('a'), isEmpty);
  });
  test(
      'SQLite write failure rolls back version insertion and remains recoverable',
      () async {
    await repo.saveArchive(id: 'a', name: 'A', document: document(1));
    await repo.close();
    var sqlite = NativeSqlite(path);
    sqlite.query(
        "CREATE TRIGGER deny_update BEFORE UPDATE ON archives BEGIN SELECT RAISE(ABORT, 'simulated disk write failure'); END");
    sqlite.close();
    repo = await FormationRepository.open(path);
    await expectLater(
        repo.saveArchive(
            id: 'unused', updateId: 'a', name: 'B', document: document(2)),
        throwsStateError);
    expect((await repo.listArchives()).single.document, document(1));
    expect(await repo.listVersions('a'), isEmpty);
    await repo.close();
    sqlite = NativeSqlite(path);
    sqlite.query('DROP TRIGGER deny_update');
    sqlite.close();
    repo = await FormationRepository.open(path);
    await repo.saveArchive(
        id: 'unused', updateId: 'a', name: 'B', document: document(2));
    expect((await repo.listVersions('a')).single.document, document(1));
  });
  test('failed restore rolls back appended snapshot and permits retry',
      () async {
    await repo.saveArchive(id: 'history', name: 'Old', document: document(1));
    await repo.saveArchive(
        id: 'ignored',
        updateId: 'history',
        name: 'Current',
        document: document(2));
    final selected = (await repo.listVersions('history')).single;
    final current = (await repo.listArchives()).single;
    await repo.close();
    var sqlite = NativeSqlite(path);
    sqlite.query(
        "CREATE TRIGGER deny_restore BEFORE UPDATE ON archives BEGIN SELECT RAISE(ABORT, 'simulated restore failure'); END");
    sqlite.close();
    repo = await FormationRepository.open(path);
    await expectLater(
        repo.restoreArchiveVersion(
            archiveId: 'history', versionId: selected.id),
        throwsStateError);
    expect((await repo.listArchives()).single.document, current.document);
    expect((await repo.listArchives()).single.updatedAt, current.updatedAt);
    expect(
        (await repo.listVersions('history')).map((v) => v.id), [selected.id]);
    await repo.close();
    sqlite = NativeSqlite(path);
    sqlite.query('DROP TRIGGER deny_restore');
    sqlite.close();
    repo = await FormationRepository.open(path);
    final restored = await repo.restoreArchiveVersion(
        archiveId: 'history', versionId: selected.id);
    expect(restored.document, document(1));
    expect(await repo.listVersions('history'), hasLength(2));
  });
  test('late draft save clears a deleted archive fingerprint', () async {
    await repo.saveArchive(id: 'source', name: 'A', document: document());
    await repo.deleteArchive('source');
    await repo.saveDraft(DraftRecord(
        id: 'late',
        name: 'L',
        mapId: 'pool',
        document: document(),
        revision: 1,
        sourceArchiveId: 'source',
        savedFingerprint: 'obsolete'));
    final record = (await repo.listDrafts()).single;
    expect(record.sourceArchiveId, isNull);
    expect(record.savedFingerprint, isNull);
  });
  test('metadata and quoted Unicode JSON round trip', () async {
    await repo.saveArchive(
        id: "a'b", name: "名'称", note: '备注', tags: ['炮位'], document: document());
    await repo.updateArchiveMetadata("a'b", favorite: true, tags: ['新']);
    final archive = (await repo.listArchives()).single;
    expect(archive.name, "名'称");
    expect(archive.tags, ['新']);
    expect(archive.favorite, true);
  });
  test('version-zero database migrates without deleting data', () async {
    await repo.saveDraft(draft('a', 1));
    await repo.close();
    final sqlite = NativeSqlite(path);
    sqlite.query('PRAGMA user_version=0');
    sqlite.close();
    repo = await FormationRepository.open(path);
    expect((await repo.listArchives()).single.id, 'a');
    expect(await repo.listDrafts(), isEmpty);
    expect(await repo.archiveForLegacyDraft('a'), 'a');
  });
  test('v1 migration preserves legacy snapshots as independent archives',
      () async {
    await repo.saveDraft(draft('migrated', 1));
    await repo.close();
    final sqlite = NativeSqlite(path);
    sqlite.query('ALTER TABLE drafts DROP COLUMN saved_fingerprint');
    sqlite.query('PRAGMA user_version=1');
    sqlite.close();
    repo = await FormationRepository.open(path);
    expect((await repo.listArchives()).single.document, document(1));
    expect(await repo.listDrafts(), isEmpty);
    await repo.saveDraft(DraftRecord(
        id: 'migrated',
        name: 'M',
        mapId: 'pool',
        document: document(2),
        revision: 2,
        savedFingerprint: 'snapshot-2'));
    await repo.close();
    repo = await FormationRepository.open(path);
    final migratedId = await repo.archiveForLegacyDraft('migrated');
    expect(
        (await repo.listArchives())
            .firstWhere((a) => a.id == migratedId)
            .document,
        document(2));
    expect(await repo.listDrafts(), isEmpty);
  });
  test('future schema and malformed stored document fail explicitly', () async {
    await repo.saveDraft(draft('a', 1));
    await repo.close();
    var sqlite = NativeSqlite(path);
    sqlite.query('PRAGMA user_version=999');
    sqlite.close();
    await expectLater(FormationRepository.open(path), throwsStateError);
    sqlite = NativeSqlite(path);
    sqlite.query('PRAGMA user_version=2');
    sqlite.query("UPDATE drafts SET document='broken'");
    sqlite.close();
    repo = await FormationRepository.open(path);
    await expectLater(repo.listArchives(), throwsFormatException);
  });
  test('invalid database file is not replaced or silently reset', () async {
    final corruptPath = '${directory.path}/broken.sqlite';
    await File(corruptPath).writeAsString('not a sqlite database');
    await expectLater(FormationRepository.open(corruptPath), throwsStateError);
    expect(await File(corruptPath).readAsString(), 'not a sqlite database');
  });
}
