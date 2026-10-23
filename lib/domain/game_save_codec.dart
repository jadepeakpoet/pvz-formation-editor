import 'dart:typed_data';
import 'formation.dart';
import 'website_codec.dart';

class GameSaveImport {
  final Formation formation;
  final List<String> warnings;

  /// The file's opaque build-date CRC, not a claimed executable version.
  final int buildDate;
  GameSaveImport(this.formation, List<String> warnings, this.buildDate)
      : warnings = List.unmodifiable(warnings);
}

/// Read-only placement extraction from the original 32-bit PC v2 save schema.
/// This does not load a battle or rewrite the source save. Experimental until
/// an actual Windows 1051 save has been independently accepted.
class GameSaveCodec {
  static const maxBytes = 32 * 1024 * 1024;
  static const _magic = 0xfeeddead;
  static const _boardStart = 0x164;
  static const _boardLength = 0x564c;
  static const _maps = ['day', 'night', 'pool', 'fog', 'roof', 'moonRoof'];

  static GameSaveImport decode(List<int> input) {
    if (input.length > maxBytes || input.length < 24) {
      throw const FormatException('PC 存档为空、过短或超过 32 MiB');
    }
    final reader = _SaveReader(input);
    final header = reader.block(expected: 12);
    if (header.getUint32(0, Endian.little) != _magic ||
        header.getUint32(4, Endian.little) != 2) {
      throw const FormatException(
          '不是支持的 PC 关卡存档；请选择 game*_13.dat，而非 user*.dat');
    }
    final build = header.getUint32(8, Endian.little);
    final board = reader.block(expected: _boardLength);
    int field(int offset) =>
        board.getInt32(offset - _boardStart, Endian.little);
    final scene = field(0x554c), sun = field(0x5560);
    if (scene < 0 || scene >= _maps.length || sun < 0 || sun > 1000000000) {
      throw const FormatException('存档场景或阳光数据无效，可能为其他游戏版本');
    }
    final rows = scene == 2 || scene == 3 ? 6 : 5;
    // Modified terrain cannot be represented faithfully by a standard map.
    for (var row = 0; row < 6; row++) {
      final expectedRow = row >= rows
          ? 0
          : (scene == 2 || scene == 3) && (row == 2 || row == 3)
              ? 2
              : 1;
      if (field(0x5d8 + row * 4) != expectedRow) {
        throw const FormatException('暂不支持此存档的自定义草皮或水路');
      }
      for (var col = 0; col < 9; col++) {
        final expectedCell = expectedRow == 0
            ? 2
            : expectedRow == 2
                ? 3
                : 1;
        if (field(0x168 + (col * 6 + row) * 4) != expectedCell) {
          throw const FormatException('暂不支持此存档的自定义格位地形');
        }
      }
    }
    // DataArrayItem includes its trailing 32-bit generation/index ID.
    final zombies = reader.array(stride: 0x15c);
    final plants = reader.array(stride: 0x14c);
    final projectiles = reader.array(stride: 0x94);
    final coins = reader.array(stride: 0xd4);
    final mowers = reader.array(stride: 0x48);
    final grids = reader.array(stride: 0xec);
    // Particle/reanimation/trail/attachment arrays are framed but intentionally
    // never interpreted as pointers or editor pieces.
    for (var i = 0; i < 6; i++) {
      reader.array();
    }
    if (reader.remaining < 28 ||
        reader.data.getUint32(reader.data.lengthInBytes - 4, Endian.little) !=
            _magic) {
      throw const FormatException('PC 存档尾部缺失或损坏');
    }
    final pieces = <Piece>[];
    void add(String type, int row, int col,
        {bool asleep = false, bool mimic = false}) {
      final spec = ObjectSpec.byId(type);
      if (row < 0 || row >= rows || col < 0 || col + spec.width > 9) {
        throw const FormatException('PC 存档中的布阵格位越界');
      }
      pieces.add(Piece(
          id: 'save-${pieces.length}',
          type: type,
          row: row,
          col: col,
          layer: spec.layer,
          asleep: asleep,
          effects: mimic ? {'模仿者'} : {}));
    }

    for (final plant in plants) {
      bool flag(int offset) => _flag(plant, offset);
      if (flag(0x141) || flag(0x142) || !flag(0x144)) continue;
      var seed = plant.getInt32(0x24, Endian.little);
      final mimicType = plant.getInt32(0x138, Endian.little);
      final mimic = seed == 48 || mimicType == 48;
      if (seed == 48) seed = mimicType;
      if (seed < 0 ||
          seed >= 48 ||
          (mimicType != -1 &&
              mimicType != 48 &&
              plant.getInt32(0x24, Endian.little) != 48)) {
        throw const FormatException('PC 存档包含尚未支持的植物类型或模仿者状态');
      }
      add(WebsiteCodec.plantIds[seed], plant.getInt32(0x1c, Endian.little),
          plant.getInt32(0x28, Endian.little),
          asleep: flag(0x143), mimic: mimic);
    }
    for (final grid in grids) {
      if (_flag(grid, 0x20)) continue;
      final kind = grid.getInt32(8, Endian.little);
      final type =
          const {1: 'grave', 2: 'crater', 3: 'ladder', 11: 'rake'}[kind];
      if (type == null) {
        throw FormatException('PC 存档包含尚未支持的场地物品（类型 $kind）');
      }
      add(type, grid.getInt32(0x14, Endian.little),
          grid.getInt32(0x10, Endian.little));
    }
    final warnings = <String>[
      '实验性 PC 存档导入：仅提取六种标准场地的植物、睡眠、模仿者、墓碑、弹坑、梯子和钉耙。',
      '不恢复波数、血量、冷却、僵尸、子弹、掉落物、小推车或战斗动画；原文件保持不变。',
      '已按原版 32 位存档结构检查，尚未完成真实 Windows 1051 存档互验。',
    ];
    if (zombies.isNotEmpty ||
        projectiles.isNotEmpty ||
        coins.isNotEmpty ||
        mowers.isNotEmpty) {
      warnings.add(
          '此存档含 ${zombies.length} 个僵尸、${projectiles.length} 个子弹、${coins.length} 个掉落物和 ${mowers.length} 辆小推车，均未导入。');
    }
    return GameSaveImport(
        Formation(mapId: _maps[scene], sunValue: sun, pieces: pieces),
        warnings,
        build);
  }

