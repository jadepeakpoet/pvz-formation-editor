// Source MakeFog geometry + independent CPU alpha-mask composition.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}
Future<ui.Image> render(void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(800, 600);
  picture.dispose();
  return image;
}
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await OriginalAssets.ensureBoardImages("", []);
    final fog = OriginalAssets.image('image/fog.jpg')!;
    final mask = OriginalAssets.image('image/fog_.jpg')!;
    final colors = (await fog.toByteData())!.buffer.asUint8List();
    final masks = (await mask.toByteData())!.buffer.asUint8List();
    final cache = <String, ui.Image>{};
    Future<ui.Image> tileImage(FogTile tile) async {
      final key = '${tile.maskFrame}:${tile.textureFrame}';
      if (cache.containsKey(key)) return cache[key]!;
      final rgba = Uint8List(210 * 190 * 4);
      for (var y = 0; y < 190; y++) {
        for (var x = 0; x < 210; x++) {
          final target = (y * 210 + x) * 4;
          final source = (y * fog.width + tile.textureFrame * 210 + x) * 4;
          final alpha = masks[(y * mask.width + tile.maskFrame * 210 + x) * 4];
          for (var channel = 0; channel < 3; channel++) {
            rgba[target + channel] = (colors[source + channel] * alpha / 255).round();
          }
          rgba[target + 3] = alpha;
        }
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(rgba, 210, 190, ui.PixelFormat.rgba8888, done.complete);
      return cache[key] = await done.future;
    }
    final base = Formation(mapId: 'fog', fogColumns: 4, display: {'迷雾': true});
    final layout = FogGeometry(base);
    check(layout.tiles.length == 35, 'Four columns must include five overlapping tile strips');
    check(layout.tiles.first.rect == const Rect.fromLTWH(388, 20, 210, 190),
        'Fog must use source origin rather than x480/y80 stretched rectangle');
    check(layout.tiles.first.opacity == .78 * .78, 'Leading strip source alpha mismatch');
    final tiles = layout.tiles;
    final images = <FogTile, ui.Image>{};
    for (final tile in tiles) {
      images[tile] = await tileImage(tile);
    }
    final expected = await render((canvas) {
      for (final tile in tiles) {
        canvas.drawImage(images[tile]!, tile.rect.topLeft,
            Paint()..color = Colors.white.withOpacity(tile.opacity));
      }
    });
    final actual = await render((canvas) => BoardPainter(
        document: base, background: false, helpers: false).paint(canvas, const Size(800, 600)));
    final actualBytes = (await actual.toByteData())!.buffer.asUint8List();
    final expectedBytes = (await expected.toByteData())!.buffer.asUint8List();
    var maximumDifference = 0;
    for (var i = 0; i < actualBytes.length; i++) {
      final delta = (actualBytes[i] - expectedBytes[i]).abs();
      if (delta > maximumDifference) maximumDifference = delta;
    }
    // Windows software rasterizer differs by up to 4/255 from the CPU mask;
    // verified against the unchanged renderer before the lazy-loading change.
    check(maximumDifference <= 4, 'GPU fog differs from independent CPU mask by $maximumDifference');
    check(actualBytes[(100 * 800 + 380) * 4 + 3] == 0, 'Area left of fog must remain clear');
    check(actualBytes[(90 * 800 + 450) * 4 + 3] > 0, 'Source cloud area unexpectedly empty');
    check(actualBytes[(20 * 800 + 388) * 4 + 3] < 30, 'Mask corner must be transparent, not black');
    for (final columns in [0, 1, 4, 9, 10]) {
      final tiles = FogGeometry(base.copy(fogColumns: columns)).tiles;
      check(tiles.length == (columns == 0 ? 0 : (columns + 1) * 7), 'Incorrect strip count for $columns');
    }
    final torch = Piece(id: 'torch', type: 'torch', row: 2, col: 7, layer: 10);
    final torchLayout = FogGeometry(base.copy(pieces: [torch]));
    check(torchLayout.cleared.containsAll({(1, 7), (2, 6), (2, 7), (2, 8), (2, 9), (3, 7)}) &&
        !torchLayout.cleared.contains((1, 6)), 'Torch must clear a cross and the last edge strip');
    final lantern = Piece(id: 'lamp', type: 'plantern', row: 2, col: 6, layer: 10);
    final lanternLayout = FogGeometry(base.copy(pieces: [lantern]));
    check(lanternLayout.cleared.contains((0, 5)) && !lanternLayout.cleared.contains((0, 3)) &&
        lanternLayout.cleared.contains((2, 9)), 'Plantern must clear source rounded 5x7 region');
    final folder = await Directory('/tmp/pvz-fog-rendering').create(recursive: true);
    for (final example in [base, base.copy(pieces: [torch, lantern])]) {
      final screenshot = await render((canvas) => BoardPainter(document: example)
          .paint(canvas, const Size(800, 600)));
      final bytes = (await screenshot.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      await File('${folder.path}/${example.pieces.isEmpty ? 'fog' : 'cleared'}.png').writeAsBytes(bytes);
      screenshot.dispose();
    }
    for (final image in [...cache.values, expected, actual]) {
      image.dispose();
    }
    stdout.writeln('PASS source fog geometry, mask alpha CPU comparison (max delta $maximumDifference), leading fade, column counts and torch/plantern clearing');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
