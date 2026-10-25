import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/layouts.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';

// Input and expected placements transcribed from original-site browser probes.
const richInput = '0,0 1 1 0 0 0,21 1 1 0 0 0,1E 1 1 0 0 1,'
    '3 2 2 0 0 0,1E 2 2 0 0 1,10 3 3 0 0 0,2A 3 3 1 0 0,'
    '1E 3 3 0 0 1,17 5 5 0 0 0,21 5 5 0 0 0,1E 5 5 0 0 0';

void main() {
  final reference = jsonDecode(File('test/fixtures/cannon_support_reference.json').readAsStringSync()) as Map;
  for (final raw in reference['cases'] as List) {
    final testCase = raw as Map;
    final mapId = testCase['map'] as String;
    final baseType = testCase['baseType'] as String;
    final action = testCase['action'] as String;
    test('source cannon support removal: $mapId / $baseType / $action', () {
      final map = BoardMap.all.singleWhere((m) => m.id == mapId);
      final pieces = <Piece>[
        for (var row = 0; row < map.rows; row++) ...[
          for (final col in [0, 2, 7]) ...[
            Piece(id: 'c-$row-$col', type: 'cob', row: row, col: col, layer: 10),
            for (final cell in [col, col + 1])
              Piece(id: 'b-$row-$cell', type: baseType, row: row, col: cell,
                  layer: 0, frameRow: baseType == 'pot' ? 1 : 0,
                  frameCol: 1, effects: {'模仿者'}),
          ],
          Piece(id: 'other-$row', type: baseType, row: row, col: 5, layer: 0),
        ],
      ];
      final base = Formation(mapId: mapId, pieces: pieces);
      final before = jsonEncode(base.toJson());
      final result = OriginalActions.apply(base, action);
      final expectedRemoved = {for (final cell in testCase['removed'] as List)
        'b-${cell[0]}-${cell[1]}'};
      expect(base.pieces.map((p) => p.id).toSet().difference(result.pieces.map((p) => p.id).toSet()),
          expectedRemoved);
      for (final piece in result.pieces) {
        expect(piece.toJson(), base.pieces.singleWhere((p) => p.id == piece.id).toJson());
      }
      expect(jsonEncode(base.toJson()), before);
      expect(OriginalActions.apply(result, action).toJson(), result.toJson());
    });
  }
  test('one-click lily leaves aquatic plants and their existing bases untouched', () {
    final plants = [
      for (final entry in ['cattail', 'tangle', 'seashroom'].asMap().entries)
        Piece(id: entry.value, type: entry.value, row: 2, col: entry.key, layer: 10,
            frameRow: 1, frameCol: 1, effects: {'模仿者'}),
    ];
    final shells = [
      for (var col = 0; col < 3; col++)
        Piece(id: 'shell-$col', type: 'pumpkin', row: 2, col: col, layer: 20),
    ];
    final existing = Piece(id: 'existing-lily', type: 'lily', row: 2, col: 0,
        layer: 0, frameCol: 2, effects: {'模仿者'});
    final base = Formation(mapId: 'pool', pieces: [
      ...plants, ...shells, existing,
      Piece(id: 'pea', type: 'pea', row: 3, col: 0, layer: 10),
      Piece(id: 'cob', type: 'cob', row: 3, col: 2, layer: 10),
    ]);
    final result = OriginalActions.apply(base, '荷叶', random: Random(4));
    for (final original in [...plants, ...shells, existing]) {
      expect(result.pieces.singleWhere((p) => p.id == original.id).toJson(), original.toJson());
    }
    expect(result.pieces.where((p) => p.type == 'lily').map((p) => (p.row, p.col)).toSet(),
        {(2, 0), (3, 0), (3, 2), (3, 3)});
    expect(base.pieces.length, 9);
  });

  test('ordinary ladders target land pumpkins in source columns without requiring nuts', () {
    final base = Formation(mapId: 'pool', pieces: [
      for (var col = 0; col < 9; col++)
        Piece(id: 'shell-$col', type: 'pumpkin', row: 0, col: col, layer: 20),
      Piece(id: 'water-shell', type: 'pumpkin', row: 2, col: 3, layer: 20),
      Piece(id: 'bare-nut', type: 'wallnut', row: 1, col: 3, layer: 10),
      Piece(id: 'ladder', type: 'ladder', row: 0, col: 2, layer: 25, scale: .8),
    ]);
    final result = OriginalActions.apply(base, '搭梯');
    expect(result.pieces.where((p) => p.type == 'ladder').map((p) => (p.row, p.col)).toSet(),
        {for (var col = 1; col <= 5; col++) (0, col)});
    expect(result.pieces.singleWhere((p) => p.id == 'ladder').toJson(), base.pieces.last.toJson());
    expect(result.pieces.where((p) => p.type != 'ladder').map((p) => p.toJson()),
        base.pieces.where((p) => p.type != 'ladder').map((p) => p.toJson()));
    expect(OriginalActions.apply(result, '搭梯').toJson(), result.toJson());
  });

  test('original flowerpot action supports planted land cells only', () {
    final base = WebsiteCodec.decode(richInput);
    final result = OriginalActions.apply(base, '花盆', random: Random(7));
    expect(
        result.pieces
            .where((p) => p.type == 'pot')
            .map((p) => (p.row, p.col, p.frameRow))
            .toSet(),
        {(0, 0, 1), (1, 1, 1), (4, 4, 1)});
    expect(
        result.pieces
            .where((p) => p.type == 'pot')
            .every((p) => p.frameCol >= 0 && p.frameCol < 2),
        isTrue);
    expect(result.pieces.length, base.pieces.length + 1);
    expect(OriginalActions.apply(result, '花盆').pieces.length,
        result.pieces.length);
  });

  test('original lily action does not fill unoccupied water cells', () {
    final base = WebsiteCodec.decode(richInput);
    final result = OriginalActions.apply(base, '荷叶', random: Random(7));
    expect(
        result.pieces
            .where((p) => p.type == 'lily')
            .map((p) => (p.row, p.col))
            .toSet(),
        {(2, 2)});
    expect(
        result.pieces
            .where((p) => p.type == 'lily')
            .every((p) => p.frameRow == 0 && p.frameCol >= 0 && p.frameCol < 3),
        isTrue);
    expect(result.pieces.length, base.pieces.length);
    expect(OriginalActions.apply(Formation(), '荷叶').pieces, isEmpty);
  });

  test('original ladders target wallnuts and tallnuts, not other pumpkins', () {
    final base = WebsiteCodec.decode(richInput);
    final result = OriginalActions.apply(base, '搭梯');
    expect(
        result.pieces
            .where((p) => p.type == 'ladder')
            .map((p) => (p.row, p.col))
            .toSet(),
        {(1, 1), (4, 4)});
    expect(OriginalActions.apply(result, '搭梯').pieces.length,
        result.pieces.length);
  });

  test('smart ladders cover land white pumpkins and remove all other ladders',
      () {
    final base = WebsiteCodec.decode(richInput);
    final whiteCells = base.pieces
        .where((p) => p.type == 'pumpkin' && p.effects.contains('模仿者'))
        .map((p) => (p.row, p.col))
        .toSet();
    expect(whiteCells, {(0, 0), (1, 1), (2, 2)});
    final result = OriginalActions.apply(base, '智能搭梯');
    expect(
        result.pieces
            .where((p) => p.type == 'ladder')
            .map((p) => (p.row, p.col))
            .toSet(),
        {(0, 0), (1, 1)});
    expect(
        result.pieces.where((p) => p.type != 'ladder').map((p) => p.toJson()),
        base.pieces.map((p) => p.toJson()));
    final repeated = OriginalActions.apply(result, '智能搭梯');
    expect(repeated.toJson(), result.toJson());
    final ordinary = OriginalActions.apply(base, '搭梯');
    final combined = OriginalActions.apply(ordinary, '智能搭梯');
    expect(
        combined.pieces
            .where((p) => p.type == 'ladder')
            .map((p) => (p.row, p.col))
            .toSet(),
        {(0, 0), (1, 1)});
    final retained =
        ordinary.pieces.singleWhere((p) => p.type == 'ladder' && p.row == 1);
    expect(combined.pieces.singleWhere((p) => p.id == retained.id).toJson(),
        retained.toJson());
    expect(
        combined.pieces.any((p) => p.type == 'ladder' && p.row == 4), isFalse);
  });

  test(
      'smart ladders clean water, bare cells, normal shells and orphan ladders',
      () {
    Piece shell(String id, int row, int col, {bool white = true}) => Piece(
        id: id,
        type: 'pumpkin',
        row: row,
        col: col,
        layer: 20,
        effects: white ? {'模仿者'} : {});
    Piece ladder(String id, int row, int col) =>
        Piece(id: id, type: 'ladder', row: row, col: col, layer: 25);
    final base = Formation(mapId: 'pool', pieces: [
      shell('land', 0, 0),
      shell('new-land', 4, 4),
      shell('water', 2, 2),
      shell('normal', 1, 1, white: false),
      ladder('keep', 0, 0),
      ladder('duplicate', 0, 0),
      ladder('wet', 2, 2),
      ladder('plain', 1, 1),
      ladder('orphan', 5, 5),
    ]);
    final before = base.toJson();
    final result = OriginalActions.apply(base, '智能搭梯');
    final ladders = result.pieces.where((p) => p.type == 'ladder').toList();
    expect(ladders.map((p) => (p.row, p.col)).toSet(), {(0, 0), (4, 4)});
    expect(ladders.length, 2);
    expect(ladders.first.id, 'keep');
    expect(base.toJson(), before);
    expect(
        result.pieces.where((p) => p.type != 'ladder').map((p) => p.toJson()),
        base.pieces.where((p) => p.type != 'ladder').map((p) => p.toJson()));
    expect(OriginalActions.apply(result, '智能搭梯').toJson(), result.toJson());
    final bare = Formation(mapId: 'greenhouseRestricted', pieces: [
      shell('bare', 0, 4),
      ladder('bare-ladder', 0, 4),
      shell('valid', 0, 3),
    ]);
    expect(
        OriginalActions.apply(bare, '智能搭梯')
            .pieces
            .where((p) => p.type == 'ladder')
            .map((p) => (p.row, p.col)),
        [(0, 3)]);
    final noTargets = Formation(
        mapId: 'allWater',
        pieces: [shell('wet', 0, 0), ladder('wet-ladder', 0, 0)]);
    expect(
        OriginalActions.apply(noTargets, '智能搭梯')
            .pieces
            .where((p) => p.type == 'ladder'),
        isEmpty);
  });

  test('support removal leaves boards without cannons unchanged', () {
    final base = WebsiteCodec.decode(richInput);
    for (final action in ['碾花盆', '炸荷叶']) {
      expect(WebsiteCodec.encode(OriginalActions.apply(base, action)),
          WebsiteCodec.encode(base));
    }
    final broken = OriginalActions.apply(base, '破南瓜');
    expect(
        broken.pieces
            .where((p) => p.type == 'pumpkin')
            .every((p) => p.frameRow == 2),
        isTrue);
  });

  test('non-cannon support frames and bare nuts remain unchanged',
      () {
    final base = WebsiteCodec.decode('0,0 1 1 0 0 0,21 1 1 1 1 0,21 2 2 1 1 0,'
        '10 3 3 0 2 0,2A 3 3 1 0 0,3 5 5 0 0 0,17 6 6 0 0 0');
    for (final action in ['搭梯', '碾花盆', '炸荷叶']) {
      expect(WebsiteCodec.encode(OriginalActions.apply(base, action)),
          WebsiteCodec.encode(base),
          reason: action);
    }
  });

  test('original support probes cover lone pumpkin and both cannon cells', () {
    final base = WebsiteCodec.decode('0,1E 1 1 0 0 0,2F 2 2 0 0 0,2F 3 3 0 0 0,'
        '3 5 5 0 0 0,1E 5 5 0 0 0,17 6 6 0 0 0,1E 6 6 0 0 1');
    expect(
        OriginalActions.apply(base, '花盆')
            .pieces
            .where((p) => p.type == 'pot')
            .map((p) => (p.row, p.col))
            .toSet(),
        {(0, 0), (1, 1), (1, 2), (4, 4), (5, 5)});
    expect(
        OriginalActions.apply(base, '荷叶')
            .pieces
            .where((p) => p.type == 'lily')
            .map((p) => (p.row, p.col))
            .toSet(),
        {(2, 2), (2, 3)});
    expect(
        OriginalActions.apply(base, '搭梯')
            .pieces
            .where((p) => p.type == 'ladder')
            .map((p) => (p.row, p.col))
            .toSet(),
        {(4, 4), (5, 5)});
  });

  test('original non-upgrade whitening excludes gloom and gatling', () {
    final base = WebsiteCodec.decode(richInput);
    final white = OriginalActions.imitate(base, '非紫卡植物');
    expect(
        white.pieces
            .where((p) => p.effects.contains('模仿者'))
            .map((p) => p.type)
            .toSet(),
        {'pea', 'pot', 'pumpkin', 'wallnut', 'lily', 'tallnut'});
    final all = OriginalActions.imitate(base, '全部植物');
    expect(all.pieces.every((p) => p.effects.contains('模仿者')), isTrue);
    final translucent = Piece(
        id: 'p', type: 'pumpkin', row: 0, col: 0, layer: 20, effects: {'半透明'});
    expect(
        OriginalActions.imitate(Formation(pieces: [translucent]), '南瓜')
            .pieces
            .single
            .effects,
        {'半透明', '模仿者'});
  });

  test('pool preset cells match original checked rows and columns', () {
    const map = BoardMap('pool', '白天泳池', 6, 9, waterRows: [2, 3]);
    final expected = <String, (List<int>, List<int>)>{
      '陆路': ([0, 1, 4, 5], [0, 1, 2, 3, 4, 5, 6, 7, 8]),
      '水路': ([2, 3], [0, 1, 2, 3, 4, 5, 6, 7, 8]),
      '后置炮': ([0, 1, 4, 5], [3]),
      '前置炮': ([0, 1, 4, 5], [4]),
      '超前置炮': ([0, 1, 4, 5], [6]),
      '底线炮': ([0, 1, 4, 5], [0]),
      '水路前场': ([2, 3], [6, 7, 8]),
      '水路56列': ([2, 3], [4, 5]),
    };
    for (final entry in expected.entries) {
      expect(
          OriginalSelection.cells(map, entry.key),
          {
            for (final row in entry.value.$1)
              for (final col in entry.value.$2) (row, col)
          },
          reason: entry.key);
    }
    expect(OriginalSelection.cells(map, '全部').length, 54);
  });
}
