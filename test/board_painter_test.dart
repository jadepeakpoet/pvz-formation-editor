import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  test('every map cell center maps back, including roof slope', () {
    for (final map in BoardMap.all) {
      final g = BoardGeometry(Formation(mapId: map.id));
      for (var r = 0; r < map.rows; r++) {
        for (var c = 0; c < map.columns; c++) {
          expect(g.hit(g.cellCenter(r, c)), (r, c));
        }
      }
      expect(g.hit(const Offset(-1, -1)), isNull);
    }
  });
  test(
      'PNG size is independent of editor view and background can be transparent',
      () async {
    final document = Formation(display: const {});
    final bytes = await exportPng(document, multiplier: 2, background: false);
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    expect(image.width, 1600);
    expect(image.height, 1200);
    final pixels = await image.toByteData();
    expect(pixels!.buffer.asUint8List().every((b) => b == 0), isTrue,
        reason:
            'an empty transparent export has no grid or coordinate helpers');
    image.dispose();
    codec.dispose();
  });
  test('invalid export multiplier is rejected', () async {
    await expectLater(
        exportPng(Formation(), multiplier: double.nan), throwsArgumentError);
    await expectLater(
        exportPng(Formation(), multiplier: 5), throwsArgumentError);
  });
}
