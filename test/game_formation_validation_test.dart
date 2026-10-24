import 'dart:io';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';
import 'package:pvz_formation_editor/platform/game_writes.dart';

void main() {
  test('six-row custom lawn reports unsupported map before coordinate errors', () {
    final target = Formation(mapId: 'day6', pieces: [
      Piece(id: 'sixth', type: 'pea', row: 5, col: 0, layer: 10),
    ]);
    expect(() => GameBridge.validateTarget(target), throwsA(isA<UnsupportedError>()
        .having((e) => e.message, 'message', contains('扩展地图'))));
  });
  test('all standard maps are accepted and six-row pools retain the sixth row', () {
    for (final map in GameBridge.supportedMaps) {
      expect(() => GameBridge.validateTarget(Formation(mapId: map)), returnsNormally);
    }
    expect(() => GameBridge.validateTarget(Formation(pieces: [
      Piece(id: 'sixth', type: 'pea', row: 5, col: 8, layer: 10),
    ])), returnsNormally);
  });
  test('out-of-bounds row and two-cell cannon identify the offending plant', () {
    for (final piece in [
      Piece(id: 'sixth', type: 'pea', row: 5, col: 0, layer: 10),
      Piece(id: 'cannon', type: 'cob', row: 0, col: 8, layer: 10),
    ]) {
      expect(() => GameBridge.validateTarget(Formation(mapId: 'day', pieces: [piece])),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(piece.spec.name))));
    }
  });
  test('invalid target is rejected before reading or writing the live game', () {
    var reads = 0, writes = 0;
    final bridge = GameWrites(Directory.systemTemp,
        read: (_) async { reads++; throw StateError('unexpected read'); },
        write: (_, __, ___) async { writes++; throw StateError('unexpected write'); });
    expect(() => bridge.apply(1051, Formation(mapId: 'day6')), throwsUnsupportedError);
    expect(reads, 0); expect(writes, 0);
  });
}
