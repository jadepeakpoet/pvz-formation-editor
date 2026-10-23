import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';

void main() {
  test('verified horizontal side imports and exports edited state', () {
    final f = WebsiteCodec.decode('0,0 1 1 0 0 0 1 1,0 1 2 0 0 0 1 0');
    expect(f.pieces.map((p) => p.flipped), [true, false]);
    final changed = f.copy(pieces: [
      f.pieces[0].copy(flipped: false),
      f.pieces[1].copy(flipped: true)
    ]);
    final restored = WebsiteCodec.decode(WebsiteCodec.encode(changed));
    expect(restored.pieces.map((p) => p.flipped), [false, true]);
    final fresh = Formation(pieces: [
      Piece(id: newId(), type: 'pea', row: 0, col: 0, layer: 10, flipped: true)
    ]);
    expect(WebsiteCodec.encode(fresh), '0,0 1 1 0 0 0 1 1 ');
    expect(
        () => WebsiteCodec.encode(fresh
            .copy(pieces: [fresh.pieces.single.copy(flippedVertical: true)])),
        throwsFormatException);
  });

  test('horizontal side updates retain positioned props and legacy coordinates',
      () {
    for (final source in [
      '0,30 1 1 0 0 0 1 0 80 75',
      '0,30 1 1 0 0 0 0 80 75'
    ]) {
      final f = WebsiteCodec.decode(source);
      final flipped = f.copy(pieces: [f.pieces.single.copy(flipped: true)]);
      final restored =
          WebsiteCodec.decode(WebsiteCodec.encode(flipped)).pieces.single;
      expect(restored.flipped, isTrue);
      expect(restored.websitePixelX, 80);
      expect(restored.websitePixelY, 75);
      final reset = WebsiteCodec.decode(WebsiteCodec.encode(
          f.copy(pieces: [restored.copy(flipped: false)]))).pieces.single;
      expect(reset.flipped, isFalse);
      expect(reset.websitePixelX, 80);
    }
  });
  test(
      'real source color mask and named filters replace assumed seven-bit layout',
      () {
    const sources = {
      '模仿者': '1',
      '冰冻': '0010',
      '魅惑': '1000',
      '高亮': '0001',
      '阴影': '0000dropshadow',
      '灰烬': '0000black'
    };
    for (final entry in sources.entries) {
      final f = WebsiteCodec.decode('0,0 1 1 0 0 ${entry.value}');
      expect(f.pieces.single.effects, {entry.key});
      expect(Piece.encodeWebsiteEffects({entry.key}), entry.value);
      expect(WebsiteCodec.decode(WebsiteCodec.encode(f)).pieces.single.effects,
          {entry.key});
      expect(f.pieces.single.copy(effects: {}).websiteEffects, '0');
    }
  });

  test('all additionally verified props and zombies round trip', () {
    for (final entry in WebsiteCodec.extraIds.entries) {
      final code = entry.key.toRadixString(16);
      final f = WebsiteCodec.decode('0,$code 1 1 0 0 0');
      expect(f.pieces.single.type, entry.value);
      expect(WebsiteCodec.decode(WebsiteCodec.encode(f)).pieces.single.type,
          entry.value);
    }
    for (final unverified in [0x5a, 0x5c, 0x64]) {
      expect(WebsiteCodec.typeForIndex(unverified), isNull);
    }
  });
  test('edits override imported appearance and clear obsolete pixel placement',
      () {
    final f = WebsiteCodec.decode('0,30 1 1 0 0 1 1 0 80 75');
    final original = f.pieces.single;
    final edited =
        original.copy(row: 1, col: 2, frameRow: 2, frameCol: 1, effects: {});
    expect(edited.websitePixelX, isNull);
    expect(
        WebsiteCodec.decode(WebsiteCodec.encode(
                f.copy(pieces: [original.copy(websiteEffects: '0')])))
            .pieces
            .single
            .websiteEffects,
        '0');
    final saved = WebsiteCodec.encode(f.copy(pieces: [edited]));
    final restored = WebsiteCodec.decode(saved).pieces.single;
    expect(restored.row, 1);
    expect(restored.col, 2);
    expect(restored.frameRow, 2);
    expect(restored.frameCol, 1);
    expect(restored.websiteEffects, '0');
    expect(restored.websitePixelX, isNull);

    expect(
        WebsiteCodec.exportIssues(f.copy(pieces: [
          original.copy(effects: {'未知效果'})
        ])),
        isNotEmpty);
  });

  test('verified original frames, gray bits and positioned ladder survive save',
      () {
    const source = '0,2A 1 1 1 0 0,30 1 1 0 0 0 1 0 80 75,0 3 1 0 0 0100000';
    final doc = WebsiteCodec.decode(source);
    expect(doc.pieces[0].frameRow, 1);
    expect(doc.pieces[1].type, 'ladder');
    expect(doc.pieces[1].websitePixelX, 80);
    expect(doc.pieces[1].websitePixelY, 75);
    expect(doc.pieces[2].websiteEffects, '0100000');
    final restored = WebsiteCodec.decode(WebsiteCodec.encode(doc));
    expect(restored.pieces[0].frameRow, 1);
    expect(restored.pieces[1].websiteFields, doc.pieces[1].websiteFields);
    expect(restored.pieces[2].websiteEffects, '0100000');
  });

  const realSample =
      '0,0 1 1 0 0 0 1 ,2F 2 3 0 0 0 1 ,10 3 1 0 0 0 1 ,1E 3 1 0 0 0 1 ';
  test('actual website Save sample imports and re-exports exact tokens', () {
    final doc = WebsiteCodec.decode(realSample);
    expect(doc.mapId, 'pool');
    expect(doc.pieces.map((p) => p.type), ['pea', 'cob', 'lily', 'pumpkin']);
    expect(doc.pieces[1].col, 2);
    expect(WebsiteCodec.encode(doc), realSample);
  });
  test('six fields gain verified default seventh field and imitater survives',
      () {
    final doc = WebsiteCodec.decode('2,0 1 1 0 0 1');
    expect(doc.pieces.single.effects, {'模仿者'});
    expect(WebsiteCodec.encode(doc), '2,0 1 1 0 0 1 1 ');
  });
  test('all 48 IDs verified from website DOM fixture map correctly', () {
    // Browser fixture: plant IDs 0..2F placed at distinct cells, then DOM inspected.
    final source =
        '0${List.generate(48, (i) => ',${i.toRadixString(16).toUpperCase()} ${i ~/ 8 + 1} ${i % 8 + 1} 0 0 0 1 ').join()}';
    final doc = WebsiteCodec.decode(source);
    expect(doc.pieces.map((p) => p.type).toList(), [
      'pea',
      'sunflower',
      'cherry',
      'wallnut',
      'potato',
      'snow',
      'chomper',
      'repeater',
      'puff',
      'sunshroom',
      'fume',
      'gravebuster',
      'hypno',
      'scaredy',
      'ice',
      'doom',
      'lily',
      'squash',
      'threepea',
      'tangle',
      'jalapeno',
      'spikeweed',
      'torch',
      'tallnut',
      'seashroom',
      'plantern',
      'cactus',
      'blover',
      'splitpea',
      'starfruit',
      'pumpkin',
      'magnet',
      'cabbage',
      'pot',
      'kernel',
      'coffee',
      'garlic',
      'umbrella',
      'marigold',
      'melon',
      'gatling',
      'doubleSun',
      'gloom',
      'cattail',
      'winter',
      'goldmagnet',
      'spike',
      'cob'
    ]);
    expect(WebsiteCodec.encode(doc), source);
  });
  test('all six verified map codes map in website order', () {
    for (var i = 0; i < 6; i++) {
      expect(WebsiteCodec.decode('$i').mapId, WebsiteCodec.mapIds[i]);
    }
  });
  test('unknown protocol extensions and invalid coordinates reject explicitly',
      () {
    for (final input in [
      '26',
      '99',
      '-1',
      '0,ZZ 1 1 0 0 0',
      '0,0 1 1 0 0 2',
      '0,0 1 1 0 0 0 2',
      '0,0 0 1 0 0 0',
      '2,0 6 1 0 0 0',
      '0,2F 1 9 0 0 0',
      '0,',
      '0,0 1 1 0 0 0,1 1 1 0 0 0'
    ]) {
      expect(() => WebsiteCodec.decode(input), throwsFormatException,
          reason: input);
    }
  });
  Piece piece(String type,
          {int layer = 10,
          Set<String> effects = const {},
          double scale = 1,
          bool flipped = false,
          bool flippedVertical = false,
          String appearance = '默认'}) =>
      Piece(
          id: newId(),
          type: type,
          row: 0,
          col: 0,
          layer: layer,
          effects: effects,
          scale: scale,
          flipped: flipped,
          flippedVertical: flippedVertical,
          appearance: appearance);
  test('removed free board cannot be exported as a website map', () {
    expect(() => WebsiteCodec.encode(Formation(mapId: 'custom')),
        throwsFormatException);
  });
  test('unsupported objects and visual data never silently disappear', () {
    final cases = [
      Formation(display: {'坐标': false}),
      Formation(pieces: [piece('ducky', layer: 40)]),
      Formation(pieces: [
        piece('pea', effects: {'未知效果'})
      ]),
      Formation(pieces: [piece('pea', layer: 11)]),
      Formation(pieces: [piece('pea', scale: 2)]),
      Formation(pieces: [piece('pea', flippedVertical: true)]),
      Formation(pieces: [piece('pea', appearance: '轮廓')]),
      Formation(pieces: [piece('pea'), piece('sunflower')]),
      Formation(pieces: [piece('lily', layer: 0), piece('pot', layer: 0)]),
    ];
    for (final doc in cases) {
      expect(WebsiteCodec.exportIssues(doc), isNotEmpty);
      expect(() => WebsiteCodec.encode(doc), throwsFormatException);
    }
  });
  test('distinct website categories may share a cell', () {
    final doc = Formation(pieces: [
      piece('lily', layer: 0),
      piece('pea'),
      piece('pumpkin', layer: 20),
      piece('coffee', layer: 30)
    ]);
    expect(WebsiteCodec.exportIssues(doc), isEmpty);
    final decoded = WebsiteCodec.decode(WebsiteCodec.encode(doc));
    expect(decoded.pieces.map((p) => p.type),
        ['lily', 'pea', 'pumpkin', 'coffee']);
  });
  test('oversized text and record count are rejected', () {
    expect(() => WebsiteCodec.decode('0${' ' * WebsiteCodec.maxBytes}'),
        throwsFormatException);
    expect(() => WebsiteCodec.decode('0${',0 1 1 0 0 0' * 5001}'),
        throwsFormatException);
  });
}
