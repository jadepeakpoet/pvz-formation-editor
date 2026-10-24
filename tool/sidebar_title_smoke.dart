// Focused library title ownership and action checks; no native window automation.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_browser.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Size viewport = const Size(410, 640);

class TitleBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      ParityMessenger(super.createBinaryMessenger());
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(logicalConstraints: BoxConstraints.tight(viewport), physicalConstraints: BoxConstraints.tight(viewport), devicePixelRatio: 1);
}

void check(bool good, String message) {
  if (!good) throw StateError(message);
}

List<Element> find(bool Function(Widget) predicate) {
  final all = <Element>[];
  void visit(Element e) {
    if (predicate(e.widget)) all.add(e);
    e.debugVisitOnstageChildren(visit);
  }

  visit(WidgetsBinding.instance.rootElement!);
  return all;
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 180));
Future<void> tapElement(Element e) async {
  await Scrollable.ensureVisible(e, duration: Duration.zero);
  final box = e.renderObject as RenderBox;
  final point = box.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 92, position: point, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 92, position: point));
  await settle();
}

Future<void> tap(String key) =>
    tapElement(find((w) => w.key == ValueKey(key)).single);
Future<void> main() async {
  final binding = TitleBinding();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  final rows = <Map<String, dynamic>>[];
  final boundary = GlobalKey();
  int created = 0, imported = 0, refreshed = 0;
  final archive = ArchiveRecord(
      id: 'fixture',
      name: '屋顶布阵',
      document: Formation(mapId: 'roof').toJson(),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026));
  Future<void> mount(Size size, {bool? showTitle}) async {
    viewport = size;
    binding.handleMetricsChanged();
    runApp(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(useMaterial3: true),
            home: LibraryBrowser(
                drafts: const [],
                archives: [archive],
                showTitle: showTitle ?? true,
                onRefresh: () async {
                  refreshed++;
                },
                onNew: () => created++,
                onImportProject: () => imported++,
                onImportString: () {},
                onOpenDraft: (_) {},
                onOpenArchive: (_) {},
                onDraftAction: (_, __) {},
                onArchiveAction: (_, __) {}))));
    await settle();
    await settle();
  }

  Future<void> test(String id, Future<void> Function() body) async {
    final before = errors.length;
    try {
      await body();
      check(errors.length == before, 'Flutter error');
      rows.add({'id': id, 'status': 'pass'});
    } catch (e, s) {
      rows.add({'id': id, 'status': 'fail', 'error': '$e', 'stack': '$s'});
    }
  }

  await OriginalAssets.ensureLoaded();
  await test('native-host-410x640-hides-content-title-keeps-actions', () async {
    await mount(const Size(410, 640), showTitle: false);
    check(find((w) => w is Text && w.data == '存档库').isEmpty,
        'native host owns librarytitle');
    check(find((w) => w is Icon && w.icon == Icons.grass_rounded).isEmpty,
        'title icon hidden');
    for (final key in [
      'library-new',
      'library-import',
      'library-refresh',
      'library-search',
      'library-filter-toggle',
      'library-sort'
    ]) {
      check(find((w) => w.key == ValueKey(key)).length == 1,
          'action retained: $key');
    }
    await tap('library-new');
    check(created == 1, 'new action');
    await tap('library-import');
    await tapElement(find((w) => w is Text && w.data == '导入项目文件').single);
    check(imported == 1, 'import action');
    await tap('library-refresh');
    check(refreshed == 1, 'refresh action');
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${Directory.systemTemp.path}/pvz-library-titleless-410.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
  await test('wide-native-host-hides-content-title', () async {
    await mount(const Size(800, 600), showTitle: false);
    check(
        find((w) => w is Text && w.data == '存档库').isEmpty, 'wide title hidden');
    for (final key in ['library-new', 'library-import', 'library-refresh']) {
      check(find((w) => w.key == ValueKey(key)).length == 1,
          'wide action retained');
    }
  });
  await test('standalone-default-retains-title', () async {
    await mount(const Size(410, 640));
    check(find((w) => w is Text && w.data == '存档库').length == 1,
        'default title preserved');
    check(find((w) => w is Icon && w.icon == Icons.grass_rounded).length == 1,
        'default icon preserved');
  });
  runApp(const SizedBox.shrink());
  await settle();
  final report = {
    'suite': 'library-title-ownership',
    'runtime':
        'real headless Flutter; focused title ownership and actual action pointers only',
    'results': rows,
    'passed': rows.where((r) => r['status'] == 'pass').length,
    'failed': rows.where((r) => r['status'] == 'fail').length,
    'flutterErrors': errors.map((e) => '${e.exception}').toList(),
    'screenshot': '${Directory.systemTemp.path}/pvz-library-titleless-410.png'
  };
  File('${Directory.systemTemp.path}/pvz-library-title-report.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(jsonEncode(report));
  exit(report['failed'] == 0 && errors.isEmpty ? 0 : 1);
}
