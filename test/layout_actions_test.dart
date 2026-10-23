import 'dart:math';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/layouts.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';

// Input and expected placements transcribed from original-site browser probes.
const richInput = '0,0 1 1 0 0 0,21 1 1 0 0 0,1E 1 1 0 0 1,'
    '3 2 2 0 0 0,1E 2 2 0 0 1,10 3 3 0 0 0,2A 3 3 1 0 0,'
    '1E 3 3 0 0 1,17 5 5 0 0 0,21 5 5 0 0 0,1E 5 5 0 0 0';

void main() {
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

  test('smart ladders cover only white pumpkins and preserve existing ladders',
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
        whiteCells);
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
        {...whiteCells, (4, 4)});
    for (final existing in ordinary.pieces.where((p) => p.type == 'ladder')) {
      expect(combined.pieces.singleWhere((p) => p.id == existing.id).toJson(),
          existing.toJson());
    }
  });

  test('crushing and bombing preserve original saved container objects', () {
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

  test('original damage probes retain nondefault support frames and bare nuts',
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
