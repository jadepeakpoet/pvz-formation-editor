import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> rejected(Future<void> future) async {
  bool rejected = false;
  try {
    await future;
  } catch (_) {
    rejected = true;
  }
  check(rejected, 'operation must reject');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = <Map<String, dynamic>>[];
  Future<void> test(String name, Future<void> Function() run) async {
    try {
      await run();
      results.add({'id': name, 'status': 'pass'});
    } catch (e, s) {
      results.add({'id': name, 'status': 'fail', 'error': '$e', 'stack': '$s'});
    }
  }

  final dir = await Directory.systemTemp.createTemp('pvz-editor-tabs-');
  final repo = await FormationRepository.open('${dir.path}/test.sqlite');
  final tabs = EditorTabsController(repo);
  await test('empty-tabs-stay-transient', () async {
    await tabs.ready;
    check((await repo.listArchives()).isEmpty,
        'initial blank archive must be deferred');
    await tabs.newBlank();
    check(tabs.sessions.length == 2, 'newblank appended');
    check(
        (await repo.listArchives()).isEmpty &&
            tabs.sessions.every((s) => s.sourceArchiveId == null),
        'untouched empty tabs must not create archives');
  });
  final a = tabs.active;
  await test('independent-history-and-switch-flush', () async {
    a.execute(
        '豌豆',
        Formation(pieces: [
          Piece(id: 'pea', type: 'pea', row: 0, col: 0, layer: 10)
        ]));
    final b = EditorSession(repo, name: '第二阵型');
    await tabs.open(b, newTab: true);
    check(
        (await repo.listArchives()).any((d) =>
            d.id == a.id &&
            Formation.fromJson(d.document).pieces.single.type == 'pea'),
        'old draft saved before switch');
    b.execute('阳光', b.document.copy(sunValue: 1234));
    await tabs.activate(tabs.sessions.indexOf(a));
    a.undo();
    check(a.document.pieces.isEmpty && a.canRedo, 'oldhistory survives');
    check(b.document.sunValue == 1234 && b.canUndo, 'otherhistory untouched');
    check(
        (await repo.listArchives())
                .firstWhere((d) => d.id == b.id)
                .document['sunValue'] ==
            1234,
        'switch flushed second draft');
  });
  await test('duplicate-editable-draft-reuses-session', () async {
    final count = tabs.sessions.length;
    final clone = EditorSession(repo, id: a.id, name: '重复草稿');
    await tabs.open(clone, newTab: true);
    check(tabs.sessions.length == count && identical(tabs.active, a),
        'duplicate must activate existing session');
  });
  await test('before-switch-finishes-gesture-before-flush', () async {
    final old = tabs.active;
    int calls = 0;
    tabs.beforeSwitch = () async {
      calls++;
      old.execute('完成手势', old.document.copy(sunValue: 888));
      return true;
    };
    await tabs.newBlank();
    tabs.beforeSwitch = null;
    check(calls == 1, 'hook once');
    check(
        (await repo.listArchives())
                .firstWhere((d) => d.id == old.id)
                .document['sunValue'] ==
            888,
        'gesture saved before activation');
  });
  await test('before-switch-rejection-preserves-session-and-ownership',
      () async {
    final old = tabs.active, count = tabs.sessions.length;
    final incoming = EditorSession(repo);
    tabs.beforeSwitch = () async => false;
    await rejected(tabs.open(incoming, newTab: true));
    check(identical(tabs.active, old) && tabs.sessions.length == count,
        'reject preserves active tab');
    incoming.rename('调用方仍持有');
    check(incoming.name == '调用方仍持有', 'failedopen remains caller-owned');
    incoming.dispose();
    await rejected(tabs.close(tabs.activeIndex));
    check(identical(tabs.active, old), 'activeclose reject preserves tab');
    tabs.beforeSwitch = null;
  });
  await test('queued-operations-preserve-requested-tab-identity', () async {
    final first = tabs.sessions.first, last = tabs.sessions.last;
    final f1 = tabs.activate(0), f2 = tabs.activate(tabs.sessions.length - 1);
    await Future.wait([f1, f2]);
    check(identical(tabs.active, last) && !identical(first, last),
        'queued activation order');
  });
  await test('close-one-keeps-other-history', () async {
    final kept = tabs.sessions.first;
    kept.execute('保留', kept.document.copy(sunValue: 222));
    final closing = tabs.active;
    await tabs.close(tabs.activeIndex);
    check(
        !tabs.sessions.contains(closing) &&
            tabs.sessions.contains(kept) &&
            kept.canUndo,
        'only closed session removed');
  });
  await test('close-last-creates-fresh-transient-blank', () async {
    while (tabs.sessions.length > 1) {
      await tabs.close(tabs.sessions.length - 1);
    }
    final old = tabs.active.id;
    await tabs.active.flush(forceSave: true);
    final before = (await repo.listArchives()).length;
    await tabs.close(0);
    check(
        tabs.sessions.length == 1 &&
            tabs.active.id != old &&
            !tabs.active.canUndo,
        'fresh blank after last close');
    check(
        (await repo.listArchives()).length == before &&
            tabs.active.sourceArchiveId == null,
        'replacement blank stays transient');
  });
  await test('default-open-replaces-only-active-after-saving', () async {
    final retained = tabs.active;
    await tabs.newBlank();
    final previous = tabs.active;
    previous.rename('被替换但保存的草稿');
    final count = tabs.sessions.length;
    final replacement = EditorSession(repo, name: '替换标签');
    await tabs.open(replacement);
    check(tabs.sessions.length == count && identical(tabs.active, replacement),
        'defaultopen replaces current');
    check(tabs.sessions.contains(retained) && !tabs.sessions.contains(previous),
        'other session preserved');
    check(
        (await repo.listArchives())
            .any((d) => d.id == previous.id && d.name == '被替换但保存的草稿'),
        'previous flushed before replacement');
  });
  await test('navigation-restores-name-document-and-edit-history', () async {
    final first = tabs.active;
    first.rename('前一页阵型');
    first.execute('保留编辑', first.document.copy(sunValue: 4321));
    final second = EditorSession(repo, name: '后一页阵型');
    await tabs.open(second);
    check(tabs.canGoBack && !tabs.canGoForward,
        'back available after navigation');
    await tabs.goBack();
    check(
        identical(tabs.active, first) &&
            tabs.active.name == '前一页阵型' &&
            tabs.active.document.sunValue == 4321 &&
            tabs.active.canUndo,
        'back restores original session, name and undo history');
    check(tabs.canGoForward, 'forward available after back');
    await tabs.goForward();
    check(identical(tabs.active, second), 'forward restores next session');
    await tabs.goBack();
    final third = EditorSession(repo, name: '分支阵型');
    await tabs.open(third);
    check(identical(tabs.active, third) && !tabs.canGoForward,
        'new navigation discards forward branch');
    await tabs.goBack();
    check(identical(tabs.active, first), 'branch retains preceding session');
    await tabs.open(EditorSession(repo, id: third.id, name: '重复导航'));
    check(identical(tabs.active, third), 'retained history entry is reused');
  });
  await test('reopening-historical-page-appends-navigation', () async {
    final local = EditorTabsController(repo);
    await local.ready;
    await local.active.flush(forceSave: true);
    final first = local.active;
    final second = EditorSession(repo, name: '历史再访问B');
    await local.open(second);
    await local.open(EditorSession(repo, id: first.id, name: '重复A'));
    check(identical(local.active, first) && local.canGoBack,
        'historical visit appends existing session');
    check(local.allSessions.length == 2,
        'one owner per session despite repeated visits');
    await local.goBack();
    check(identical(local.active, second), 'back returns page before revisit');
    await local.goForward();
    check(identical(local.active, first), 'forward returns revisited page');
    await local.goBack();
    await local.open(EditorSession(repo, name: '历史分支C'));
    await local.goBack();
    await local.goBack();
    check(identical(local.active, first),
        'discarded duplicate history retains original owner');
    first.rename('仍可编辑的A');
    check(await local.flushAll(), 'remaining shared history session saves');
    local.dispose();
  });
  await test('forced-navigation-retains-previous-archive-version', () async {
    final original = EditorSession(repo,
        id: 'original-version',
        sourceArchiveId: 'shared-archive',
        name: '旧版本名称',
        document: Formation(sunValue: 123),
        readOnly: true);
    final local = EditorTabsController(repo, initial: original);
    await local.ready;
    await local.active.flush(forceSave: true);
    final restored = EditorSession(repo,
        id: 'restored-version',
        sourceArchiveId: 'shared-archive',
        name: '恢复版本名称',
        document: Formation(sunValue: 456),
        readOnly: true);
    await local.open(restored, forceNavigation: true);
    check(identical(local.active, restored),
        'forced open keeps incoming version');
    await local.goBack();
    check(
        identical(local.active, original) &&
            local.active.name == '旧版本名称' &&
            local.active.document.sunValue == 123,
        'back restores previous version and name');
    await local.goForward();
    check(
        identical(local.active, restored) &&
            local.active.document.sunValue == 456,
        'forward restores new archive version');
    await local.open(EditorSession(repo, id: restored.id, readOnly: true),
        forceNavigation: true);
    check(local.allSessions.length == 2,
        'forced navigation still deduplicates session id');
    local.dispose();
  });
  await test('unified-undo-redo-orders-edits-titles-and-navigation', () async {
    final local = EditorTabsController(repo);
    await local.ready;
    await local.active.flush(forceSave: true);
    final first = local.active;
    final originalName = first.name;
    first.execute('修改阳光', first.document.copy(sunValue: 717));
    first.rename('修改后的名称');
    final second = EditorSession(repo, name: '新页面');
    await local.open(second);
    second.execute('新页编辑', second.document.copy(sunValue: 818));
    await local.undo();
    check(identical(local.active, second) && second.document.sunValue != 818,
        'undo latest document command before navigation');
    await local.undo();
    check(identical(local.active, first) && first.name == '修改后的名称',
        'undo navigation retains prior title');
    await local.undo();
    check(first.name == originalName && first.document.sunValue == 717,
        'undo title separately from document');
    await local.undo();
    check(first.document.sunValue != 717 && !local.canUndo,
        'undo earliest document command');
    await local.redo();
    await local.redo();
    check(first.name == '修改后的名称' && first.document.sunValue == 717,
        'redo document then title');
    await local.redo();
    check(identical(local.active, second), 'redo navigation');
    await local.redo();
    check(
        second.document.sunValue == 818 && !local.canRedo, 'redo latest edit');
    check(await local.flushAll(), 'unified history flushes');
    local.dispose();
  });
  await test('new-navigation-redo-skips-preexisting-undone-commands', () async {
    final local = EditorTabsController(repo);
    await local.ready;
    await local.active.flush(forceSave: true);
    final first = local.active;
    first.execute(
        '种植',
        Formation(pieces: [
          Piece(id: 'redo-pea', type: 'pea', row: 0, col: 0, layer: 10)
        ]));
    first.execute('清空', first.document.copy(pieces: []));
    await local.undo();
    check(first.document.pieces.length == 1, 'clear is undone');
    final originalName = first.name;
    first.rename('修改名称');
    await local.undo();
    check(first.name == originalName, 'rename undone before navigation');
    final second = EditorSession(repo, name: '另一阵型');
    await local.open(second);
    await local.undo();
    check(identical(local.active, first) && first.name == originalName,
        'navigation undo returns exact departure state');
    await local.redo();
    check(identical(local.active, second) && first.name == originalName,
        'redo navigation skips rename undone before departure');
    check(await local.flushAll(), 'departure boundary flushes');
    local.dispose();
  });
  await test('unified-undo-respects-revisit-boundary-and-edit-branch',
      () async {
    final local = EditorTabsController(repo);
    await local.ready;
    await local.active.flush(forceSave: true);
    final first = local.active;
    first.execute('A编辑', first.document.copy(sunValue: 919));
    final second = EditorSession(repo, name: 'B');
    await local.open(second);
    await local.open(EditorSession(repo, id: first.id));
    await local.undo();
    check(identical(local.active, second) && first.document.sunValue == 919,
        'undo revisit navigates B before touching old A commands');
    await local.undo();
    check(identical(local.active, first), 'undo initial navigation');
    await local.undo();
    check(first.document.sunValue != 919, 'then undo original A edit');
    await local.redo();
    await local.redo();
    check(identical(local.active, second), 'redo edit and first navigation');
    second.rename('B的新分支');
    check(!local.canGoForward && !local.canRedo,
        'new edit immediately invalidates forward navigation');
    await local.undo();
    check(identical(local.active, second) && second.name == 'B',
        'new branch title remains undoable');
    await local.undo();
    check(identical(local.active, first) && first.document.sunValue == 919,
        'branch cleanup retains shared A session');
    check(await local.flushAll(), 'retired branch cleanup is safe');
    local.dispose();
  });
  await test('navigation-hook-rejection-preserves-page', () async {
    final current = tabs.active;
    tabs.beforeSwitch = () async => false;
    await rejected(tabs.goBack());
    check(identical(tabs.active, current),
        'rejected navigation retains current page');
    tabs.beforeSwitch = null;
  });
  await test('history-flush-and-tab-local-navigation', () async {
    final previousTab = tabs.activeIndex;
    final previousPage = tabs.active;
    await tabs.newBlank();
    check(
        !tabs.canGoBack && !tabs.canGoForward, 'new tab has separate history');
    await tabs.activate(previousTab);
    check(identical(tabs.active, previousPage) && tabs.canGoBack,
        'switching tabs preserves navigation cursor');
    await tabs.goBack();
    final retained = tabs.active;
    await tabs.goForward();
    retained.rename('后台历史名称也保存');
    check(await tabs.flushAll(), 'flush includes hidden history entries');
    check(
        (await repo.listArchives()).any((archive) =>
            archive.id == retained.id && archive.name == '后台历史名称也保存'),
        'hidden session is persisted');
  });
  await test('read-only-tabs-reuse-without-persisting', () async {
    final before = (await repo.listArchives()).length;
    final ro = EditorSession(repo, id: 'archive-readonly', readOnly: true);
    await tabs.open(ro, newTab: true);
    await tabs.open(EditorSession(repo, id: ro.id, readOnly: true),
        newTab: true);
    check(tabs.sessions.where((s) => s.id == ro.id).length == 1,
        'readonly duplicate');
    check(await tabs.flushAll(), 'flushall success');
    check((await repo.listArchives()).length == before,
        'readonly preview never persisted');
  });
  await test('archive-removal-prunes-retained-pages-only', () async {
    final local = EditorTabsController(repo);
    await local.ready;
    await local.active.flush(forceSave: true);
    final archived = local.active;
    final archiveId = archived.sourceArchiveId!;
    final next = EditorSession(repo, name: '删除历史后保留此页');
    await local.open(next);
    check(local.allSessions.contains(archived), 'allSessions includes history');
    await local.removeArchive(archiveId);
    check(
        identical(local.active, next) &&
            local.sessions.length == 1 &&
            !local.canGoBack &&
            !local.allSessions.contains(archived),
        'archive removed from history while unrelated current page survives');
    await repo.deleteArchive(archiveId);
    await local.goBack();
    check(identical(local.active, next), 'deleted archive cannot return');
    local.beforeSwitch = () async => false;
    await rejected(local.removeArchive(next.sourceArchiveId!));
    check(identical(local.active, next) && local.allSessions.length == 1,
        'prepare failure preserves history');
    local.beforeSwitch = null;
    await local.removeArchive(next.sourceArchiveId!);
    check(local.sessions.length == 1 && !identical(local.active, next),
        'removing last entry creates transient blank');
    local.dispose();
  });
  await test('archive-removal-save-failure-preserves-history', () async {
    final brokenRepo =
        await FormationRepository.open('${dir.path}/remove-failure.sqlite');
    final local = EditorTabsController(brokenRepo);
    await local.ready;
    await local.active.flush(forceSave: true);
    final archived = local.active;
    final archiveId = archived.sourceArchiveId!;
    await local.open(EditorSession(brokenRepo, name: '当前阵型'));
    archived.rename('历史页待保存');
    final current = local.active;
    await brokenRepo.close();
    await rejected(local.removeArchive(archiveId));
    check(
        identical(local.active, current) &&
            local.canGoBack &&
            local.allSessions.contains(archived),
        'save failure leaves history intact');
    local.dispose();
  });
  await test('save-failure-blocks-switch-close-and-exit', () async {
    final failedRepo =
        await FormationRepository.open('${dir.path}/failed.sqlite');
    final bad = EditorSession(failedRepo);
    final failedTabs = EditorTabsController(failedRepo, initial: bad);
    bad.rename('待保存');
    await failedRepo.close();
    final incoming = EditorSession(failedRepo);
    await rejected(failedTabs.open(incoming, newTab: true));
    check(identical(failedTabs.active, bad) && failedTabs.sessions.length == 1,
        'save failure preserves active');
    await rejected(failedTabs.close(0));
    check(failedTabs.sessions.length == 1, 'cannot close failed draft');
    check(!await failedTabs.flushAll(), 'exit cannot claim saved');
    incoming.dispose();
    failedTabs.dispose();
  });
  await test('save-failure-blocks-existing-tab-activation', () async {
    final brokenRepo =
        await FormationRepository.open('${dir.path}/activate-failure.sqlite');
    final brokenTabs = EditorTabsController(brokenRepo);
    await brokenTabs.newBlank();
    final current = brokenTabs.active;
    current.rename('保存失败保留此页');
    await brokenRepo.close();
    await rejected(brokenTabs.activate(0));
    check(
        identical(brokenTabs.active, current) &&
            brokenTabs.sessions.length == 2,
        'existing activation preserves failing draft');
    brokenTabs.dispose();
  });
  final saved = await tabs.flushAll();
  check(saved, 'final healthy flush');
  tabs.dispose();
  await repo.close();
  await dir.delete(recursive: true);
  final report = {
    'suite': 'editor-tabs',
    'runtime':
        'real Flutter engine and temporary SQLite; no native window automation',
    'results': results,
    'passed': results.where((r) => r['status'] == 'pass').length,
    'failed': results.where((r) => r['status'] == 'fail').length
  };
  File('${Directory.systemTemp.path}/pvz-editor-tabs-report.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(jsonEncode(report));
  exit(report['failed'] == 0 ? 0 : 1);
}
