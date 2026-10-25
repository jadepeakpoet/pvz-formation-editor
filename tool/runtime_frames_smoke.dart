// Verify runtime crops against independently decoded source-sheet pixels.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/sprite_frame_image.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OriginalAssets.ensureLoaded();
  await OriginalAssets.ensureHitMasks(OriginalAssets.sprites.keys.toList());
  final index = jsonDecode(
    await rootBundle.loadString('assets/original/frame_index.json'),
  ) as Map;
  var checked = 0;
  for (final entry in index.entries) {
    final part = entry.value as Map;
    final data = await rootBundle.load('assets/original/${entry.key}');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final sheet = (await codec.getNextFrame()).image;
    codec.dispose();
    // Compare displayed pixels: drawing applies the source PNG color profile.
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImage(sheet, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    final displayed = await picture.toImage(sheet.width, sheet.height);
    picture.dispose();
    final raw = (await displayed.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    displayed.dispose();
    final expected = raw.buffer.asUint8List(
      raw.offsetInBytes,
      raw.lengthInBytes,
    );
    final width = part['w'] as int, height = part['h'] as int;
    final columns = part['cols'] as int;
    final frames = part['frames'] as List;
    for (var frame = 0; frame < frames.length; frame++) {
      final key = 'frames/${frames[frame]}.png';
      final image = await OriginalAssets.loadFrameImage(key);
      if (image.width != width || image.height != height) {
        throw StateError('Wrong crop size: $key');
      }
      final cropped = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final actual = cropped.buffer.asUint8List(
        cropped.offsetInBytes,
        cropped.lengthInBytes,
      );
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final sx = (frame % columns) * width + x;
          final sy = (frame ~/ columns) * height + y;
          if (!(entry.key as String).endsWith('/shadow.png')) {
            final alpha = sx < sheet.width && sy < sheet.height
                ? expected[(sy * sheet.width + sx) * 4 + 3]
                : 0;
            if (OriginalAssets.frameOpaqueAt(
                  {...part, 'path': entry.key, 'rw': width, 'rh': height},
                  frame ~/ columns,
                  frame % columns,
                  x,
                  y,
                ) !=
                (alpha >= 16)) {
              throw StateError(
                'Hit mask mismatch: ${entry.key} frame $frame ($x,$y)',
              );
            }
          }
          for (var channel = 0; channel < 4; channel++) {
            final value = sx < sheet.width && sy < sheet.height
                ? expected[(sy * sheet.width + sx) * 4 + channel]
                : 0;
            if ((actual[(y * width + x) * 4 + channel] - value).abs() > 1) {
              throw StateError(
                'Crop pixel mismatch: ${entry.key} frame $frame ($x,$y) channel $channel: ${actual[(y * width + x) * 4 + channel]} != $value; alpha ${actual[(y * width + x) * 4 + 3]}',
              );
            }
          }
        }
      }
      image.dispose();
      checked++;
    }
    sheet.dispose();
    OriginalAssets.releaseColdImages();
  }
  // A subset of a large sheet must not become a cached whole-sheet image.
  final part =
      (OriginalAssets.sprites['Cobcannon']['images'] as List).last as Map;
  final key = OriginalAssets.spriteFramePath(part, 0, 0);
  final previews = await Future.wait(
    List.generate(8, (_) => OriginalAssets.loadFrameImage(key, scale: .25)),
  );
  if (OriginalAssets.resourceStats()['transientSheets'] != 0) {
    throw StateError('A full source sheet remained resident after cropping');
  }
  if (previews.any(
    (image) => image.width != ((part['rw'] as num) * .25).ceil(),
  )) {
    throw StateError('Preview did not use its requested resolution');
  }
  for (final image in previews) {
    image.dispose();
  }
  // Exercise the ImageProvider ownership path used by the appearance picker.
  final completer = SpriteFrameImage(
    key,
    scale: .25,
  ).resolve(ImageConfiguration.empty);
  final done = <String>[];
  final listener = ImageStreamListener((image, synchronousCall) {
    image.dispose();
    done.add('ready');
  });
  completer.addListener(listener);
  for (var i = 0; i < 100 && done.isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  completer.removeListener(listener);
  if (done.isEmpty) throw StateError('Appearance preview did not resolve');
  stdout.writeln(
    'PASS $checked runtime frames match source pixels; '
    'scaled previews, concurrent requests, source release and image provider',
  );
  exit(0);
}