  static bool _flag(ByteData data, int offset) {
    final value = data.getUint8(offset);
    if (value > 1) throw const FormatException('PC 存档布尔字段损坏');
    return value == 1;
  }
}

class _SaveReader {
  final ByteData data;
  int position = 0;
  _SaveReader(List<int> input)
      : data = ByteData.sublistView(Uint8List.fromList(input));
  int get remaining => data.lengthInBytes - position;
  int uint() {
    if (remaining < 4) throw const FormatException('PC 存档截断');
    final result = data.getUint32(position, Endian.little);
    position += 4;
    return result;
  }

  ByteData block({int? expected}) {
    final length = uint();
    if ((expected != null && length != expected) || length > remaining) {
      throw const FormatException('PC 存档结构尺寸不匹配或截断，可能为其他版本');
    }
    final result = ByteData.sublistView(data, position, position + length);
    position += length;
    return result;
  }

  List<ByteData> array({int? stride}) {
    final free = uint(), maxUsed = uint(), size = uint();
    if (maxUsed > 65536 || size > maxUsed || free > maxUsed) {
      throw const FormatException('PC 存档数组计数损坏');
    }
    final bytes = block();
    if (maxUsed == 0) {
      if (bytes.lengthInBytes != 0) throw const FormatException('空数组尺寸无效');
      return [];
    }
    final width = stride ?? bytes.lengthInBytes ~/ maxUsed;
    if (width < 4 ||
        width > 16384 ||
        width % 4 != 0 ||
        bytes.lengthInBytes != maxUsed * width) {
      throw const FormatException('PC 存档数组结构不受支持');
    }
    final live = <ByteData>[];
    for (var i = 0; i < maxUsed; i++) {
      final id = bytes.getUint32((i + 1) * width - 4, Endian.little);
      if ((id & 0xffff0000) != 0) {
        if ((id & 0xffff) != i) throw const FormatException('PC 存档对象索引损坏');
        live.add(ByteData.sublistView(bytes, i * width, (i + 1) * width - 4));
      } else if (id > maxUsed) {
        throw const FormatException('PC 存档空闲索引损坏');
      }
    }
    if (live.length != size) throw const FormatException('PC 存档对象数量不一致');
    return live;
  }
}
