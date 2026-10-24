import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'formation.dart';
import 'website_codec.dart';

/// Independent implementation of PvZ Toolkit RFC1437, not its GPL source.
class ToolkitCodec {
  static const maps = ['day', 'night', 'pool', 'fog', 'roof', 'moonRoof'];
  static const _sleepers = {8, 9, 10, 12, 13, 14, 15, 24, 31, 42};
  static const _special = {'lily', 'pot', 'pumpkin', 'coffee'};

  static List<String> exportIssues(Formation formation) {
    final issues = <String>[];
    final scene = maps.indexOf(formation.mapId);
    if (scene < 0) issues.add('Toolkit 仅支持六种原版场景');
    final rows = scene == 2 || scene == 3 ? 6 : 5;
    final slots = <String>{};
    var rakes = 0;
    for (final p in formation.pieces) {
      final index = WebsiteCodec.plantIds.indexOf(p.type);
      if (index < 0 && !{'grave', 'ladder', 'rake'}.contains(p.type)) {
        issues.add('${p.type}: Toolkit 不支持此对象');
        continue;
      }
      if (p.row < 0 || p.row >= rows || p.col < 0 || p.col >= 9) {
        issues.add('${p.type}: 超出场景范围');
      }
      if (p.scale != 1 ||
          p.opacity != 1 ||
          p.flipped ||
          p.flippedVertical ||
          (p.frameRow != 0 &&
              !(Piece.mushroomTypes.contains(p.type) && p.frameRow == 1)) ||
          p.frameCol != 0 ||
          p.appearance != '默认' ||
          p.websitePixelX != null ||
          p.websitePixelY != null ||
          p.effects.any((e) => e != '模仿者')) {
        issues.add('${p.type}: Toolkit 不支持位置微调、帧、变换或此特效');
      }
      if (p.layer != p.spec.layer) issues.add('${p.type}: Toolkit 不支持自定义层级');
      if (p.asleep &&
          (!_sleepers.contains(index) || !{0, 2, 4}.contains(scene))) {
        issues.add('${p.type}: 当前场景不支持此睡眠状态');
      }
      if (p.effects.contains('模仿者') && index < 0) {
        issues.add('${p.type}: 此对象不能是模仿者');
      }
      if (p.type == 'rake') {
        rakes++;
        if (p.col != 7 ||
            ((scene == 2 || scene == 3) && {2, 3}.contains(p.row))) {
          issues.add('钉耙必须位于第八列的陆地行');
        }
        continue;
      }
      final slot = {'lily', 'pot', 'grave'}.contains(p.type)
          ? 'base'
          : _special.contains(p.type) || p.type == 'ladder'
              ? p.type
              : 'main';
      if (!slots.add('${p.row}:${p.col}:$slot')) {
        issues.add('${p.type}: 同格同层对象重叠');
      }
    }
    if (rakes > 1) issues.add('Toolkit 仅支持一个钉耙');
    if (formation.seedSlots.isNotEmpty) issues.add('Toolkit 不保存选卡');
    if (formation.sunValue != 9990) issues.add('Toolkit 不保存自定义阳光数');
    if (formation.fogColumns != 0) issues.add('Toolkit 不保存自定义雾范围');
    return issues.toSet().toList();
  }

  static String encode(Formation formation) {
    final issues = exportIssues(formation);
    if (issues.isNotEmpty) throw FormatException(issues.join('；'));
    final scene = maps.indexOf(formation.mapId);
    final data = ByteData((scene == 2 || scene == 3 ? 54 : 45) * 2);
    var rake = 0;
    for (final p in formation.pieces) {
      if (p.type == 'rake') {
        rake = p.row + 1;
        continue;
      }
      final offset = (p.row * 9 + p.col) * 2;
      var word = data.getUint16(offset, Endian.little);
      final imitate = p.effects.contains('模仿者');
      switch (p.type) {
        case 'lily':
          word |= 1 << 6;
          if (imitate) word |= 1 << 5;
        case 'pot':
          word |= 2 << 6;
          if (imitate) word |= 1 << 5;
        case 'grave':
          word |= 3 << 6;
        case 'pumpkin':
          word |= 1 << 4;
          if (imitate) word |= 1 << 3;
        case 'coffee':
          word |= 1 << 2;
          if (imitate) word |= 1 << 1;
        case 'ladder':
          word |= 1;
        default:
          word |= (WebsiteCodec.plantIds.indexOf(p.type) + 1) << 10;
          if (imitate) word |= 1 << 9;
          if (!p.asleep) word |= 1 << 8;
      }
      data.setUint16(offset, word, Endian.little);
    }
    final compressed = ZLibEncoder(level: 9).convert(data.buffer.asUint8List());
    return base64.encode(
        [...compressed, (rake << 4) | scene].map((b) => b ^ 0x54).toList());
  }

