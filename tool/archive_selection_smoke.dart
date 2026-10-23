import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_browser.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'sidebar_title_smoke.dart' as h;

Future<void> main() async {
  h.TitleBinding();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  final exported = <List<String>>[];
  final archives = List.generate(
      3,
      (i) => ArchiveRecord(
          id: 'a$i',
          name: '个人阵型$i',
          document: Formation().toJson(),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026)));
  await OriginalAssets.ensureLoaded();
  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LibraryBrowser(
          showTitle: false,
          drafts: const [],
          archives: archives,
          onRefresh: () async {},
          onNew: () {},
          onImportProject: () {},
          onImportString: () {},
          onOpenDraft: (_) {},
          onDraftAction: (_, __) {},
          onOpenArchive: (_) {},
          onArchiveAction: (_, __) {},
          onExportArchives: (records) async =>
              exported.add(records.map((a) => a.id).toList()))));
  await h.settle();
  await h.settle();
  bool passed = false;
  String? failure;
  try {
    await h.tap('library-select-archives');
    await h.tap('library-select-a0');
    final field = h.find((w) => w is EditableText).single as StatefulElement;
    (field.state as EditableTextState)
        .updateEditingValue(const TextEditingValue(text: '个人阵型1'));
    await h.settle();
    h.check(
        h.find((w) => w is Text && w.data == '已选 1（含 1 个筛选外存档）').length == 1,
        'hidden selected hint');
    h.check(h.find((w) => w is Text && w.data == '全选当前结果').length == 1,
        'explicit visible-select label');
    await h.tap('library-select-all');
    h.check(
        h.find((w) => w is Text && w.data == '已选 2（含 1 个筛选外存档）').length == 1,
        'union count hint');
    await h.tap('library-export');
    await h.tap('library-export-selected');
    h.check(exported.single.join(',') == 'a0,a1',
        'export preserves hidden selection');
    h.check(errors.isEmpty, 'Flutter error');
    passed = true;
  } catch (e, s) {
    failure = '$e\n$s';
  }
  final report = {
    'id': '410x640-filtered-selection-explicit-count-and-export',
    'status': passed ? 'pass' : 'fail',
    'error': failure,
    'flutterErrors': errors.map((e) => '${e.exception}').toList()
  };
  File('/tmp/pvz-archive-selection-report.json')
      .writeAsStringSync(jsonEncode(report));
  stdout.writeln(jsonEncode(report));
  exit(passed ? 0 : 1);
}
