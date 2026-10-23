import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'package:pvz_formation_editor/storage/native_sqlite.dart';

Map<String, dynamic> document(String pieceId, {int value = 1}) => {
      'schemaVersion': 1,
      'mapId': 'pool',
      'objects': [
        {
          'id': pieceId,
          'type': 'pea',
          'row': 0,
          'column': 0,
          'layer': 10,
          'effects': [],
          'flipped': false
        }
      ],
      'display': {'卡槽': true},
      'sunValue': value,
    };

void main() {
  late Directory directory;
  late String path;
  late FormationRepository repo;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pvz-archive-dedup-');
    path = '${directory.path}/library.sqlite';
    repo = await FormationRepository.open(path);
  });
  tearDown(() async {
    await repo.close();
    await directory.delete(recursive: true);
  });
  Future<ArchiveRecord> add(String id,
          {String note = '',
          List<String> tags = const [],
          Map<String, dynamic>? doc}) =>
      repo.saveArchive(
          id: id,
          name: '阵型-$id',
          note: note,
          tags: tags,
          document: doc ?? document('piece-$id'));
  void sql(String text) {
    final db = NativeSqlite(path);
    try {
      db.query(text);
    } finally {
      db.close();
    }
  }

  test(
      'read-only plan ignores local object IDs and keeps earliest-modified head unchanged',
      () async {
    await add('a', doc: document('a', value: 0));
    await repo.saveArchive(
        id: 'unused', updateId: 'a', name: '阵型-a', document: document('a'));
    await add('b', doc: document('b', value: 2));
    await repo.saveArchive(
        id: 'unused', updateId: 'b', name: '阵型-b', document: document('b'));
    sql("UPDATE archives SET updated_at=10 WHERE id='a'");
    sql("UPDATE archives SET updated_at=1, created_at=20 WHERE id='b'");
    final before = (await repo.listArchives()).firstWhere((a) => a.id == 'b');
    final plan = await repo.planDuplicateArchives();
    expect(plan.groupsCount, 1);
    expect(plan.removableCount, 1);
    expect(plan.preservedHistoryCount, 2);
    expect(plan.groups.single.keeper.id, 'b');
    expect((await repo.listArchives()).length, 2);
    expect((await repo.listVersions('a')).length, 1);
    final result = await repo.removeDuplicateArchives(plan);
    expect(result.removedCount, 1);
    expect(result.preservedHistoryCount, 2);
    expect(result.redirects, {'a': 'b'});
    final kept = (await repo.listArchives()).single;
    expect(kept.id, 'b');
    expect(kept.name, before.name);
    expect(kept.document, before.document);
    expect(kept.updatedAt, before.updatedAt);
    final history = await repo.listVersions('b');
    expect(history.length, 3);
    expect(
        history.any((v) =>
            v.name == '阵型-a' &&
            jsonEncode(v.document) == jsonEncode(document('a'))),
        true);
    expect(history.map((v) => v.document['sunValue']), containsAll([0, 1, 2]));
    expect((await repo.planDuplicateArchives()).removableCount, 0);
  });

  test('earliest modification decides keeper independently of creation and ID order', () async {
    await add('a');
    await add('z');
    sql("UPDATE archives SET created_at=10, updated_at=100 WHERE id='a'");
    sql("UPDATE archives SET created_at=20, updated_at=50 WHERE id='z'");
    final plan = await repo.planDuplicateArchives();
    expect(plan.groups.single.keeper.id, 'z');
    await repo.removeDuplicateArchives(plan);
    expect((await repo.listArchives()).single.id, 'z');
  });

  test('unchanged saves and metadata keep modification time and history', () async {
    final saved = await add('a', tags: ['标签'], note: '备注');
    sql("UPDATE archives SET updated_at=10 WHERE id='a'");
    for (var i = 0; i < 2; i++) {
      final same = await repo.saveArchive(id: 'unused', updateId: 'a',
          name: saved.name, document: saved.document, note: saved.note, tags: saved.tags);
      expect(same.updatedAt.millisecondsSinceEpoch, 10);
      await repo.updateArchiveMetadata('a', name: saved.name, note: saved.note,
          tags: saved.tags, favorite: false);
      await repo.updateArchiveMetadata('a');
    }
    expect((await repo.listArchives()).single.updatedAt.millisecondsSinceEpoch, 10);
    expect(await repo.listVersions('a'), isEmpty);
    await repo.updateArchiveMetadata('a', favorite: true);
    final changed = (await repo.listArchives()).single;
    expect(changed.updatedAt.millisecondsSinceEpoch, greaterThan(10));
    await repo.updateArchiveMetadata('a', favorite: true);
    expect((await repo.listArchives()).single.updatedAt, changed.updatedAt);
    await repo.updateArchiveMetadata('a', note: '新的备注');
    expect((await repo.listArchives()).single.updatedAt.isAfter(changed.updatedAt), isTrue);
    expect((await repo.listVersions('a')).length, 1);
  });

  test('equal modification times use stable IDs', () async {
    await add('a');
    await add('b');
    sql("UPDATE archives SET created_at=10, updated_at=20 WHERE id='b'");
    sql("UPDATE archives SET created_at=10, updated_at=20 WHERE id='a'");
    expect((await repo.planDuplicateArchives()).groups.single.keeper.id, 'a');
  });

  test(
      'maps, display, appearance, object order and metadata remain significant',
      () async {
    await add('base');
    await add('note', note: '独立备注');
    await add('tags', tags: ['独立标签']);
    await add('fav');
    await repo.updateArchiveMetadata('fav', favorite: true);
    await add('map', doc: {...document('map'), 'mapId': 'day'});
    await add('display', doc: {
      ...document('display'),
      'display': {'卡槽': false}
    });
    final flip = document('flip');
    (flip['objects'] as List).single['flipped'] = true;
    await add('flip', doc: flip);
    final order = document('first');
    (order['objects'] as List)
        .add({'id': 'second', 'type': 'pumpkin', 'row': 0, 'column': 0});
    await add('order-a', doc: order);
    await add('order-b', doc: {
      ...order,
      'objects': (order['objects'] as List).reversed.toList()
    });
    expect((await repo.planDuplicateArchives()).removableCount, 0);
  });

  test('canonical key order merges without ignoring any object content',
      () async {
    await add('a');
    final reordered = document('different-id');
    final reversed =
        Map<String, dynamic>.fromEntries(reordered.entries.toList().reversed);
    await add('b', doc: reversed);
    expect((await repo.planDuplicateArchives()).removableCount, 1);
  });

  test('earliest head wins while newer protected heads survive',
      () async {
    for (final id in ['a', 'b', 'c', 'd']) {
      await add(id);
    }
    sql("UPDATE archives SET created_at=30, updated_at=1 WHERE id='b'");
    sql("UPDATE archives SET created_at=10, updated_at=10 WHERE id='a'");
    sql("UPDATE archives SET created_at=20, updated_at=20 WHERE id='c'");
    final plan =
        await repo.planDuplicateArchives(protectedArchiveIds: {'a', 'c'});
    expect(plan.groups.single.keeper.id, 'b');
    expect(plan.skippedProtectedCount, 2);
    expect(plan.removableCount, 1);
    await repo.removeDuplicateArchives(plan, protectedArchiveIds: {'a', 'c'});
    expect((await repo.listArchives()).map((a) => a.id).toSet(), {'a', 'b', 'c'});
  });

  test(
      'new protection or changed head refuses the complete plan without deletion',
      () async {
    await add('a');
    await add('b');
    final plan = await repo.planDuplicateArchives();
    final removeId = plan.groups.single.duplicates.single.id;
    await expectLater(
        repo.removeDuplicateArchives(plan, protectedArchiveIds: {removeId}),
        throwsStateError);
    expect((await repo.listArchives()).length, 2);
    await repo.updateArchiveMetadata('a', note: '修改后不要合并');
    await expectLater(repo.removeDuplicateArchives(plan), throwsStateError);
    expect((await repo.listArchives()).length, 2);
  });

  test('history-only concurrent changes refuse the plan', () async {
    await add('a');
    await add('b');
    final plan = await repo.planDuplicateArchives();
    sql("INSERT INTO archive_versions SELECT 'late-history',id,name,note,tags,document,999 FROM archives WHERE id='a'");
    await expectLater(repo.removeDuplicateArchives(plan), throwsStateError);
    expect((await repo.listArchives()).length, 2);
    expect((await repo.listVersions('a')).single.id, 'late-history');
  });

  test(
      'history, resume pointer and legacy references move before deleting a head',
      () async {
    await add('a');
    await add('b');
    sql("UPDATE archives SET updated_at=10 WHERE id='a'");
    sql("UPDATE archives SET updated_at=1, created_at=20 WHERE id='b'");
    await repo.rememberOpenedArchive('a');
    sql("INSERT INTO legacy_draft_archives VALUES('legacy-draft','a')");
    final plan = await repo.planDuplicateArchives();
    await repo.removeDuplicateArchives(plan);
    expect((await repo.lastOpenedArchive())!.id, 'b');
    expect(await repo.archiveForLegacyDraft('legacy-draft'), 'b');
    final db = NativeSqlite(path);
    try {
      expect(db.query('PRAGMA foreign_key_check'), isEmpty);
      expect(db.query('PRAGMA quick_check').single.values.single, 'ok');
    } finally {
      db.close();
    }
    await repo.close();
    repo = await FormationRepository.open(path);
    expect((await repo.listArchives()).single.id, 'b');
    expect((await repo.listVersions('b')).single.name, '阵型-a');
  });

  test('failure after moving history rolls back every row and allows retry',
      () async {
    await add('a');
    await add('b');
    sql("UPDATE archives SET updated_at=10 WHERE id='a'");
    sql("UPDATE archives SET updated_at=1, created_at=20 WHERE id='b'");
    await repo.rememberOpenedArchive('a');
    final plan = await repo.planDuplicateArchives();
    sql("CREATE TRIGGER stop_delete BEFORE DELETE ON archives BEGIN SELECT RAISE(ABORT,'blocked'); END");
    await expectLater(repo.removeDuplicateArchives(plan), throwsStateError);
    expect((await repo.listArchives()).length, 2);
    expect(await repo.listVersions('b'), isEmpty);
    expect((await repo.lastOpenedArchive())!.id, 'a');
    sql('DROP TRIGGER stop_delete');
    final result = await repo.removeDuplicateArchives(plan);
    expect(result.removedCount, 1);
  });

  test('plans belong to their repository and no-op plans remain safe',
      () async {
    await add('a');
    final plan = await repo.planDuplicateArchives();
    expect(plan.removableCount, 0);
    expect((await repo.removeDuplicateArchives(plan)).removedCount, 0);
    final other = await FormationRepository.open(':memory:');
    try {
      await expectLater(other.removeDuplicateArchives(plan), throwsStateError);
    } finally {
      await other.close();
    }
  });
  test(
      'real formation comparison keeps appearance, display, cards and object order',
      () async {
    final rich =
        Formation(mapId: 'fog', sunValue: 1234, fogColumns: 4, seedSlots: [
      'pea',
      'pumpkin'
    ], imitaterSeedSlots: {
      0
    }, display: {
      '阳光': true,
      '卡槽': true,
      '迷雾': true
    }, pieces: [
      Piece(
          id: 'first',
          type: 'pea',
          row: 0,
          col: 0,
          layer: 10,
          scale: 1.2,
          opacity: .6,
          frameRow: 1,
          frameCol: 1,
          effects: {'冰冻', '模仿者'},
          flipped: true,
          flippedVertical: true,
          appearance: '轮廓'),
      Piece(id: 'second', type: 'sunflower', row: 1, col: 1, layer: 10),
    ]).toJson();
    Map<String, dynamic> clone() =>
        jsonDecode(jsonEncode(rich)) as Map<String, dynamic>;
    await add('rich-a', doc: rich);
    final same = clone();
    for (final piece in same['objects'] as List) {
      piece['id'] = 'new-${piece['id']}';
    }
    await add('rich-b', doc: same);
    final variants = <void Function(Map<String, dynamic>)>[
      (d) => d['map'] = 'pool',
      (d) => d['sunValue'] = 1235,
      (d) => d['fogColumns'] = 3,
      (d) => (d['display'] as Map)['卡槽'] = false,
      (d) => d['seedSlots'] = ['sunflower', 'pumpkin'],
      (d) => d['imitaterSeedSlots'] = <int>[],
      (d) => d['objects'] = (d['objects'] as List).reversed.toList(),
      for (final entry in <String, dynamic>{
        'scale': 1.3,
        'opacity': .5,
        'frameRow': 2,
        'frameCol': 2,
        'flipped': false,
        'flippedVertical': false,
        'appearance': '默认',
        'effects': <String>['冰冻'],
      }.entries)
        (d) => ((d['objects'] as List).first as Map)[entry.key] = entry.value,
    ];
    for (var i = 0; i < variants.length; i++) {
      final changed = clone();
      variants[i](changed);
      await add('variant-$i', doc: changed);
    }
    final plan = await repo.planDuplicateArchives();
    expect(plan.groupsCount, 1);
    expect(plan.removableCount, 1);
    expect({
      plan.groups.single.keeper.id,
      ...plan.groups.single.duplicates.map((a) => a.id)
    }, {
      'rich-a',
      'rich-b'
    });
  });
}
