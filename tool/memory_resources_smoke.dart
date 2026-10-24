import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/editor/resource_image.dart';
import 'package:pvz_formation_editor/editor/image_resources.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<ui.Image> pixel() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xff336699), ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(8, 8);
  } finally {
    picture.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  try {
    final cache = ImageResources(maximumBytes: 256);
    cache['old'] = await pixel();
    final widgetHandle = cache['old']!.clone();
    cache['new'] = await pixel();
    cache.trim(minimumAge: Duration.zero);
    check(cache.bytes == 256 && !cache.containsKey('old'), 'LRU byte eviction');
    check((await widgetHandle.toByteData())!.lengthInBytes == 256,
        'Mounted widget survives eviction through its independent handle');
    widgetHandle.dispose();
    runApp(Directionality(textDirection: TextDirection.ltr,
      child: ResourceImage(image: cache['new'])));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    cache.clear();
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    runApp(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    cache['new'] = await pixel();
    await cache.retainDuring(() async {
      cache['lease'] = await pixel();
      cache.trim(minimumAge: Duration.zero);
      check(cache.bytes == 512, 'Export lease protects resources');
    });
    cache.trim(minimumAge: Duration.zero);
    check(cache.bytes == 256, 'Released export resources can be evicted');
    cache.clear();
    check(
        cache.bytes == 0 && cache.isEmpty, 'Cache clear releases all handles');
    await OriginalAssets.ensureLoaded();
    check(
        OriginalAssets.images.isEmpty, 'Metadata startup decodes no pictures');
    for (final preset in LibraryPresets.all.take(40)) {
      final bytes = await exportPng(preset.document, multiplier: .32);
      check(bytes.length > 1000, 'Populated thumbnail ${preset.id}');
      OriginalAssets.images.trim(minimumAge: Duration.zero);
      check(OriginalAssets.images.bytes <= OriginalAssets.images.maximumBytes,
          'Artwork remains within the byte budget after resource release');
    }
    final doc = LibraryPresets.all.first.document;
    final first = await exportPng(doc);
    OriginalAssets.images.clear();
    final second = await exportPng(doc);
    File('build/checks/export-before.png').writeAsBytesSync(first);
    File('build/checks/export-after.png').writeAsBytesSync(second);
    check(
        first.length == second.length &&
            List.generate(first.length, (i) => first[i] == second[i])
                .every((v) => v),
        'Full export is identical after eviction and lazy reload');
    check(errors.isEmpty, 'Mounted cache eviction has no framework errors: $errors');
    stdout.writeln(
        'PASS memory resources, leases, 40 thumbnails, full export reload');
    OriginalAssets.images.clear();
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
