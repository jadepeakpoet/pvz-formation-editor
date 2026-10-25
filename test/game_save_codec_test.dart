import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/game_save_codec.dart';

// Synthetic primary-schema vectors, not files captured from an actual game.
Uint8List save(
    {int scene = 2,
    int sun = 50,
    int? seed = 42,
    bool asleep = true,
    bool mimic = true,
    int? gridKind = 3,
    bool dead = false,
    bool coinFreeSentinel = false}) {
  final result = BytesBuilder();
  void u(int n) {
    final b = ByteData(4)..setUint32(0, n, Endian.little);
    result.add(b.buffer.asUint8List());
  }

  void block(Uint8List bytes) {
    u(bytes.length);
    result.add(bytes);
  }

  final header = ByteData(12)
    ..setUint32(0, 0xfeeddead, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, 0x12345678, Endian.little);
  block(header.buffer.asUint8List());
  final board = ByteData(0x564c);
  void field(int offset, int value) =>
      board.setInt32(offset - 0x164, value, Endian.little);
  field(0x554c, scene);
  field(0x5560, sun);
  final rows = scene == 2 || scene == 3 ? 6 : 5;
  for (var r = 0; r < 6; r++) {
    final type = r >= rows
        ? 0
        : (scene == 2 || scene == 3) && (r == 2 || r == 3)
            ? 2
            : 1;
    field(0x5d8 + r * 4, type);
    for (var c = 0; c < 9; c++) {
      field(
          0x168 + (c * 6 + r) * 4,
          type == 0
              ? 2
              : type == 2
                  ? 3
                  : 1);
    }
  }
  block(board.buffer.asUint8List());
  void array(int stride, {ByteData? item}) {
    u(item == null ? 0 : 1);
    u(item == null ? 0 : 1);
    u(item == null ? 0 : 1);
    if (item == null) {
      block(Uint8List(0));
      return;
    }
    final record = Uint8List(stride);
    record.setRange(0, item.lengthInBytes, item.buffer.asUint8List());
    ByteData.sublistView(record).setUint32(stride - 4, 0x10000, Endian.little);
    block(record);
  }

  array(0x15c);
  ByteData? plant;
  if (seed != null) {
    plant = ByteData(0x148)
      ..setInt32(0x24, seed, Endian.little)
      ..setInt32(0x28, 2, Endian.little)
      ..setInt32(0x1c, 1, Endian.little)
      ..setInt32(0x138, mimic ? 48 : -1, Endian.little)
      ..setUint8(0x141, dead ? 1 : 0)
      ..setUint8(0x143, asleep ? 1 : 0)
      ..setUint8(0x144, 1);
  }
  array(0x14c, item: plant);
  array(0x94);
  if (coinFreeSentinel) {
    u(0); u(1); u(0);
    final freeCoin = ByteData(0xd8)..setUint32(0xd4, 0xffffffff, Endian.little);
    block(freeCoin.buffer.asUint8List());
  } else {
    array(0xd8);
  }
  array(0x48);
  final grid = gridKind == null
      ? null
      : (ByteData(0xe8)
        ..setInt32(8, gridKind, Endian.little)
        ..setInt32(0x10, 2, Endian.little)
        ..setInt32(0x14, 1, Endian.little));
  array(0xec, item: grid);
  for (var i = 0; i < 6; i++) {
    array(4);
  }
  for (var i = 0; i < 6; i++) {
    block(Uint8List(0));
  }
  u(0xfeeddead);
  return result.takeBytes();
}

