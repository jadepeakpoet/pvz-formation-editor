import 'dart:io';
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
