// Run without the flutter test runner's local server socket:
// /tmp/pvz-flutter-sdk/bin/cache/dart-sdk/bin/dart \
//   /tmp/pvz-flutter-sdk/bin/cache/dart-sdk/bin/snapshots/frontend_server.dart.snapshot \
//   --sdk-root /tmp/pvz-flutter-sdk/bin/cache/artifacts/engine/common/flutter_patched_sdk \
//   --target=flutter --packages .dart_tool/package_config.json \
//   --output-dill /tmp/pvz-renderer-smoke.dill tool/render_smoke.dart
// /tmp/pvz-flutter-sdk/bin/cache/artifacts/engine/darwin-x64/flutter_tester \
//   --disable-vm-service --run-forever --enable-software-rendering \
//   /tmp/pvz-renderer-smoke.dill
// Adjust SDK paths/engine architecture for another machine.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/shovel_targets.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await OriginalAssets.ensureLoaded();
    for (final map in BoardMap.all) {
      final g = BoardGeometry(Formation(mapId: map.id));
      for (var r = 0; r < map.rows; r++) {
        for (var c = 0; c < map.columns; c++) {
          check(g.hit(g.cellCenter(r, c)) == (r, c),
              '${map.id} center hit $r,$c');
        }
      }
      check(g.hit(const Offset(-1, -1)) == null, 'outside hit');
    }
    final roof = BoardGeometry(Formation(mapId: 'roof'));
    check(
        (roof.cellCenter(0, 0).dy - roof.cellCenter(0, 5).dy - 100).abs() <
            .001,
        'measured roof column delta');
    check(roof.cellCenter(0, 5).dy == roof.cellCenter(0, 8).dy,
        'roof flat after column 6');
    final scaleHit = Formation(pieces: [
      Piece(id: 'low', type: 'pea', row: 1, col: 1, layer: 10, scale: 3),
      Piece(id: 'top', type: 'sunflower', row: 1, col: 1, layer: 20)
    ]);
    final hitGeometry = BoardGeometry(scaleHit);
    check(hitGeometry.hitPieces(hitGeometry.cellCenter(1, 1)).first.id == 'top',
        'hit top layer first');
    check(
        hitGeometry.hitPieces(hitGeometry.cellCenter(1, 2)).single.id == 'low',
        'hit scaled object outside logical cell');
    for (final map in ['pool', 'roof']) {
      final pot = Piece(id: 'pot', type: 'pot', row: 1, col: 2, layer: 0);
      final bare = Formation(mapId: map);
      final planted = bare.copy(pieces: [pot]);
      final bareGeometry = BoardGeometry(bare);
      final plantedGeometry = BoardGeometry(planted);
      for (final type in ['pea', 'pumpkin', 'coffee', 'ladder']) {
        for (final col in [2, 3]) {
          final piece =
              Piece(id: type, type: type, row: 1, col: col, layer: 10);
          final expected = col == 2 && ['pea', 'pumpkin'].contains(type)
              ? const Offset(0, -5)
              : Offset.zero;
          check(
              plantedGeometry.pieceCenter(piece) -
                      bareGeometry.pieceCenter(piece) ==
                  expected,
              '$map/$type/$col pot lift stays local and respects object kind');
        }
      }
      final removed = BoardGeometry(planted.copy(pieces: []));
      final plant = Piece(id: 'plant', type: 'pea', row: 1, col: 2, layer: 10);
      check(removed.pieceCenter(plant) == bareGeometry.pieceCenter(plant),
          'new document does not reuse old pot positions');
    }
    final stacked = Formation(pieces: [
      Piece(id: 'pea', type: 'pea', row: 1, col: 2, layer: 10),
      Piece(id: 'shell', type: 'pumpkin', row: 1, col: 2, layer: 20),
      Piece(id: 'ladder', type: 'ladder', row: 1, col: 2, layer: 30),
      Piece(id: 'cob', type: 'cob', row: 1, col: 1, layer: 10),
      Piece(id: 'other', type: 'pea', row: 2, col: 2, layer: 10),
    ]);
    final stackPoint = BoardGeometry(stacked).cellCenter(1, 2);
    check(
        ShovelTargets.at(stacked, stackPoint, '普通植物')
                .containsAll({'pea', 'cob'}) &&
            ShovelTargets.at(stacked, stackPoint, '普通植物').length == 2,
        'category shovel includes spanning plants and excludes other rows');
    final shellTargets = ShovelTargets.at(stacked, stackPoint, '南瓜');
    check(
        shellTargets.length == 2 &&
            shellTargets.containsAll({'shell', 'ladder'}),
        'category shovel removes shell attachments');
    check(ShovelTargets.at(stacked, const Offset(-1, -1), '全部').isEmpty,
        'category shovel outside the board');
    final empty = Formation(display: const {});
    final bytes = await exportPng(empty, multiplier: 2, background: false);
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    check(image.width == 1600 && image.height == 1200, 'PNG dimensions');
    final data = await image.toByteData();
    check(data!.buffer.asUint8List().every((b) => b == 0),
        'transparent PNG excludes helpers');
    image.dispose();
    codec.dispose();
    final halfCodec = await ui.instantiateImageCodec(
        await exportPng(empty, multiplier: .5, background: false));
    final halfImage = (await halfCodec.getNextFrame()).image;
    check(halfImage.width == 400 && halfImage.height == 300,
        'original half-size export');
    halfImage.dispose();
    halfCodec.dispose();
    final formation = Formation(display: const {}, pieces: [
      Piece(id: 'c', type: 'cob', row: 0, col: 0, layer: 10),
      Piece(id: 'l', type: 'lily', row: 0, col: 0, layer: 0),
    ]);
    final png = await exportPng(formation, background: false);
    final filledCodec = await ui.instantiateImageCodec(png);
    final filled = (await filledCodec.getNextFrame()).image;
    final raw = (await filled.toByteData())!.buffer.asUint8List();
    final g = BoardGeometry(formation);
    final first = g.cellCenter(0, 0), second = g.cellCenter(0, 1);
    int alphaAt(Offset p) =>
        raw[(p.dy.round() * filled.width + p.dx.round()) * 4 + 3];
    check(alphaAt(first) > 0 && alphaAt(second) > 0, 'cannon spans two cells');
    filled.dispose();
    filledCodec.dispose();
    final translucent = Formation(display: const {}, pieces: [
      Piece(
          id: 'alpha', type: 'cob', row: 1, col: 1, layer: 10, effects: {'半透明'})
    ]);
    final alphaCodec = await ui
        .instantiateImageCodec(await exportPng(translucent, background: false));
    final alphaImage = (await alphaCodec.getNextFrame()).image;
    final alphaPixels = (await alphaImage.toByteData())!.buffer.asUint8List();
    final ag = BoardGeometry(translucent),
        ac = ag.pieceCenter(translucent.pieces.single);
    final alphaIndex =
        ((ac.dy + ag.cellHeight * .2).round() * alphaImage.width +
                    ac.dx.round()) *
                4 +
            3;
    check((alphaPixels[alphaIndex] - 128).abs() <= 1,
        'object half-transparency retained in PNG');
    alphaImage.dispose();
    alphaCodec.dispose();
    stdout.writeln(
        'PASS: geometry, transparent PNG helpers, 2x dimensions, cross-cell cannon');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
