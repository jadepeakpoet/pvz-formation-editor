// Real-engine regression: static boards stay clear; growth uses exact source tiles.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';

Future<List<int>> render(Formation document, List<GrowthEffect> effects) async {
  final recorder = ui.PictureRecorder();
  BoardPainter(
          document: document,
          growthEffects: effects,
          background: false,
          helpers: false)
      .paint(Canvas(recorder), const Size(800, 600));
  final picture = recorder.endRecording();
  final image = await picture.toImage(800, 600);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = List<int>.of(
      bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  image.dispose();
  picture.dispose();
  return result;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await OriginalAssets.ensureLoaded();
    final doc = Formation(display: const {'泥土': true});
    if ((await render(doc, const [])).any((b) => b != 0)) {
      throw StateError(
          'Default static board must not contain growth particles');
    }
    final sheet = OriginalAssets.image('image/GrowPlant.png')!;
    final raw = (await sheet.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final original =
        raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    for (final water in [false, true]) {
      for (var frame = 0; frame < 6; frame++) {
        final row = water ? 2 : 0;
        final effect = GrowthEffect(row: row, col: 0, frame: frame);
        final pixels = await render(doc, [effect]);
        final left = 50, top = water ? 310 : 140;
        for (var y = 0; y < 34; y++) {
          for (var x = 0; x < 61; x++) {
            for (var channel = 0; channel < 4; channel++) {
              final source =
                  (((water ? 34 : 0) + y) * sheet.width + frame * 61 + x) * 4 +
                      channel;
              final actual = ((top + y) * 800 + left + x) * 4 + channel;
              if ((original[source] - pixels[actual]).abs() > 1) {
                throw StateError(
                    'Source tile mismatch water=$water frame=$frame at $x,$y channel$channel');
              }
            }
          }
        }
      }
    }
    final hidden = await render(doc.copy(display: const {'泥土': false}),
        const [GrowthEffect(row: 2, col: 0, frame: 2)]);
    if (hidden.any((b) => b != 0)) {
      throw StateError('Soil toggle must hide explicit growth frames');
    }
    stdout.writeln(
        'PASS 12 source growth tiles, exact placement, empty static board, soil toggle');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