  static Formation decode(String input) {
    final text = input.trim();
    if (text.length < 4 ||
        text.length > 164 ||
        !RegExp(r'^[A-Za-z0-9+/_-]+={0,2}$').hasMatch(text) ||
        text.length % 4 == 1) {
      throw const FormatException('Toolkit 阵型码 Base64 无效');
    }
    final normalized =
        base64.normalize(text.replaceAll('-', '+').replaceAll('_', '/'));
    final encoded = base64.decode(normalized);
    if (base64.encode(encoded) != normalized ||
        encoded.length > 122 ||
        encoded.length < 9) {
      throw const FormatException('Toolkit 阵型码长度或填充无效');
    }
    final bytes = encoded.map((b) => b ^ 0x54).toList();
    final rs = bytes.removeLast(), scene = rs & 15, rake = rs >> 4;
    if (scene > 5 ||
        rake > (scene == 2 || scene == 3 ? 6 : 5) ||
        ((scene == 2 || scene == 3) && {3, 4}.contains(rake))) {
      throw const FormatException('Toolkit 场景或钉耙行无效');
    }
    _DeflateBoundary(bytes).verify();
    final output = _BoundedBytes();
    try {
      final decoder = ZLibDecoder().startChunkedConversion(output);
      decoder.add(bytes);
      decoder.close();
    } catch (_) {
      throw const FormatException('Toolkit 压缩数据损坏或超限');
    }
    final raw = output.bytes;
    final expected = (scene == 2 || scene == 3 ? 54 : 45) * 2;
    if (raw.length != expected ||
        bytes.length < 6 ||
        bytes[0] != 0x78 ||
        ((bytes[0] << 8) + bytes[1]) % 31 != 0 ||
        (bytes[1] & 32) != 0 ||
        _adler(raw) !=
            ((bytes[bytes.length - 4] << 24) |
                (bytes[bytes.length - 3] << 16) |
                (bytes[bytes.length - 2] << 8) |
                bytes.last)) {
      throw const FormatException('Toolkit 网格长度或 zlib 校验无效');
    }
    final data = ByteData.sublistView(Uint8List.fromList(raw));
    final pieces = <Piece>[];
    void add(String type, int row, int col,
        {bool imitate = false, bool asleep = false}) {
      pieces.add(Piece(
          id: 'toolkit-${pieces.length}',
          type: type,
          row: row,
          col: col,
          layer: ObjectSpec.byId(type).layer,
          asleep: asleep,
          effects: imitate ? {'模仿者'} : {}));
    }

    for (var cell = 0; cell < expected ~/ 2; cell++) {
      final w = data.getUint16(cell * 2, Endian.little);
      final p = w >> 10, b = (w >> 6) & 3;
      if (p > 48 ||
          {17, 31, 34, 36}.contains(p) ||
          (p == 0 && (w & 0x300) != 0) ||
          ((b == 0 || b == 3) && (w & 32) != 0) ||
          ((w & 16) == 0 && (w & 8) != 0) ||
          ((w & 4) == 0 && (w & 2) != 0)) {
        throw const FormatException('Toolkit 网格标志无效');
      }
      final row = cell ~/ 9, col = cell % 9;
      if (b != 0) {
        add(['', 'lily', 'pot', 'grave'][b], row, col, imitate: (w & 32) != 0);
      }
      if (p != 0) {
        add(WebsiteCodec.plantIds[p - 1], row, col,
            imitate: (w & 512) != 0,
            asleep: {0, 2, 4}.contains(scene) &&
                _sleepers.contains(p - 1) &&
                (w & 256) == 0);
      }
      if ((w & 16) != 0) add('pumpkin', row, col, imitate: (w & 8) != 0);
      if ((w & 4) != 0) add('coffee', row, col, imitate: (w & 2) != 0);
      if ((w & 1) != 0) add('ladder', row, col);
    }
    if (rake != 0) add('rake', rake - 1, 7);
    return Formation(mapId: maps[scene], pieces: pieces);
  }

  static int _adler(List<int> bytes) {
    var a = 1, b = 0;
    for (final value in bytes) {
      a = (a + value) % 65521;
      b = (b + a) % 65521;
    }
    return (b << 16) | a;
  }
}

class _BoundedBytes implements Sink<List<int>> {
  final bytes = <int>[];
  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > 108) {
      throw const FormatException('Toolkit 解压超限');
    }
    bytes.addAll(chunk);
  }

  @override
  void close() {}
}

