// Real responsive LibraryBrowser. Export callbacks capture records in memory;
// no archive database, file dialog or native transport is used here.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_browser.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

class Binding extends ParityBinding {
  Size viewport = const Size(410, 720);
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(logicalConstraints: BoxConstraints.tight(viewport), physicalConstraints: BoxConstraints.tight(viewport), devicePixelRatio: 1);
}

Future<void> main() async {
  final binding = Binding();
  await OriginalAssets.ensureLoaded();
  final records = [
    ArchiveRecord(
        id: 'one',
        name: '我的泳池',
        document: Formation().toJson(),
        tags: ['泳池', '夜间'],
        createdAt: DateTime(2020),
        updatedAt: DateTime(2021)),
    ArchiveRecord(
        id: 'fav',
        name: '收藏草地',
        document: Formation(mapId: 'day').toJson(),
        favorite: true,
        tags: ['草地'],
        createdAt: DateTime(2020),
        updatedAt: DateTime(2022)),
    ArchiveRecord(
        id: 'other',
        name: '我的屋顶',
        document: Formation(mapId: 'roof').toJson(),
        tags: const [],
        createdAt: DateTime(2020),
        updatedAt: DateTime(2020)),
  ];
  final presets = LibraryPresets.all.take(2).toList();
  final favoredPreset = presets.last;
  final unchanged = jsonEncode([
    for (final record in records)
      {
        'id': record.id,
        'name': record.name,
        'document': record.document,
        'tags': record.tags,
        'favorite': record.favorite,
      }
  ]);
  final exports = <List<ArchiveRecord>>[];
  var mutatingCallbacks = 0;
  final boundary = GlobalKey();
  final h = ParityHarness(
      boundary,
      await Directory('/tmp/pvz-library-global-actions')
          .create(recursive: true));
  FlutterError.onError = h.errors.add;
  bool keyed(String key) => h.all((w) => w.key == ValueKey(key)).isNotEmpty;
  Future<void> tap(String key) =>
      h.tapElement(h.find((w) => w.key == ValueKey(key)));
  Set<String> visibleIds() => h
      .all((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('library-item-archive:'))
      .map((element) => (element.widget.key as ValueKey<String>)
          .value
          .substring('library-item-archive:'.length))
      .toSet();
  Future<void> export(String key) async {
    await tap('library-export');
    await tap(key);
    await h.settle();
  }

  Offset origin(String key) =>
      (h.find((w) => w.key == ValueKey(key)).renderObject as RenderBox)
          .localToGlobal(Offset.zero);
  Future<void> closeTagPicker() async {
    await h.tapElement(h.find((w) => w is BackButton || w is CloseButton));
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  for (final width in [410.0, 1100.0]) {
    binding.viewport = Size(width, 720);
    binding.handleMetricsChanged();
    runApp(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            key: ValueKey('library-$width'),
            home: Scaffold(
                body: LibraryBrowser(
                    drafts: const [],
                    archives: records,
                    presets: presets,
                    favoritePresetIds: {favoredPreset.id},
                    onRefresh: () async {},
                    onNew: () {},
                    onImportProject: () {},
                    onImportString: () {},
                    onOpenDraft: (_) {},
                    onOpenArchive: (_) {},
                    onDraftAction: (_, __) => mutatingCallbacks++,
                    onArchiveAction: (_, __) => mutatingCallbacks++,
                    onPresetAction: (_, __) async {
                      mutatingCallbacks++;
                    },
                    onAddPreset: (_) async {
                      mutatingCallbacks++;
                    },
                    onExportArchives: (value) async {
                      exports.add(List.of(value));
                    })))));
    await h.settle();
    await h.settle();
    h.expect(keyed('library-export') && keyed('library-select-archives'),
        'Global actions missing at $width px');
    h.expect(
        (origin('library-export').dy - origin('library-select-archives').dy)
                    .abs() <
                12 &&
            origin('library-select-archives').dx > origin('library-export').dx,
        'Batch selection is not at the right of the global header at $width px');
    h.expect(!keyed('library-export-all') && !keyed('library-export-selected'),
        'Classification content still exposes standalone export actions');
    final stars = h
        .all((w) => w is Icon && w.icon == Icons.star_rounded)
        .map((e) => e.widget as Icon)
        .toList();
    h.expect(
        stars.isNotEmpty &&
            stars.every((icon) => icon.color == const Color(0xffffb300)),
        'Selected favorite stars are not consistently gold');

    await tap('library-section-预制名阵');
    await export('library-export-all');
    h.expect(
        exports.last
                .map((r) => r.id)
                .toSet()
                .containsAll({'one', 'fav', 'other'}) &&
            exports.last.length == 3,
        'Global user export depends on current category');
    await export('library-export-favorites');
    h.expect(
        exports.last.length == 2 &&
            exports.last.any((r) => r.id == 'fav') &&
            exports.last.any((r) =>
                r.name == favoredPreset.name &&
                Formation.fromJson(r.document).fingerprint ==
                    favoredPreset.document.fingerprint),
        'Favorites export omitted the favorite preset or included nonfavorites');
    h.expect(mutatingCallbacks == 0, 'Export mutated or added library records');

    await tap('library-section-我的存档');
    await tap('library-select-archives');
    await tap('library-select-one');
    await export('library-export-selected');
    h.expect(exports.last.length == 1 && exports.last.single.id == 'one',
        'Selected export did not contain the exact checked user archive');
    await tap('library-select-archives');

    final beforeTag = visibleIds();
    await tap('library-tags');
    h.expect(
        keyed('library-tag-picker') && h.all((w) => w is Scaffold).isNotEmpty,
        'Tags did not push a dedicated page');
    await closeTagPicker();
    h.expect(
        !keyed('library-tag-picker') &&
            visibleIds().length == beforeTag.length &&
            visibleIds().containsAll(beforeTag),
        'Canceling tag route changed the filter');
    await tap('library-tags');
    await tap('library-tag:泳池');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    h.expect(
        !keyed('library-tag-picker') &&
            visibleIds().length == 1 &&
            visibleIds().contains('one'),
        'Selecting a tag did not return to filtered library');
    await export('library-export-all');
    h.expect(
        exports.last.length == 3, 'Tag filter narrowed global user export');
    await tap('library-tags');
    await tap('library-tag-all');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    h.expect(
        visibleIds().length == 3, 'All-tags route did not clear tag filter');

    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/pvz-library-global-actions/${width.toInt()}.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    stdout.writeln(
        'PASS global exports, header batch selection, tag route and gold favorites at ${width.toInt()} px');
    runApp(const SizedBox.shrink());
    await h.settle();
  }
  h.expect(
      mutatingCallbacks == 0 &&
          unchanged ==
              jsonEncode([
                for (final record in records)
                  {
                    'id': record.id,
                    'name': record.name,
                    'document': record.document,
                    'tags': record.tags,
                    'favorite': record.favorite,
                  }
              ]),
      'Library navigation or exports mutated source records');
  h.expect(h.errors.isEmpty,
      h.errors.map((error) => error.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS library actions remain read-only across responsive layouts');
  exit(0);
}
