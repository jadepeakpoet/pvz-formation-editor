import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/layouts.dart';
import 'package:pvz_formation_editor/domain/object_filter.dart';
import 'package:pvz_formation_editor/domain/original_catalog.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

List<dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/parity/$name.json').readAsStringSync())
        as List;
Piece piece(String type) => Piece(
    id: type, type: type, row: 0, col: 0, layer: ObjectSpec.byId(type).layer);
List<String> semantics(Formation f, {bool randomSupport = false}) => f.pieces
    .map((p) => '${p.type}:${p.row}:${p.col}:${p.frameRow}:${randomSupport && [
          'pot',
          'lily'
        ].contains(p.type) ? '*' : p.frameCol}:${p.websiteEffects}:${p.flipped}')
    .toList()
  ..sort();
const input =
    '0,0 1 1 0 0 0,21 1 1 0 0 0,1E 1 1 0 0 1,3 2 2 0 0 0,1E 2 2 0 0 1,10 3 3 0 0 0,2A 3 3 1 0 0,1E 3 3 0 0 1,17 5 5 0 0 0,21 5 5 0 0 0,1E 5 5 0 0 0';
void main() {
  for (final map in OriginalCatalog.maps) {
    test(
        'D-MAP-${map['index']} ${map['name']} source index survives import and project',
        () {
      final f = WebsiteCodec.decode('${map['index']}');
      expect(f.mapId, map['id']);
      expect(WebsiteCodec.encode(f), '${map['index']}');
      expect(ProjectCodec.decode(ProjectCodec.encode(f)).toJson(), f.toJson());
    });
  }
  for (final group in {
    'FORMATION': OriginalCatalog.formations,
    'COB': OriginalCatalog.cobLayouts,
    'GLOOM': OriginalCatalog.gloomLayouts
  }.entries) {
    for (final preset in group.value) {
      test(
          'D-${group.key}-${preset.index} ${preset.name} preserves all captured fields',
          () {
        final f = preset.decode();
        final records =
            preset.source.split(',').skip(preset.partial ? 0 : 1).toList();
        expect(f.pieces.length, records.length);
        for (var i = 0; i < records.length; i++) {
          final fields = records[i].trim().split(RegExp(r'\s+'));
          final p = f.pieces[i];
          expect(p.type,
              WebsiteCodec.typeForIndex(int.parse(fields[0], radix: 16)));
          expect((
            p.row,
            p.col,
            p.frameRow,
            p.frameCol,
            p.websiteEffects
          ), (
            int.parse(fields[1]) - 1,
            int.parse(fields[2]) - 1,
            int.parse(fields[3]),
            int.parse(fields[4]),
            fields[5]
          ));
          expect(p.websiteFields, fields);
        }
        expect(
            ProjectCodec.decode(ProjectCodec.encode(f)).toJson(), f.toJson());
      });
    }
  }
  for (final type in [
    ...WebsiteCodec.plantIds,
    ...WebsiteCodec.extraIds.values
  ]) {
    test('D-OBJECT-$type protocol placement, frames and horizontal side', () {
      final code = WebsiteCodec.indexForType(type).toRadixString(16);
      final f = WebsiteCodec.decode('0,$code 2 3 2 1 0 1 1');
      expect((f.pieces.single.type, f.pieces.single.row, f.pieces.single.col),
          (type, 1, 2));
      expect(f.pieces.single.flipped, isTrue);
      final restored =
          WebsiteCodec.decode(WebsiteCodec.encode(f)).pieces.single;
      expect((restored.frameRow, restored.frameCol, restored.flipped),
          (2, 1, true));
    });
  }
  for (final record in fixture('effects')) {
    test('D-EFFECT-SOURCE-${record['effect']} actual icon+card+board Save', () {
      final f = WebsiteCodec.decode(record['source']);
      final p = f.pieces.single;
      expect(p.effects, {record['effect']});
      expect(p.opacity, record['effect'] == '半透明' ? .5 : 1);
      expect(p.scale, 1);
      expect(p.websitePixelX, 240);
      expect(p.websitePixelY, 94);
      final restored = WebsiteCodec.decode(WebsiteCodec.encode(f));
      expect(restored.pieces.single.effects, p.effects);
      expect(restored.pieces.single.opacity, p.opacity);
      final cleared = p.copy(effects: {});
      expect(cleared.websiteEffects, '0');
      expect(cleared.opacity, 1);
      expect(
          WebsiteCodec.decode(WebsiteCodec.encode(f.copy(pieces: [cleared])))
              .pieces
              .single
              .effects,
          isEmpty);
      final oldJson = p.toJson()..remove('opacity');
      expect(Piece.fromJson(oldJson).opacity, p.opacity);
    });
  }
  test(
      'D-EFFECT-FILTER-ORDER last selected filter wins and survives JSON sorting',
      () {
    for (final pair in [
      ['灰烬', '阴影'],
      ['阴影', '灰烬'],
      ['灰烬', '模仿者'],
      ['模仿者', '我是僵尸']
    ]) {
      final p = piece('pea').copy(effects: pair.toSet());
      final winner = pair.last == '我是僵尸' ? '阴影' : pair.last;
      expect(p.effects, {winner});
      expect(Piece.fromJson(p.toJson()).effects, {winner});
      expect(
          WebsiteCodec.decode(WebsiteCodec.encode(Formation(pieces: [p])))
              .pieces
              .single
              .effects,
          {winner});
    }
  });
  test(
      'D-EFFECT-LEGACY-PIXELS transparency edit upgrades legacy suffix without losing coordinates',
      () {
    final f = WebsiteCodec.decode('0,30 1 1 0 0 0 0 80 75');
    final edited = f.copy(pieces: [
      f.pieces.single.copy(effects: {'半透明'})
    ]);
    final restored =
        WebsiteCodec.decode(WebsiteCodec.encode(edited)).pieces.single;
    expect(restored.opacity, .5);
    expect((restored.websitePixelX, restored.websitePixelY), (80, 75));
  });
  final combinationExpected = [
    {'模仿者', '冰冻'},
    {'冰冻', '魅惑'},
    {'灰烬'},
    {'冰冻', '魅惑', '高亮', '灰烬', '半透明'}
  ];
  for (final entry in fixture('effect-combinations').asMap().entries) {
    test(
        'D-EFFECT-COMBINATION-${entry.key} source filter override and independent opacity',
        () {
      final f = WebsiteCodec.decode(entry.value['saved']);
      expect(f.pieces.single.effects, combinationExpected[entry.key]);
      final saved = WebsiteCodec.encode(f);
      expect(saved.trim(), (entry.value['saved'] as String).trim());
      expect(f.pieces.single.scale, 1);
      expect(f.pieces.single.opacity, entry.key == 3 ? .5 : 1);
    });
  }
  test('D-EFFECT-LEGACY old project remains editable with independent opacity',
      () {
    final p = piece('pea').copy(effects: {'冰冻', '半透明'}, scale: 2);
    final old = p.toJson()..remove('opacity');
    final restored = Piece.fromJson(old);
    expect(restored.opacity, .5);
    expect(restored.scale, 2);
    expect(restored.effects, {'冰冻', '半透明'});
    expect(restored.copy(effects: {}).opacity, 1);
  });
  for (final record in fixture('selection')) {
    test('D-SELECT-${record['label']} source checkbox cross product', () {
      final checked = record['checked'] as List;
      final rows = checked
          .where((e) => (e['id'] as String).startsWith('lRow'))
          .map((e) => int.parse(e['value']) - 1);
      final cols = checked
          .where((e) => (e['id'] as String).startsWith('lCol'))
          .map((e) => int.parse(e['value']) - 1);
      expect(OriginalSelection.cells(Formation().map, record['label']), {
        for (final r in rows)
          for (final c in cols) (r, c)
      });
    });
  }
  test('D-SELECT-ALL all 54 pool cells and unknown rejected', () {
    expect(OriginalSelection.cells(Formation().map, '全部').length, 54);
    expect(() => OriginalSelection.cells(Formation().map, '错误'),
        throwsArgumentError);
  });
  for (final record in fixture('actions')) {
    // Fixture action numbers belong to the original site's fixed menu.
    // Product-only additions must not shift these reference identifiers.
    const sourceActions = ['花盆', '荷叶', '搭梯', '碾花盆', '炸荷叶', '破南瓜'];
    final action = sourceActions[(record['action'] as int) - 1];
    test('D-ACTION-$action against source browser save result', () {
      final actual = OriginalActions.apply(WebsiteCodec.decode(input), action,
          random: Random(42));
      final expected = WebsiteCodec.decode(record['result']);
      expect(semantics(actual, randomSupport: true),
          semantics(expected, randomSupport: true));
      for (final p
          in actual.pieces.where((p) => p.type == 'lily' || p.type == 'pot')) {
        expect(p.frameCol, inInclusiveRange(0, p.type == 'pot' ? 1 : 2));
      }
    });
  }
  for (final record in fixture('flip')) {
    test(
        'D-FLIP-SOURCE-${record['flipX']}-${record['flipY']} save behavior matches browser canvas side',
        () {
      final imported = WebsiteCodec.decode(record['result']);
      final canvas = (record['canvas'] as List).single as String;
      final side =
          int.parse(RegExp(r'side="(\d+)"').firstMatch(canvas)!.group(1)!);
      expect(
          side,
          (record['flipX'] == true ? 1 : 0) +
              (record['flipY'] == true ? 2 : 0));
      // The actual source Save form itself discards side 2/3. Preserve that
      // distinction instead of pretending the serialized protocol supports Y.
      expect(imported.pieces.first.flipped, side == 1);
      expect(imported.pieces.first.flippedVertical, isFalse);
      if (side >= 2) {
        final edited = imported.copy(pieces: [
          imported.pieces.first.copy(flippedVertical: true),
          ...imported.pieces.skip(1)
        ]);
        expect(() => WebsiteCodec.encode(edited), throwsFormatException);
        expect(
            ProjectCodec.decode(ProjectCodec.encode(edited))
                .pieces
                .first
                .flippedVertical,
            isTrue);
      }
    });
  }
  final filters = <String, Set<String>>{
    '全部': {
      'pea',
      'pot',
      'lily',
      'pumpkin',
      'coffee',
      'ladder',
      'grave',
      'rake',
      'zombie',
      'FumeCloud'
    },
    '植物': {'pea', 'pot', 'lily', 'pumpkin', 'coffee'},
    '普通植物': {'pea'},
    '容器': {'pot', 'lily'},
    '南瓜': {'pumpkin'},
    '咖啡豆': {'coffee'},
    '梯子': {'ladder'},
    '墓碑': {'grave'},
    '钉耙': {'rake'},
    '僵尸': {'zombie'},
    '特效': {'FumeCloud'},
    '物品': {'ladder', 'grave', 'rake'},
    '物品及特效': {'ladder', 'grave', 'rake', 'FumeCloud'},
  };
  final objects = filters['全部']!.map(piece).toList();
  for (final entry in filters.entries) {
    test('D-DELETE-${entry.key} selects exact category and retains complement',
        () {
      expect(
          objects
              .where((p) => ObjectFilter.matches(p, entry.key))
              .map((p) => p.type)
              .toSet(),
          entry.value);
      final remaining =
          objects.where((p) => !ObjectFilter.matches(p, entry.key));
      expect(remaining.map((p) => p.type).toSet(),
          filters['全部']!.difference(entry.value));
    });
  }
  for (final scope in ['南瓜', '荷叶', '花盆', '非紫卡植物', '全部植物']) {
    test('D-IMITATE-$scope whitening retains existing effects', () {
      final base = Formation(pieces: [
        for (final type in WebsiteCodec.plantIds)
          piece(type).copy(effects: {'半透明'})
      ]);
      final result = OriginalActions.imitate(base, scope);
      const upgrades = {
        'gatling',
        'doubleSun',
        'gloom',
        'cattail',
        'winter',
        'goldmagnet',
        'spike',
        'cob'
      };
      final targets = scope == '全部植物'
          ? WebsiteCodec.plantIds.toSet()
          : scope == '非紫卡植物'
              ? WebsiteCodec.plantIds.toSet().difference(upgrades)
              : {
                  {'南瓜': 'pumpkin', '荷叶': 'lily', '花盆': 'pot'}[scope]!
                };
      expect(
          result.pieces
              .where((p) => p.effects.contains('模仿者'))
              .map((p) => p.type)
              .toSet(),
          targets);
      expect(result.pieces.every((p) => p.effects.contains('半透明')), isTrue);
    });
  }
  for (final entry in Formation().display.entries) {
    test('D-PERSIST-DISPLAY-${entry.key} SQLite legacy draft migration',
        () async {
      final dir = await Directory.systemTemp.createTemp('pvz-parity-');
      final path = '${dir.path}/test.sqlite';
      var repo = await FormationRepository.open(path);
      try {
        final f = Formation(
            display: {...Formation().display, entry.key: !entry.value},
            seedSlots: ['pea', 'gloom', 'cob']);
        await repo.saveDraft(DraftRecord(
            id: 'case',
            name: entry.key,
            mapId: f.mapId,
            document: f.toJson(),
            revision: 1));
        await repo.close();
        repo = await FormationRepository.open(path);
        expect(await repo.listDrafts(), isEmpty);
        expect(
            Formation.fromJson((await repo.listArchives()).single.document)
                .toJson(),
            f.toJson());
      } finally {
        await repo.close();
        await dir.delete(recursive: true);
      }
    });
  }
  for (final bad in [
    '',
    '26',
    '-1',
    'x',
    '0,FF 1 1 0 0 0',
    '0,0 0 1 0 0 0',
    '0,2F 1 9 0 0 0',
    '0,0 1 1 -1 0 0',
    '0,0 1 1 0 0 2',
    '0,0 1 1 0 0 0 1 2',
    '0,0 1 1 0 0 0,1 1 1 0 0 0'
  ]) {
    test('D-CODEC-ERROR-$bad rejects invalid or lossy records',
        () => expect(() => WebsiteCodec.decode(bad), throwsFormatException));
  }
  final losses = <String, Formation>{
    '卡槽': Formation(seedSlots: ['pea']),
    '雾列': Formation(fogColumns: 1),
    '阳光': Formation(sunValue: 50),
    '垂直翻转': Formation(pieces: [piece('pea').copy(flippedVertical: true)]),
    '缩放': Formation(pieces: [piece('pea').copy(scale: 2)]),
    '未知类型': Formation(pieces: [piece('FumeCloud')]),
  };
  for (final entry in losses.entries) {
    test(
        'D-CODEC-LOSS-${entry.key} refuses silent data loss, project preserves',
        () {
      expect(WebsiteCodec.exportIssues(entry.value), isNotEmpty);
      expect(() => WebsiteCodec.encode(entry.value), throwsFormatException);
      expect(ProjectCodec.decode(ProjectCodec.encode(entry.value)).toJson(),
          entry.value.toJson());
    });
  }
}
