import 'dart:io';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'package:pvz_formation_editor/storage/native_sqlite.dart';

void main() {
  late Directory directory;
  late String path;
  late FormationRepository repo;
  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('pvz-preset-preferences-');
    path = '${directory.path}/library.sqlite';
    repo = await FormationRepository.open(path);
  });
  tearDown(() async {
    await repo.close();
    await directory.delete(recursive: true);
  });
  test('favorite toggles persist across reopen without user archives',
      () async {
    expect(await repo.listFavoritePresets(), isEmpty);
    await repo.setPresetFavorite('original-362', true);
    await repo.setPresetFavorite('future-catalog:item', true);
    await repo.setPresetFavorite('original-362', true);
    await repo.close();
    repo = await FormationRepository.open(path);
    expect(await repo.listFavoritePresets(),
        {'original-362', 'future-catalog:item'});
    expect(await repo.listDrafts(), isEmpty);
    expect(await repo.listArchives(), isEmpty);
    await repo.setPresetFavorite('original-362', false);
    await repo.setPresetFavorite('missing-id', false);
    await repo.close();
    repo = await FormationRepository.open(path);
    expect(await repo.listFavoritePresets(), {'future-catalog:item'});
    final db = NativeSqlite(path);
    expect(
        db.query(
            "SELECT * FROM preset_preferences WHERE preset_id='original-362'"),
        isEmpty);
    db.close();
  });
  test('v2 additive migration preserves drafts archives versions and metadata',
      () async {
    final document = Formation().toJson();
    await repo.saveDraft(DraftRecord(
        id: 'draft',
        name: 'existing draft',
        mapId: 'pool',
        document: document,
        revision: 7));
    await repo.saveArchive(id: 'archive', name: 'before', document: document);
    await repo.saveArchive(
        id: 'ignored', updateId: 'archive', name: 'after', document: document);
    await repo.updateArchiveMetadata('archive',
        favorite: true, note: 'keep', tags: ['tag']);
    final draft = (await repo.listDrafts()).single,
        archive = (await repo.listArchives()).single;
    final versions = await repo.listVersions('archive');
    await repo.close();
    final old = NativeSqlite(path);
    old.query('DROP TABLE preset_preferences');
    old.query('PRAGMA user_version=2');
    old.close();
    repo = await FormationRepository.open(path);
    expect(await repo.listFavoritePresets(), isEmpty);
    expect(await repo.listDrafts(), isEmpty);
    final migrated =
        (await repo.listArchives()).firstWhere((a) => a.id == draft.id);
    expect(migrated.document, draft.document);
    final restored =
        (await repo.listArchives()).firstWhere((a) => a.id == archive.id);
    expect(restored.name, archive.name);
    expect(restored.favorite, isTrue);
    expect(restored.note, 'keep');
    expect(restored.tags, ['tag']);
    expect(restored.createdAt, archive.createdAt);
    expect(restored.updatedAt, archive.updatedAt);
    expect((await repo.listVersions('archive')).map((v) => v.id),
        versions.map((v) => v.id));
    await repo.setPresetFavorite('original-0', true);
    final db = NativeSqlite(path);
    expect(db.query('PRAGMA user_version').single['user_version'], 4);
    db.close();
  });
  test('preset operations never change same-ID user archive or draft',
      () async {
    final document = Formation(sunValue: 42).toJson();
    await repo.saveDraft(DraftRecord(
        id: 'same',
        name: 'draft',
        mapId: 'pool',
        document: document,
        revision: 1));
    await repo.saveArchive(id: 'same', name: 'archive', document: document);
    await repo.setPresetFavorite('same', true);
    await repo.setPresetFavorite('same', false);
    final draft = (await repo.listDrafts()).single,
        archive = (await repo.listArchives()).single;
    expect(draft.name, 'draft');
    expect(draft.document, document);
    expect(archive.name, 'archive');
    expect(archive.favorite, isFalse);
    expect(archive.document, document);
    expect(await repo.listVersions('same'), isEmpty);
  });
  test('queued toggles are ordered and returned sets are independent',
      () async {
    await Future.wait([
      repo.setPresetFavorite('id', true),
      repo.setPresetFavorite('id', false),
      repo.setPresetFavorite('last', true)
    ]);
    final first = await repo.listFavoritePresets();
    expect(first, {'last'});
    first.clear();
    expect(await repo.listFavoritePresets(), {'last'});
  });
  test('opaque quoted Unicode IDs remain literal and invalid IDs reject',
      () async {
    const id = "原始'阵型; DROP TABLE archives;--";
    await repo.setPresetFavorite(id, true);
    expect(await repo.listFavoritePresets(), {id});
    expect(await repo.listArchives(), isEmpty);
    for (final invalid in [
      '',
      '  ',
      'x' * 257,
      'bad\u0000id',
      'bad\nid',
      'bad\u007fid'
    ]) {
      await expectLater(
          repo.setPresetFavorite(invalid, true), throwsFormatException);
      await expectLater(
          repo.setPresetFavorite(invalid, false), throwsFormatException);
    }
    expect(await repo.listFavoritePresets(), {id});
    await repo.setPresetFavorite(id, false);
    expect(await repo.listFavoritePresets(), isEmpty);
  });
}
