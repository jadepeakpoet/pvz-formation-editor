import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/toolkit_codec.dart';

String fixture(List<int> bytes, int rs) => base64.encode([
      ...ZLibEncoder(level: 9).convert(bytes),
      rs
    ].map((b) => b ^ 0x54).toList());
Piece piece(String type,
        {int row = 0,
        int col = 0,
        bool asleep = false,
        Set<String> effects = const {}}) =>
    Piece(
        id: type,
        type: type,
        row: row,
        col: col,
        layer: ObjectSpec.byId(type).layer,
        asleep: asleep,
        effects: effects);

void main() {
  // Independent Python struct.pack('<H') + zlib.compress(level=9), from RFC1437.
  const empty = [
    'LI43NPRBVFRUDlRVVA==',
    'LI43NPRBVFRUDlRVVQ==',
    'LI43NPRLVFRUOFRVVg==',
    'LI43NPRLVFRUOFRVVw==',
    'LI43NPRBVFRUDlRVUA==',
    'LI43NPRBVFRUDlRVUQ=='
  ];
  test('six independently generated RFC empty-grid golden vectors', () {
    for (var i = 0; i < 6; i++) {
      final f = ToolkitCodec.decode(empty[i]);
      expect(f.mapId, ToolkitCodec.maps[i]);
      expect(f.pieces, isEmpty);
      expect(ToolkitCodec.encode(f), empty[i]);
    }
  });
  test('independent dynamic-Huffman deflate and stored blocks accepted', () {
    const dynamicGolden =
        'LI5RlFVQVFRUVMRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRUVFRU1FVUVFRUVFRUVFRUXFQOVFVU';
    expect(ToolkitCodec.decode(dynamicGolden).pieces, isEmpty);
    for (final level in [0, 1, 6, 9]) {
      final payload = [
        ...ZLibEncoder(level: level).convert(List<int>.filled(90, 0)),
        0
      ];
      expect(
          ToolkitCodec.decode(
                  base64.encode(payload.map((b) => b ^ 84).toList()))
              .pieces,
          isEmpty);
    }
    final payload = base64.decode(dynamicGolden).map((b) => b ^ 84).toList();
    payload.insertAll(payload.length - 5, [0, 0, 0, 0]);
    expect(
        () => ToolkitCodec.decode(
            base64.encode(payload.map((b) => b ^ 84).toList())),
        throwsFormatException);
  });
  test('independent little endian layered asleep-mimic and rake golden', () {
    final f = ToolkitCodec.decode('LI43NHRagPs39ExUVBvmVXo2');
    expect(f.mapId, 'pool');
    expect(f.pieces.map((p) => p.type),
        ['lily', 'gloom', 'pumpkin', 'coffee', 'ladder', 'rake']);
    expect(f.pieces.take(5).every((p) => p.row == 2 && p.col == 2), isTrue);
    expect(f.pieces[1].asleep, isTrue);
    expect(f.pieces.take(4).every((p) => p.effects.contains('模仿者')), isTrue);
    expect(f.pieces.last.row, 5);
    expect(f.pieces.last.col, 7);
    expect(ToolkitCodec.encode(f), 'LI43NHRagPs39ExUVBvmVXo2');
  });
  test('all 48 plant slots, awake and imitater semantics', () {
    final types = <String>[];
    // Use codec goldens then ordinary website plants via the stable object catalog.
    for (final spec in ObjectSpec.all) {
      final f = Formation(mapId: 'day', pieces: [piece(spec.id)]);
      if (ToolkitCodec.exportIssues(f).isNotEmpty || spec.id == 'rake') {
        continue;
      }
      types.add(spec.id);
      final result = ToolkitCodec.decode(ToolkitCodec.encode(f));
      expect(result.pieces.single.type, spec.id);
      if (!{'ladder', 'grave'}.contains(spec.id)) {
        final mimic = f.copy(pieces: [
          piece(spec.id, effects: {'模仿者'})
        ]);
        expect(
            ToolkitCodec.decode(ToolkitCodec.encode(mimic))
                .pieces
                .single
                .effects,
            {'模仿者'});
      }
    }
    expect(types.length, 50); // 48 plants + ladder + tombstone.
  });
  test('base64url and unpadded accepted, malformed encodings rejected', () {
    expect(ToolkitCodec.decode(empty[0].replaceAll('=', '')).mapId, 'day');
    for (final text in [
      '',
      'a',
      '!!!!!',
      '${empty[0]}=',
      ' ${empty[0]}x',
      empty[0].replaceFirst('L', 'M'),
      'LI43NPRBVFRUDlRVVB=='
    ]) {
      expect(() => ToolkitCodec.decode(text), throwsFormatException,
          reason: text);
    }
  });
  test(
      'malformed scene, rake, grid lengths, flags, checksum and expansion rejected',
      () {
    for (final rs in [6, 15, 0x60, 0x32, 0x43]) {
      expect(() => ToolkitCodec.decode(fixture(List.filled(90, 0), rs)),
          throwsFormatException);
    }
    for (final length in [0, 88, 92, 1000000]) {
      expect(() => ToolkitCodec.decode(fixture(List.filled(length, 0), 0)),
          throwsFormatException);
    }
    for (final word in [
      49 << 10,
      17 << 10,
      31 << 10,
      34 << 10,
      36 << 10,
      512,
      256,
      32,
      8,
      2,
      0xe0
    ]) {
      final bytes = List.filled(90, 0);
      bytes[0] = word & 255;
      bytes[1] = word >> 8;
      expect(
          () => ToolkitCodec.decode(fixture(bytes, 0)), throwsFormatException,
          reason: '$word');
    }
    final bytes = base64.decode(empty[0]);
    for (var i = 0; i < bytes.length - 1; i++) {
      final changed = [...bytes];
      changed.removeAt(i);
      expect(() => ToolkitCodec.decode(base64.encode(changed)),
          throwsFormatException,
          reason: 'removed byte $i');
    }
  });
  test('unsupported content produces actionable errors rather than loss', () {
    final cases = [
      Formation(mapId: 'day6'),
      Formation(seedSlots: ['pea']),
      Formation(sunValue: 100),
      Formation(fogColumns: 3),
      Formation(pieces: [piece('zombie')]),
      Formation(pieces: [
        piece('pea', effects: {'冰冻'})
      ]),
      Formation(pieces: [piece('pea').copy(opacity: .5)]),
      Formation(pieces: [piece('pea'), piece('pea')]),
      Formation(pieces: [piece('rake')]),
      Formation(pieces: [piece('pea', asleep: true)]),
      Formation(mapId: 'night', pieces: [piece('puff', asleep: true)])
    ];
    for (final f in cases) {
      expect(ToolkitCodec.exportIssues(f), isNotEmpty);
      expect(() => ToolkitCodec.encode(f), throwsFormatException);
    }
  });
  test('sleep survives project JSON and copy without altering existing JSON',
      () {
    final awake = piece('puff');
    expect(awake.toJson().containsKey('asleep'), isFalse);
    final asleep = awake.copy(asleep: true);
    expect(Piece.fromJson(asleep.toJson()).asleep, isTrue);
    expect(asleep.copy(col: 1).asleep, isTrue);
    expect(() => Piece.fromJson({...awake.toJson(), 'asleep': 'yes'}),
        throwsFormatException);
  });
}