void main() {
  test('original 216-byte coin records accept an empty free-list end sentinel', () {
    final input = save(coinFreeSentinel: true), before = [...save(coinFreeSentinel: true)];
    final imported = GameSaveCodec.decode(input);
    expect(imported.formation.pieces.map((p) => p.type), ['gloom', 'ladder']);
    expect(input, before);
  });
  test('schema plant, asleep, mimic, sun, ladder and warnings', () {
    final input = save(), before = [...save()];
    final imported = GameSaveCodec.decode(input);
    expect(imported.buildDate, 0x12345678);
    expect(imported.formation.mapId, 'pool');
    expect(imported.formation.sunValue, 50);
    expect(imported.formation.pieces.map((p) => p.type), ['gloom', 'ladder']);
    final plant = imported.formation.pieces.first;
    expect(plant.row, 1);
    expect(plant.col, 2);
    expect(plant.asleep, isTrue);
    expect(plant.effects, {'模仿者'});
    expect(imported.warnings, isNotEmpty);
    expect(input, before);
  });
  test('six standard scenes and all supported placeable grid types', () {
    for (var scene = 0; scene < 6; scene++) {
      expect(GameSaveCodec.decode(save(scene: scene)).formation.mapId,
          ['day', 'night', 'pool', 'fog', 'roof', 'moonRoof'][scene]);
    }
    for (final pair
        in {1: 'grave', 2: 'crater', 3: 'ladder', 11: 'rake'}.entries) {
      expect(
          GameSaveCodec.decode(save(seed: null, gridKind: pair.key))
              .formation
              .pieces
              .single
              .type,
          pair.value);
    }
    expect(
        GameSaveCodec.decode(save(dead: true, gridKind: null)).formation.pieces,
        isEmpty);
  });
  test('all 48 plants and untransformed imitater map correctly', () {
    for (var seed = 0; seed < 48; seed++) {
      expect(
          GameSaveCodec.decode(
                  save(seed: seed, mimic: false, asleep: false, gridKind: null))
              .formation
              .pieces
              .length,
          1);
    }
    final bytes = save();
    // Header block16 + board length4 + board + zombie empty16 + plants metadata16.
    const plantOffset = 16 + 4 + 0x564c + 16 + 16;
    ByteData.sublistView(bytes)
      ..setInt32(plantOffset + 0x24, 48, Endian.little)
      ..setInt32(plantOffset + 0x138, 42, Endian.little);
    expect(GameSaveCodec.decode(bytes).formation.pieces.first.type, 'gloom');
  });
  test('header/version/sizes/scene/sun/terrain/end marker reject corruption',
      () {
    final changes = <int, int>{
      0: 11,
      4: 0,
      8: 3,
      16: 0,
      20 + 0x554c - 0x164: 6,
      20 + 0x5560 - 0x164: -1,
      20 + 0x5d8 - 0x164: 2,
      20 + 0x168 - 0x164: 3
    };
    for (final change in changes.entries) {
      final bytes = save();
      ByteData.sublistView(bytes)
          .setInt32(change.key, change.value, Endian.little);
      expect(() => GameSaveCodec.decode(bytes), throwsFormatException,
          reason: 'offset ${change.key}');
    }
    final bytes = save();
    bytes.last = 0;
    expect(() => GameSaveCodec.decode(bytes), throwsFormatException);
    expect(() => GameSaveCodec.decode(Uint8List(GameSaveCodec.maxBytes + 1)),
        throwsFormatException);
  });
  test(
      'truncated arrays, bad slotIDs, flags, coordinates and grid objects reject',
      () {
    final original = save();
    for (final length in [0, 12, 16, 100, 0x5660, original.length - 4]) {
      expect(() => GameSaveCodec.decode(original.sublist(0, length)),
          throwsFormatException);
    }
    const plantOffset = 16 + 4 + 0x564c + 16 + 16;
    for (final change in {
      plantOffset - 8: 2,
      plantOffset - 4: 0x150,
      plantOffset + 0x148: 0x10001,
      plantOffset + 0x24: 49,
      plantOffset + 0x28: 9,
      plantOffset + 0x1c: 6
    }.entries) {
      final bytes = save();
      ByteData.sublistView(bytes)
          .setInt32(change.key, change.value, Endian.little);
      expect(() => GameSaveCodec.decode(bytes), throwsFormatException,
          reason: 'offset ${change.key}');
    }
    final badFlag = save();
    badFlag[plantOffset + 0x143] = 2;
    expect(() => GameSaveCodec.decode(badFlag), throwsFormatException);
    expect(
        () => GameSaveCodec.decode(save(gridKind: 7)), throwsFormatException);
  });
}
