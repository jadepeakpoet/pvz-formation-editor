// Real Flutter filter dialog, including Navigator Overlay in review screenshots.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_browser.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

Size size = const Size(900, 600);

class Binding extends WidgetsFlutterBinding {
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(logicalConstraints: BoxConstraints.tight(size), physicalConstraints: BoxConstraints.tight(size), devicePixelRatio: 1);
}

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

void walk(Element e, void Function(Element) visit) {
  visit(e);
  e.visitChildren((c) => walk(c, visit));
}

Element? keyed(String key) {
  Element? result;
  walk(WidgetsBinding.instance.rootElement!, (e) {
    if (e.widget.key == ValueKey(key)) result = e;
  });
  return result;
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 180));
Future<void> tap(String key) async {
  final e = keyed(key);
  check(e != null, 'Missing $key');
  await Scrollable.ensureVisible(e!, duration: Duration.zero, alignment: .5);
  await settle();
  final b = keyed(key)!.renderObject as RenderBox;
  final p = b.localToGlobal(b.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: p, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 1, position: p));
  await settle();
}

void search(String value) {
  final field = keyed('library-search')!.widget as TextField;
  field.controller!.text = value;
  field.onChanged!(value);
}

List<String> texts(Element element) {
  final values = <String>[];
  walk(element, (e) {
    if (e.widget is Text) values.add((e.widget as Text).data ?? '');
  });
  return values;
}

Formation formation(String map, int cobs) => Formation(
    mapId: map,
    pieces: List.generate(
        cobs,
        (i) => Piece(
            id: 'cob-$i',
            type: 'cob',
            row: i ~/ 4,
            col: (i % 4) * 2,
            layer: 10)));
Future<void> main() async {
  final binding = Binding();
  await OriginalAssets.ensureLoaded();
  final boundary = GlobalKey();
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  final passed = <String>[];
  final now = DateTime.now();
  final archives = [
    ArchiveRecord(
        id: 'pool-two',
        name: '名字写无炮但实际两炮',
        document: formation('pool', 2).toJson(),
        createdAt: now,
        updatedAt: now),
    ArchiveRecord(
        id: 'pool-zero',
        name: '名字写八炮但实际无炮',
        document: formation('pool', 0).toJson(),
        createdAt: now,
        updatedAt: now),
    ArchiveRecord(
        id: 'roof-four',
        name: '屋顶四炮',
        document: formation('roof', 4).toJson(),
        createdAt: now,
        updatedAt: now)
  ];
  runApp(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true),
          home: LibraryBrowser(
              drafts: const [],
              archives: archives,
              onRefresh: () async {},
              onNew: () {},
              onImportProject: () {},
              onImportString: () {},
              onOpenDraft: (_) {},
              onOpenArchive: (_) {},
              onDraftAction: (_, __) {},
              onArchiveAction: (_, __) {}))));
  await settle();
  await settle();
  try {
    check(keyed('library-filters-panel') == null,
        'Filter dialog collapsed by default');
    await tap('library-filter-toggle');
    await tap('library-map-pool');
    check(
        keyed('library-cannon-4') == null &&
            keyed('library-cannon-2') != null &&
            keyed('library-cannon-0') != null,
        'Cannon choices hide zero matches after scene staging');
    await tap('library-cannon-2');
    check(keyed('library-map-roof') == null,
        'Scene choices hide zero matches after cannon staging');
    check(
        texts(keyed('library-cannon-2')!).contains('2炮') &&
            texts(keyed('library-cannon-2')!).contains('1阵'),
        'Cannon amount and matching formation badge are separate');
    check((keyed('library-filter-count')!.widget as Text).data == '匹配 1 个阵型',
        'Combined dialog result count');
    await tap('library-filter-apply');
    check(
        keyed('library-item-archive:pool-two') != null &&
            keyed('library-item-archive:pool-zero') == null,
        'Scene and cannon combination applies to actual cob count');
    passed.add(
        'zero-match choices hidden; scene/cannon intersection and separate formation counts');
    await tap('library-filter-toggle');
    await tap('library-filter-reset');
    check(
        keyed('library-map-roof') != null && keyed('library-cannon-4') != null,
        'Staged reset restores available choices');
    await tap('library-filter-cancel');
    check(
        keyed('library-item-archive:pool-two') != null &&
            keyed('library-item-archive:pool-zero') == null,
        'Cancel leaves applied combination unchanged');
    passed.add(
        'reset changes draft conditions; cancel preserves applied filters');
    search('不存在的阵型');
    await settle();
    await tap('library-filter-toggle');
    check(
        keyed('library-map-all') != null && keyed('library-cannon-all') != null,
        'All choices remain available for empty matches');
    check(
        keyed('library-map-pool') == null &&
            keyed('library-map-roof') == null &&
            keyed('library-cannon-0') == null &&
            keyed('library-cannon-2') == null &&
            keyed('library-cannon-4') == null,
        'Empty search hides every zero-match non-all choice');
    check(
        !texts(keyed('library-map-all')!).contains('0阵') &&
            !texts(keyed('library-cannon-all')!).contains('0阵'),
        'All fallback has no zero-count badge');
    await tap('library-filter-reset');
    await tap('library-filter-apply');
    search('');
    await settle();
    check(keyed('library-item-archive:pool-zero') != null,
        'Reset and clearing search recover from no matches');
    passed.add('empty results retain All/reset fallback without 0阵 options');
    await tap('library-filter-toggle');
    await tap('library-map-pool');
    await tap('library-cannon-0');
    check(texts(keyed('library-cannon-0')!).contains('无炮'),
        'Zero actual cannon amount is labeled 无炮');
    await tap('library-filter-apply');
    check(
        keyed('library-item-archive:pool-zero') != null &&
            keyed('library-item-archive:pool-two') == null,
        'Cannon count ignores misleading formation names');
    passed.add('无炮 is based on actual cob plants rather than formation name');
    for (final viewport in [const Size(900, 600), const Size(800, 540)]) {
      size = viewport;
      binding.handleMetricsChanged();
      await settle();
      await tap('library-filter-toggle');
      await tap('library-filter-reset');
      await tap('library-map-pool');
      await tap('library-cannon-2');
      check(errors.isEmpty, 'Flutter layout errors at $viewport: $errors');
      final image = await (boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary)
          .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${Directory.systemTemp.path}/pvz-library-filter-dialog-${viewport.width.toInt()}.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
      await tap('library-filter-cancel');
      passed.add(
          'actual Overlay dialog screenshot and no layout errors ${viewport.width.toInt()}x${viewport.height.toInt()}');
    }
    await File('${Directory.systemTemp.path}/pvz-library-filter-dialog-report.json')
        .writeAsString(jsonEncode({
      'pass': passed,
      'errors': errors,
      'scope':
          'real Flutter LibraryBrowser modal/Overlay; fixture archives with exact cob counts; no native window assertion'
    }));
    stdout.writeln('PASS ${passed.length}: ${passed.join('; ')}');
    exit(0);
  } catch (e, stack) {
    stderr.writeln('$e\n$stack\n$errors');
    exit(1);
  }
}
