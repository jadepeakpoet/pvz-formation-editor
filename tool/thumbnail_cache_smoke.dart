import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/formation_thumbnail.dart';
import 'package:pvz_formation_editor/library/thumbnail_store.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'sidebar_title_smoke.dart' as h;

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Future<void> waitFor(bool Function() predicate, String reason) async {
  for (var i = 0; i < 150; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(reason);
}

int visibleImages() {
  if (WidgetsBinding.instance.rootElement == null) return 0;
  return h
      .find((w) =>
          w is RawImage && w.image?.width == 256 && w.image?.height == 192)
      .where((element) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final p = box.localToGlobal(Offset.zero);
    return p.dy < 640 && p.dy + box.size.height > 0;
  }).length;
}

Future<void> main() async {
  h.viewport = const Size(410, 640);
  h.TitleBinding();
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  final temp = await Directory.systemTemp.createTemp('pvz-thumbnail-cache-');
  ThumbnailStore.directoryOverride = temp;
  try {
    await OriginalAssets.ensureLoaded();
    final progress = <double>[];
    void updated() {
      final value = ThumbnailStore.preparationProgress.value;
      if (value != null) progress.add(value);
    }

    ThumbnailStore.preparationProgress.addListener(updated);
    await ThumbnailStore.primeBuiltins();
    check(
        (await temp.list().where((f) => f.path.endsWith('.webp')).length) ==
            0,
        'First-start registers bundled previews without copying/decoding 363 files');
    check(progress.first == 0 && progress.last == 1,
        'First-start progress completes');
    progress.clear();
    await ThumbnailStore.primeBuiltins();
    check(progress.isEmpty, 'Second start reuses completed cache');
    ThumbnailStore.preparationProgress.removeListener(updated);
    final controller = ScrollController();
    final presets = LibraryPresets.all.take(90).toList();
    runApp(MaterialApp(
        home: Scaffold(
            body: ListView.builder(
                controller: controller,
                itemExtent: 90,
                cacheExtent: 0,
                itemCount: presets.length,
                itemBuilder: (context, i) => Row(children: [
                      SizedBox(
                          width: 120,
                          height: 90,
                          child: FormationThumbnail(
                              key: ValueKey(presets[i].id),
                              document: presets[i].document)),
                      Text('$i')
                    ])))));
    await waitFor(() => visibleImages() >= 6,
        'First completed thumbnail Futures reach widgets');
    check(ThumbnailStore.generated == 0,
        'Built-in previews never render full formations');
    for (var page = 1; page <= 10; page++) {
      controller.jumpTo(page * 600);
      await WidgetsBinding.instance.endOfFrame;
      await waitFor(
          () => visibleImages() >= 5, 'Scroll shows ready thumbnails');
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    FormationThumbnail.clearCache();
    check(visibleImages() >= 5,
        'Memory trimming preserves visible pinned images');
    controller.jumpTo(0);
    await WidgetsBinding.instance.endOfFrame;
    await waitFor(() => visibleImages() >= 6,
        'Scroll-back reloads cached local previews');
    check(ThumbnailStore.generated == 0,
        'Scroll-back never renders built-in previews');
    check(FormationThumbnail.cachedBytes <= (4 << 20),
        'Cold preview cache fits byte budget');
    final base = presets.first.document;
    final custom = base.copy(pieces: [
      ...base.pieces,
      Piece(id: 'cache-test', type: 'pea', row: 0, col: 8, layer: 20)
    ]);
    final duplicate = custom.copy(pieces: [
      for (final p in custom.pieces)
        Piece.fromJson(
            Map<String, dynamic>.from(p.toJson())..['id'] = 'different-${p.id}')
    ]);
    check(ThumbnailStore.key(custom) == ThumbnailStore.key(duplicate),
        'Visual cache identity ignores archive/object IDs');
    runApp(MaterialApp(home: FormationThumbnail(document: custom)));
    await waitFor(() => visibleImages() >= 1,
        'Custom preview first generation completes');
    final key = ThumbnailStore.key(custom);
    await waitFor(() => File('${temp.path}/$key.png').existsSync(),
        'Custom preview persists to disk');
    final generated = ThumbnailStore.generated;
    runApp(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    FormationThumbnail.clearCache();
    runApp(MaterialApp(home: FormationThumbnail(document: duplicate)));
    await waitFor(
        () => visibleImages() >= 1, 'Custom preview reopens from local cache');
    check(ThumbnailStore.generated == generated,
        'Disk hit bypasses plant/background decoding and composition');
    runApp(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    FormationThumbnail.clearCache();
    await File('${temp.path}/$key.png').writeAsBytes([1, 2, 3]);
    check(await ThumbnailStore.read(key) == null,
        'Corrupt cache is treated as a miss');
    check(errors.isEmpty, 'No image-lifetime or framework errors: $errors');
    stdout.writeln(jsonEncode({
      'status': 'pass',
      'bundledHits': ThumbnailStore.bundledHits,
      'diskHits': ThumbnailStore.diskHits,
      'generated': ThumbnailStore.generated,
      'previewBytes': FormationThumbnail.cachedBytes,
      'errors': errors
    }));
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack\n$errors');
    exit(1);
  }
}