/// Checks the deflate end marker and exact stream boundary: Dart's streaming
/// decoder can emit valid output before discovering a missing trailer/end bit.
class _DeflateBoundary {
  final List<int> bytes;
  int bit = 16;
  _DeflateBoundary(this.bytes);
  int read(int n) {
    if (bit + n > (bytes.length - 4) * 8) {
      throw const FormatException('截断的 deflate');
    }
    var result = 0;
    for (var i = 0; i < n; i++, bit++) {
      result |= ((bytes[bit ~/ 8] >> (bit % 8)) & 1) << i;
    }
    return result;
  }

  Map<int, int> table(List<int> lengths) {
    final counts = List.filled(16, 0), next = List.filled(16, 0);
    for (final l in lengths) {
      if (l > 15) throw const FormatException('Huffman 长度无效');
      if (l > 0) counts[l]++;
    }
    var code = 0;
    for (var i = 1; i <= 15; i++) {
      code = (code + counts[i - 1]) << 1;
      next[i] = code;
      if (code + counts[i] > (1 << i)) {
        throw const FormatException('Huffman 过度订阅');
      }
    }
    final result = <int, int>{};
    for (var symbol = 0; symbol < lengths.length; symbol++) {
      final length = lengths[symbol];
      if (length == 0) continue;
      final value = next[length]++;
      var reversed = 0;
      for (var i = 0; i < length; i++) {
        reversed = (reversed << 1) | ((value >> i) & 1);
      }
      result[(1 << length) | reversed] = symbol;
    }
    return result;
  }

  int symbol(Map<int, int> codes) {
    var code = 0;
    for (var length = 1; length <= 15; length++) {
      code |= read(1) << (length - 1);
      final value = codes[(1 << length) | code];
      if (value != null) return value;
    }
    throw const FormatException('Huffman 码无效');
  }

  void verify() {
    var last = false;
    while (!last) {
      last = read(1) == 1;
      final kind = read(2);
      if (kind == 0) {
        bit = (bit + 7) ~/ 8 * 8;
        final length = read(16);
        if ((length ^ read(16)) != 65535) {
          throw const FormatException('未压缩块长度无效');
        }
        readBytes(length);
        continue;
      }
      if (kind == 3) throw const FormatException('保留 deflate 块');
      late List<int> literals, distances;
      if (kind == 1) {
        literals = List.generate(
            288,
            (i) => i < 144
                ? 8
                : i < 256
                    ? 9
                    : i < 280
                        ? 7
                        : 8);
        distances = List.filled(32, 5);
      } else {
        final nl = read(5) + 257, nd = read(5) + 1, nc = read(4) + 4;
        // RFC1951 code-length alphabet order.
        const canonicalOrder = [
          16,
          17,
          18,
          0,
          8,
          7,
          9,
          6,
          10,
          5,
          11,
          4,
          12,
          3,
          13,
          2,
          14,
          1,
          15
        ];
        final cl = List.filled(19, 0);
        for (var i = 0; i < nc; i++) {
          cl[canonicalOrder[i]] = read(3);
        }
        final ct = table(cl), lengths = <int>[];
        while (lengths.length < nl + nd) {
          final s = symbol(ct);
          if (s < 16) {
            lengths.add(s);
            continue;
          }
          if (s == 16 && lengths.isEmpty) {
            throw const FormatException('重复长度无前项');
          }
          final count = s == 16
              ? read(2) + 3
              : s == 17
                  ? read(3) + 3
                  : read(7) + 11;
          lengths.addAll(List.filled(count, s == 16 ? lengths.last : 0));
          if (lengths.length > nl + nd) throw const FormatException('长度表溢出');
        }
        literals = lengths.sublist(0, nl);
        distances = lengths.sublist(nl);
        if (literals[256] == 0) throw const FormatException('无结束码');
      }
      final lt = table(literals), dt = table(distances);
      while (true) {
        final s = symbol(lt);
        if (s < 256) continue;
        if (s == 256) break;
        if (s > 285) throw const FormatException('保留长度码');
        const extras = [
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          1,
          1,
          1,
          1,
          2,
          2,
          2,
          2,
          3,
          3,
          3,
          3,
          4,
          4,
          4,
          4,
          5,
          5,
          5,
          5,
          0
        ];
        read(extras[s - 257]);
        final d = symbol(dt);
        if (d > 29) throw const FormatException('保留距离码');
        read(d < 4 ? 0 : (d ~/ 2) - 1);
      }
    }
    if ((bit + 7) ~/ 8 != bytes.length - 4) {
      throw const FormatException('deflate 有尾随或缺失数据');
    }
  }

  void readBytes(int count) {
    if (bit + count * 8 > (bytes.length - 4) * 8) {
      throw const FormatException('截断块');
    }
    bit += count * 8;
  }
}
