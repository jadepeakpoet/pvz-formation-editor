// Real LibraryPage and temporary SQLite. No user database or native dialogs.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  await OriginalAssets.ensureLoaded();
  final directory = await Directory.systemTemp.createTemp('pvz-dedup-ui-');
  final repo =
      await FormationRepository.open('${directory.path}/fixture.sqlite');
  Formation formation(String pieceId, {int sun = 9990}) => Formation(
      sunValue: sun,
      pieces: [Piece(id: pieceId, type: 'pea', row: 0, col: 0, layer: 10)]);
  final original = formation('original');
  await repo.saveArchive(
      id: 'active', name: '当前正在编辑', document: original.toJson());
  await repo.saveArchive(
      id: 'copy',
      name: '副本旧内容',
      document: formation('copy', sun: 100).toJson());
  await repo.saveArchive(
      id: 'ignored',
      updateId: 'copy',
      name: '重复副本',
      document: formation('copy').toJson());
  await repo.saveArchive(
      id: 'note',
      name: '有独立备注',
      document: formation('note').toJson(),
      note: '保留的备注');
  await repo.saveArchive(
      id: 'tags',
      name: '有独立标签',
      document: formation('tags').toJson(),
      tags: ['保留标签']);
  await repo.saveArchive(
      id: 'favorite', name: '收藏版本', document: formation('favorite').toJson());
  await repo.updateArchiveMetadata('favorite', favorite: true);
  final boundary = GlobalKey();
  final h = ParityHarness(boundary,
      await Directory('${Directory.systemTemp.path}/pvz-archive-dedup-ui').create(recursive: true));
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          home: app.LibraryPage(repository: repo, activeDraftId: 'active'))));

  await h.settle();
  await h.settle();
  Future<void> until(bool Function() condition, String reason) async {
    for (var attempt = 0; attempt < 80; attempt++) {
      if (condition()) return;
      await h.settle();
    }
    throw StateError(reason);
  }

  bool keyed(String key) => h.all((w) => w.key == ValueKey(key)).isNotEmpty;
  bool textContains(String text) =>
      h.all((w) => w is Text && (w.data ?? '').contains(text)).isNotEmpty;
  Future<void> tap(String key) =>
      h.tapElement(h.find((w) => w.key == ValueKey(key)));
  Future<String> databaseState() async {
    final records = await repo.listArchives();
    records.sort((a, b) => a.id.compareTo(b.id));
    return jsonEncode([
      for (final record in records)
        {
          'id': record.id,
          'name': record.name,
          'document': record.document,
          'note': record.note,
          'tags': record.tags,
          'favorite': record.favorite,
          'updated': record.updatedAt.toIso8601String(),
          'versions': [
            for (final version in await repo.listVersions(record.id)) version.id
          ],
        }
    ]);
  }

  await until(
      () => keyed('library-deduplicate'), 'Library deduplicate button missing');
  final initial = await databaseState();
  h.expect(
      (await repo.planDuplicateArchives(protectedArchiveIds: {'active'}))
              .removableCount ==
          1,
      'Metadata differences were considered duplicates');
  h.expect(
      await databaseState() == initial, 'Read-only plan wrote to database');

  await tap('library-section-预制名阵');
  h.expect(!keyed('library-deduplicate'),
      'Deduplicate action leaked into built-ins');
  await tap('library-section-我的存档');
  await tap('library-deduplicate');
  await until(
      () => keyed('archive-dedup-dialog'), 'Duplicate preview did not open');
  h.expect(
      await databaseState() == initial, 'Preview removed or changed archives');
  h.expect(textContains('当前正在编辑'),
      'Protected current archive is not the planned keeper');
  await tap('archive-dedup-cancel');
  await until(
      () => !keyed('archive-dedup-dialog'), 'Cancel did not close preview');
  h.expect(
      await databaseState() == initial, 'Cancel modified archives or history');

  await tap('library-deduplicate');
  await until(() => keyed('archive-dedup-dialog'), 'Second preview missing');
  await repo.updateArchiveMetadata('copy', note: '预览期间被外部编辑');
  final externallyEdited = await databaseState();
  await tap('archive-dedup-confirm');
  await until(() => textContains('去重失败'), 'Stale plan failure was not shown');
  h.expect(await databaseState() == externallyEdited,
      'Stale preview deleted or changed a newly edited archive');
  await repo.updateArchiveMetadata('copy', note: '');
  final dynamic page =
      (h.find((w) => w is app.LibraryPage) as StatefulElement).state;
  await page.refresh();
  await h.settle();

  final copyHistory = await repo.listVersions('copy');
  final keeperHistory = await repo.listVersions('active');
  await tap('library-deduplicate');
  await until(
      () => keyed('archive-dedup-dialog'), 'Confirmed plan preview missing');
  await tap('archive-dedup-confirm');
  await until(
      () => textContains('已清理 1 个重复存档'), 'Deduplication did not complete');
  final kept = await repo.listArchives();
  h.expect(
      kept.length == 4 &&
          kept.any((r) => r.id == 'active') &&
          !kept.any((r) => r.id == 'copy') &&
          kept.any((r) => r.id == 'note' && r.note == '保留的备注') &&
          kept.any((r) => r.id == 'tags' && r.tags.contains('保留标签')) &&
          kept.any((r) => r.id == 'favorite' && r.favorite),
      'Confirmation removed protected or distinct-metadata records');
  final preserved = await repo.listVersions('active');
  h.expect(
      preserved.length == copyHistory.length + keeperHistory.length + 1 &&
          copyHistory.every((old) => preserved.any((v) => v.id == old.id)) &&
          preserved.any((v) => v.name == '重复副本'),
      'Duplicate history or current head snapshot was discarded');
  h.expect((await repo.listVersions('copy')).isEmpty,
      'Removed archive retained orphaned versions');
  final afterConfirm = await databaseState();
  await tap('library-deduplicate');
  await until(() => textContains('没有可清理的重复存档'), 'No-duplicates result missing');
  h.expect(
      !keyed('archive-dedup-confirm') && await databaseState() == afterConfirm,
      'Empty plan exposed destructive confirmation or wrote data');
  await h.tapElement(h.find((w) =>
      w is TextButton && w.child is Text && (w.child as Text).data == '确定'));
  final nativeCalls = <String>[];
  ParityBinding.handlers['pvz_formation_editor/library'] = (call) async {
    nativeCalls.add(call.method);
    if (call.method == 'ready') return {'dataPath': '${directory.path}/fixture.sqlite', 'activeDraftId': 'active'};
    if (call.method == 'prepareDedup') return ['active'];
    throw MissingPluginException('Unexpected forwarding: ${call.method}');
  };
  runApp(RepaintBoundary(key: boundary, child: MaterialApp(key: UniqueKey(),
      home: app.LibraryPage(repository: repo, independent: true))));
  await h.settle();
  await h.settle();
  await until(() => keyed('library-deduplicate'), 'Independent library missing');
  await tap('library-deduplicate');
  await until(() => textContains('没有可清理的重复存档'), 'Independent library must display its own dedup feedback');
  h.expect(nativeCalls.contains('prepareDedup') && !nativeCalls.contains('openEditor'),
      'Dedup dialog must remain in the library instead of forwarding UI to the editor');
  await h.tapElement(h.find((w) => w is TextButton && w.child is Text && (w.child as Text).data == '确定'));
  h.expect(h.errors.isEmpty,
      h.errors.map((error) => error.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS library dedup entry, dry-run/cancel preservation, stale-plan error, protected keeper, metadata distinctions, complete history retention and no-duplicates feedback');
  runApp(const SizedBox.shrink());
  await h.settle();
  await repo.close();
  await directory.delete(recursive: true);
  exit(0);
}
