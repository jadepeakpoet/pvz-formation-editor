import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final watch = Stopwatch()..start();
    await OriginalAssets.ensureLoaded();
    stdout.writeln(
        'asset load ${watch.elapsedMilliseconds}ms, ${OriginalAssets.images.length} source images');
    check(OriginalAssets.images.isEmpty, "Metadata startup must not decode images");
    await OriginalAssets.ensureTypes(["pea", "sunflower"]);
    final realPath = ((OriginalAssets.sprites['Peashooter']['images'] as List)
        .first as Map)['path'] as String;
    check(OriginalAssets.grayImage('Peashooter', realPath) == null,
        'ensureLoaded must not eagerly generate imitation sprites');

    final decoded = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        Uint8List.fromList([
          100,
          40,
          20,
          255,
          255,
          0,
          0,
          255,
          0,
          0,
          0,
          0,
        ]),
        3,
        1,
        ui.PixelFormat.rgba8888,
        decoded.complete);
    const path = 'test/lazy-imitation';
    OriginalAssets.images[path] = await decoded.future;
    final initialRevision = OriginalAssets.revision.value;
    final ready = Completer<void>();
    void changed() {
      // Requests made while generation is pending share one decode.
      if (OriginalAssets.grayImage('test', path) != null &&
          !ready.isCompleted) {
        ready.complete();
      }
    }

    OriginalAssets.revision.addListener(changed);
    for (var i = 0; i < 20; i++) {
      check(OriginalAssets.grayImage('test', path) == null,
          'pending generation returns no incomplete image');
    }
    await ready.future.timeout(const Duration(seconds: 5));
    OriginalAssets.revision.removeListener(changed);
    final image = OriginalAssets.grayImage('test', path)!;
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    check(rgba[0] == 114 && rgba[1] == 114 && rgba[2] == 114 && rgba[3] == 255,
        'HSL min/max lightness times 1.9, not luminance weighting');
    check(rgba[4] == 242 && rgba[5] == 242 && rgba[6] == 242 && rgba[7] == 255,
        'source rounding remains exact');
    check(rgba[8] == 0 && rgba[9] == 0 && rgba[10] == 0 && rgba[11] == 0,
        'transparent pixels remain transparent');
    final settledRevision = OriginalAssets.revision.value;
    check(settledRevision > initialRevision,
        'ready generation publishes repaint');
    for (var i = 0; i < 20; i++) {
      check(identical(OriginalAssets.grayImage('test', path), image),
          'cached image stays alive and is reused');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    check(OriginalAssets.revision.value == settledRevision,
        'no duplicate pending decode publishes another image');
    final mimic = Formation(mapId: 'day', display: const {}, pieces: [
      Piece(
          id: 'mimic',
          type: 'sunflower',
          row: 2,
          col: 2,
          layer: 10,
          effects: {'模仿者'}),
    ]);
    final recorder = ui.PictureRecorder();
    BoardPainter(document: mimic, background: false, helpers: false)
        .paint(ui.Canvas(recorder), const Size(800, 600));
    final picture = recorder.endRecording();
    final initialImage = await picture.toImage(800, 600);
    final initialPixels =
        (await initialImage.toByteData())!.buffer.asUint8List();
    check(initialPixels.any((value) => value > 0),
        'first interactive paint shows source while imitation is pending');
    initialImage.dispose();
    picture.dispose();
    final exported = await ui
        .instantiateImageCodec(await exportPng(mimic, background: false));
    final exportImage = (await exported.getNextFrame()).image;
    final exportPixels = (await exportImage.toByteData())!.buffer.asUint8List();
    var opaque = 0;
    for (var i = 0; i < exportPixels.length; i += 4) {
      if (exportPixels[i + 3] == 0) continue;
      opaque++;
      check(
          exportPixels[i] == exportPixels[i + 1] &&
              exportPixels[i] == exportPixels[i + 2],
          'first export awaits gray images instead of using colored fallback');
    }
    check(opaque > 100, 'imitation export must contain its sprite');
    exportImage.dispose();
    exported.dispose();
    await OriginalAssets.ensureImitationImages(['pea', 'pumpkin']);
    check(OriginalAssets.grayImage('Peashooter', realPath) != null,
        'one-shot export preparation awaits requested image');
    for (final part
        in OriginalAssets.sprites['Pumpkin_back']['images'] as List) {
      check(
          OriginalAssets.grayImage('Pumpkin_back', part['path'] as String) !=
              null,
          'split shell back is prepared for export');
    }
    stdout.writeln(
        'PASS: lazy imitation, repaint, request deduplication, cached image lifetime and exact HSL pixels');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
