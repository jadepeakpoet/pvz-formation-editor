// Actual library clicks and SQLite; 410px toolbox or wide library via env.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_browser.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

class Binding extends ParityBinding {
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(logicalConstraints: BoxConstraints.tight(Size(
              double.parse(Platform.environment['PVZ_TAGS_WIDTH'] ?? '410'),
              700)), physicalConstraints: BoxConstraints.tight(Size(
              double.parse(Platform.environment['PVZ_TAGS_WIDTH'] ?? '410'),
              700)), devicePixelRatio: 1);
}

class LibraryHarness extends ParityHarness {
  LibraryHarness(super.boundary, super.output);
  @override
  Future<String> screenshot(String label) async {
    await settle();
    final image = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final path = '${output.path}/$label.png';
    await File(path).writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
    evidence.add(path);
    return path;
  }
}

Future<void> main() async {
  Binding();
  await OriginalAssets.ensureLoaded();
  final dir = await Directory.systemTemp.createTemp('pvz-library-tags-');
  final path = '${dir.path}/tags.sqlite';
  final repo = await FormationRepository.open(path);
  final document = Formation().toJson();
  for (final fixture in [
    ('a', '第一阵', ['常用', '攻略']),
    ('b', '第二阵', ['常用']),
    ('c', '第三阵', <String>[]),
    ('d', '第四阵', ['常用扩展']),
  ]) {
    await repo.saveArchive(
        id: fixture.$1,
        name: fixture.$2,
        document: document,
        tags: fixture.$3,
        note: '保留备注');
  }
  final key = GlobalKey();
  final h = LibraryHarness(
      key,
      await Directory(
              '${Directory.systemTemp.path}/pvz-library-tags-${Platform.environment['PVZ_TAGS_WIDTH'] ?? '410'}')
          .create(recursive: true));
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: key,
      child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home:
              app.LibraryPage(repository: repo, onOpenSession: (_) async {}))));
  await h.settle();
  await h.settle();
  dynamic browser() =>
      (h.find((w) => w is LibraryBrowser) as StatefulElement).state;
  Future<void> tap(String key) async =>
      h.tapElement(h.find((w) => w.key == ValueKey(key)));
  Future<void> refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await h.settle();
  }

  Future<ArchiveRecord> record() async =>
      (await repo.listArchives()).singleWhere((a) => a.id == 'a');
  Future<void> input(String key, String value) async {
    final field = h.find((w) => w.key == ValueKey(key)).widget as TextField;
    field.controller!.text = value;
    field.onChanged?.call(value);
    await h.settle();
  }

  List<String> ids() =>
      [for (final entry in browser().filtered) entry.archive.id as String];
  await h.run('tags.create-reuse-persist',
      'Create/reuse/remove labels; save pending input and preserve archive contents',
      () async {
    await tap('library-item-archive:a');
    await tap('library-edit-tags');
    await tap('archive-tag-choice:攻略');
    await input('archive-tag-input', ' 新标签，常用，新标签 ');
    await tap('archive-tag-add');
    await input('archive-tag-input', '待保存');
    await tap('archive-tags-save');
    await refresh();
    final saved = await record();
    h.expect(
        saved.tags.toSet().containsAll(['常用', '新标签', '待保存']) &&
            saved.tags.length == 3 &&
            !saved.tags.contains('攻略'),
        'Wrong saved tags');
    h.expect(
        saved.name == '第一阵' &&
            saved.note == '保留备注' &&
            Formation.fromJson(saved.document).fingerprint ==
                Formation.fromJson(document).fingerprint,
        'Tag change modified name/note/formation');
    h.expect((await repo.listVersions('a')).length == 1,
        'Tag save did not preserve archive history');
  });
  await h.run('tags.open-all-exact',
      'Detail chip opens every archive with exact tag and clears old search/filters',
      () async {
    browser().query = '不匹配';
    browser().mapFilter = 'roof';
    await tap('library-detail-tag:常用');
    h.expect(ids().toSet().containsAll(['a', 'b']) && ids().length == 2,
        'Click label did not open all exact matches');
    h.expect(
        browser().query.isEmpty &&
            browser().mapFilter.isEmpty &&
            browser().tagFilter == '常用',
        'Old filters hid label results');
    await tap('library-tags');
    await tap('library-tag:新标签');
    h.expect(
        ids().length == 1 && ids().single == 'a', 'Tag index not filtering');
    await tap('library-tags');
    await tap('library-tag-all');
    h.expect(ids().length == 4, 'All archives did not clear tag filter');
  });
  await h.run('tags.search-and-cancel',
      'Search tags; cancel leaves metadata unchanged; labels survive database reopen',
      () async {
    await input('library-search', '新标签');
    h.expect(
        ids().length == 1 && ids().single == 'a', 'Tag text search failed');
    await tap('library-item-archive:a');
    await tap('library-edit-tags');
    await tap('archive-tag-choice:常用');
    await input('archive-tag-input', '取消标签');
    await tap('archive-tags-cancel');
    await refresh();
    h.expect(
        (await record()).tags.contains('常用') &&
            !(await record()).tags.contains('取消标签'),
        'Canceled changes persisted');
    final reopened = await FormationRepository.open(path);
    final saved =
        (await reopened.listArchives()).singleWhere((a) => a.id == 'a');
    h.expect(saved.tags.contains('新标签'), 'Reopen lost tags');
    await reopened.close();
  });
  await h.run('tags.clear',
      'All labels can be removed; obsolete label disappears from index',
      () async {
    await tap('library-edit-tags');
    for (final tag in (await record()).tags) {
      await tap('archive-tag-choice:$tag');
    }
    await tap('archive-tags-save');
    await refresh();
    h.expect((await record()).tags.isEmpty, 'Cannot remove all labels');
    h.expect(
        !browser().tagCounts.containsKey('新标签') &&
            browser().tagCounts['常用'] == 1,
        'Tag index/count retained removed label');
  });
  await h.report();
  await File(
          '${Directory.systemTemp.path}/pvz-library-tags-${Platform.environment['PVZ_TAGS_WIDTH'] ?? '410'}-report.json')
      .writeAsString(jsonEncode(h.cases));
  await repo.close();
  exit(h.cases.every((c) => c['status'] == 'pass') ? 0 : 1);
}
