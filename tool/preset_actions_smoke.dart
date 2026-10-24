// Focused library title ownership and action checks; no native window automation.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_browser.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';

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
    Future<void>.delayed(const Duration(milliseconds: 400));
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
  TitleBinding();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  final actions = <String>[];
  final exports = <List<String>>[];
  final presets = LibraryPresets.all.take(2).toList();
  final initial = jsonEncode(presets.first.document.toJson());
  final archives = List.generate(
      3,
      (i) => ArchiveRecord(
          id: 'a$i',
          name: '个人阵型$i',
          document: Formation(mapId: 'pool').toJson(),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026)));
  final rows = <Map<String, dynamic>>[];
  Future<void> test(String id, Future<void> Function() body) async {
    try {
      await body();
      check(errors.isEmpty, 'Flutter errors');
      rows.add({'id': id, 'status': 'pass'});
    } catch (e, s) {
      rows.add({'id': id, 'status': 'fail', 'error': '$e', 'stack': '$s'});
    }
  }

  await OriginalAssets.ensureLoaded();
  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LibraryBrowser(
        showTitle: false,
        drafts: [
          DraftRecord(
              id: 'hidden',
              name: '禁止出现草稿',
              mapId: 'pool',
              document: Formation(mapId: 'pool').toJson(),
              revision: 1)
        ],
        archives: archives,
        presets: presets,
        onRefresh: () async {},
        onNew: () {},
        onImportProject: () {},
        onImportString: () {},
        onOpenDraft: (_) {},
        onDraftAction: (_, __) {},
        onOpenArchive: (_) {},
        onArchiveAction: (a, _) => actions.add('archive:$a'),
        onPresetAction: (a, p) async {
          actions.add(a);
          check(identical(p, presets.first), 'preset identity');
        },
        onExportArchives: (items) async =>
            exports.add(items.map((a) => a.id).toList()),
      )));
  await settle();
  await settle();
  await test('no-draft-ui', () async {
    check(find((w) => w is Text && (w.data ?? '').contains('草稿')).isEmpty,
        'draft text visible');
    check(find((w) => w.key == const ValueKey('library-section-工作草稿')).isEmpty,
        'draft section visible');
  });
  await tap('library-section-预制名阵');
  await tap('library-item-preset:${presets.first.id}');
  await test('template-explicit-actions', () async {
    for (final pair in [
      ('library-open-current', 'open-current'),
      ('library-open-tab', 'open-tab'),
      ('library-copy-code', 'copy-code'),
      ('library-add-preset', 'copy')
    ]) {
      await tap(pair.$1);
      check(actions.last == pair.$2, 'wrong ${pair.$1}');
      if (pair.$2 == 'open-current' || pair.$2 == 'open-tab') {
        check(
            find((w) => w.key == const ValueKey('library-detail-back')).isEmpty,
            'Successful template use must return to list');
        await tap('library-item-preset:${presets.first.id}');
      }
    }
  });
  await test('template-menu-nine-safe-actions', () async {
    for (final pair in [
      ('只读预览', 'preview'),
      ('导出完整项目', 'export'),
      ('复制图片', 'copy-image'),
      ('导出图片', 'export-image')
    ]) {
      await tap('library-menu-preset:${presets.first.id}');
      check(
          find((w) =>
              w is Text &&
              ['删除存档', '重命名', '历史版本与回退', '名称、备注、标签'].contains(w.data)).isEmpty,
          'template mutations visible');
      await tapElement(find((w) => w is Text && w.data == pair.$1).single);
      check(actions.last == pair.$2, 'wrong menu action');
    }
    check(jsonEncode(presets.first.document.toJson()) == initial,
        'template changed');
  });
  await tap('library-detail-back');
  await tap('library-section-我的存档');
  await test('personal-rename-history', () async {
    await tap('library-menu-archive:a0');
    await tapElement(find((w) => w is Text && w.data == '重命名').single);
    check(actions.last == 'archive:rename', 'rename callback');
    await tap('library-menu-archive:a0');
    await tapElement(find((w) => w is Text && w.data == '历史版本与回退').single);
    check(actions.last == 'archive:versions', 'history callback');
  });
  await test('export-all-selection-subset-cancel', () async {
    await tap('library-export');
    await tap('library-export-all');
    check(exports.last.join(',') == 'a0,a1,a2', 'all excludes presets');
    await tap('library-select-archives');
    await tap('library-select-a1');
    await tap('library-export');
    await tap('library-export-selected');
    check(exports.last.join(',') == 'a1', 'single selected export');
    await tap('library-select-all');
    await tap('library-export');
    await tap('library-export-selected');
    check(exports.last.toSet().length == 3, 'all selected');
    await tap('library-select-archives');
    check(
        find((w) => w.key == const ValueKey('library-selected-count')).isEmpty,
        'cancel selection');
  });
  final report = {
    'suite': 'preset-and-personal-archive-actions',
    'results': rows,
    'flutterErrors': errors.map((e) => '${e.exception}').toList(),
    'passed': rows.where((r) => r['status'] == 'pass').length,
    'failed': rows.where((r) => r['status'] == 'fail').length
  };
  File('${Directory.systemTemp.path}/pvz-preset-actions-report.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(jsonEncode(report));
  exit(report['failed'] == 0 && errors.isEmpty ? 0 : 1);
}
