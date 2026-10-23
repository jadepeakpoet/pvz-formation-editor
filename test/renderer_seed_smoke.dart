// Real-engine regression: duplicate normal/imitater seeds use distinct source cards.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await OriginalAssets.ensureLoaded();
    final document = Formation(
        seedSlots: const ['pea', 'pea'], imitaterSeedSlots: const {1});
    final png = await exportPng(document);
    final codec = await ui.instantiateImageCodec(png);
    final rendered = (await codec.getNextFrame()).image;
    final bytes =
        (await rendered.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final pixels =
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    var checked = 0;
    for (var index = 0; index < 2; index++) {
      final path = OriginalAssets.cardPath('pea', imitater: index == 1)
          .replaceFirst('assets/original/', '');
      final card = OriginalAssets.image(path)!;
      final data = (await card.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final original =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final rect = BoardPainter.seedSlotBounds(index);
      if (rect.left != 89 + index * 51 ||
          rect.top != 8 ||
          rect.width != 50 ||
          rect.height != 70) {
        throw StateError('Source card CSS anchor/stride mismatch');
      }
      for (var y = 0; y < 70; y++) {
        for (var x = 0; x < 50; x++) {
          final source = (y * 50 + x) * 4;
          if (original[source + 3] != 255) continue;
          final target =
              ((rect.top.toInt() + y) * 800 + rect.left.toInt() + x) * 4;
          for (var channel = 0; channel < 4; channel++) {
            if ((original[source + channel] - pixels[target + channel]).abs() >
                1) {
              throw StateError(
                  'Source seed card mismatch slot $index pixel $x,$y channel$channel');
            }
          }
          checked++;
        }
      }
    }
    if (checked < 5000) {
      throw StateError('Insufficient opaque card pixels checked');
    }
    final grayPath = OriginalAssets.cardPath('pea', imitater: true)
        .replaceFirst('assets/original/', '');
    final grayAsset = OriginalAssets.images.remove(grayPath);
    try {
      final fallbackPng = await exportPng(document);
      final fc = await ui.instantiateImageCodec(fallbackPng);
      final fi = (await fc.getNextFrame()).image;
      final fb = (await fi.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      final source = (await OriginalAssets.image('image/Card/Peashooter.png')!
              .toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      final rect = BoardPainter.seedSlotBounds(1);
      var samples = 0;
      for (var y = 0; y < 70; y++) {
        for (var x = 0; x < 50; x++) {
          final s = (y * 50 + x) * 4;
          if (source[s + 3] != 255) continue;
          final t = ((rect.top.toInt() + y) * 800 + rect.left.toInt() + x) * 4;
          final expected = (source[s] * .2126 +
                  source[s + 1] * .7152 +
                  source[s + 2] * .0722)
              .round();
          for (var c = 0; c < 3; c++) {
            if ((fb[t + c] - expected).abs() > 2) {
              throw StateError('Missing gray card fallback incorrect');
            }
          }
          samples++;
        }
      }
      if (samples < 3000) throw StateError('Insufficient fallback coverage');
      await File('/tmp/pvz-parity-seed-fallback.png').writeAsBytes(fallbackPng);
      fi.dispose();
      fc.dispose();
    } finally {
      if (grayAsset != null) OriginalAssets.images[grayPath] = grayAsset;
    }
    File('/tmp/pvz-parity-seed-cards.png').writeAsBytesSync(png);
    rendered.dispose();
    codec.dispose();
    stdout.writeln(
        'PASS normal+imitater same seed, $checked source card pixels, source89/51 spacing, 50x70 dimensions and missing-gray fallback');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
