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

class Fixture {
  final Directory directory;
  FormationRepository repository;
  final sessions = <EditorSession>[];
  final controllers = <EditorTabsController>[];
  Fixture(this.directory, this.repository);
  EditorSession session({Formation? document, String name = '新建阵型'}) {
    final value = EditorSession(repository, document: document, name: name);
    sessions.add(value);
    return value;
  }

  EditorTabsController tabs({EditorSession? initial}) {
    final value = EditorTabsController(repository, initial: initial);
    controllers.add(value);
    return value;
  }

  Future<void> reopen() async {
    await repository.close();
    repository =
        await FormationRepository.open('${directory.path}/library.sqlite');
  }

  Future<void> dispose() async {
    for (final value in controllers) {
      value.dispose();
    }
    for (final value in sessions) {
      value.dispose();
    }
    await repository.close();
    await directory.delete(recursive: true);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final results = <Map<String, Object?>>[];
  Future<void> test(String name, Future<void> Function(Fixture) run) async {
    final directory =
        await Directory.systemTemp.createTemp('pvz-startup-resume-');
    final fixture = Fixture(directory,
        await FormationRepository.open('${directory.path}/library.sqlite'));
    try {
      await run(fixture);
      results.add({'id': name, 'status': 'pass'});
    } catch (error, stack) {
      results.add(
          {'id': name, 'status': 'fail', 'error': '$error', 'stack': '$stack'});
    } finally {
      await fixture.dispose();
    }
  }

  await test('default-blank-stays-transient-until-explicit-save', (f) async {
    final implicit = f.session(), explicit = f.session(document: Formation());
    await Future.wait([implicit.flush(), explicit.flush()]);
    check((await f.repository.listArchives()).isEmpty,
        'Constructing/flushing default blank created archives');
    check(implicit.sourceArchiveId == null && explicit.sourceArchiveId == null,
        'Transient blank acquired archive ID');
    await explicit.flush(forceSave: true);
    check(
        (await f.repository.listArchives()).length == 1 &&
            explicit.sourceArchiveId != null,
        'Explicit blank save was ignored');
    await explicit.flush();
    check((await f.repository.listArchives()).length == 1,
        'Repeated flush duplicated explicit blank');
  });
  await test('nondefault-document-or-name-autosaves', (f) async {
    final changed = f.session(document: Formation(sunValue: 123));
    final named = f.session(name: '用户命名的空阵');
    final renamed = f.session()..rename('随后重命名');
    await Future.wait([changed.flush(), named.flush(), renamed.flush()]);
    final archives = await f.repository.listArchives();
    check(
        archives.length == 3 &&
            [changed, named, renamed].every((s) => s.matchesArchive),
        'Meaningful documents and names must autosave');
  });
  await test('first-edit-clear-undo-redo-remain-persistent', (f) async {
    final value = f.session();
    final planted = Formation(
        pieces: [Piece(id: 'pea', type: 'pea', row: 0, col: 0, layer: 10)]);
    value.execute('种植', planted);
    await value.flush();
    final id = value.sourceArchiveId;
    check(
        id != null &&
            (await f.repository.listArchives())
                    .single
                    .document['objects']
                    .length ==
                1,
        'First edit did not save');
    value.execute('清空', Formation());
    await value.flush();
    check(
        value.sourceArchiveId == id &&
            (await f.repository.listArchives())
                .single
                .document['objects']
                .isEmpty,
        'Clearing existing archive skipped save');
    value.undo();
    await value.flush();
    check(
        (await f.repository.listArchives()).single.document['objects'].length ==
            1,
        'Undo did not persist restored content');
    value.redo();
    await value.flush();
    check(
        (await f.repository.listArchives()).single.document['objects'].isEmpty,
        'Redo did not persist empty archive');
  });
  await test('startup-resume-prefers-pointer-over-latest-update', (f) async {
    final a = await f.repository.saveArchive(
        id: 'a', name: '上次阵型', document: Formation(sunValue: 111).toJson());
    await f.repository.rememberOpenedArchive(a.id);
    await f.repository.saveArchive(
        id: 'b', name: '后来更新', document: Formation(sunValue: 222).toJson());
    await f.reopen();
    final resumed = await EditorSession.resume(f.repository);
    f.sessions.add(resumed);
    check(
        resumed.sourceArchiveId == a.id &&
            resumed.document.sunValue == 111 &&
            !resumed.readOnly &&
            resumed.matchesArchive,
        'Startup selected update order instead of last activation');
    await resumed.flush();
    check((await f.repository.listArchives()).length == 2,
        'Startup duplicated archive');
  });
  await test('startup-bootstrap-skips-old-generated-blanks-without-deleting',
      (f) async {
    final empty = await EditorSession.resume(f.repository);
    f.sessions.add(empty);
    await empty.flush();
    check((await f.repository.listArchives()).isEmpty,
        'First startup wrote blank');
    await f.repository.saveArchive(
        id: 'work',
        name: '真实阵型',
        document: Formation(seedSlots: ['pea']).toJson());
    await f.repository.saveArchive(
        id: 'old-blank', name: '新建阵型（38）', document: Formation().toJson());
    final resumed = await EditorSession.resume(f.repository);
    f.sessions.add(resumed);
    check(
        resumed.sourceArchiveId == 'work' &&
            resumed.document.seedSlots.single == 'pea',
        'Bootstrap selected old automatic empty page');
    check((await f.repository.listArchives()).length == 2,
        'Bootstrap deleted old records');
    await f.repository.rememberOpenedArchive('old-blank');
    final explicitBlank = await EditorSession.resume(f.repository);
    f.sessions.add(explicitBlank);
    check(explicitBlank.sourceArchiveId == 'old-blank',
        'Recorded empty archive was not restored');
  });
  await test('last-opened-pointer-survives-reopen-and-rejects-missing',
      (f) async {
    final a = await f.repository.saveArchive(
        id: 'a', name: '阵A', document: Formation(sunValue: 111).toJson());
    final b = await f.repository.saveArchive(
        id: 'b', name: '阵B', document: Formation(sunValue: 222).toJson());
    await f.repository.rememberOpenedArchive(a.id);
    await f.repository.rememberOpenedArchive('missing-id');
    check((await f.repository.lastOpenedArchive())?.id == a.id,
        'Missing ID replaced valid pointer');
    await f.repository.rememberOpenedArchive(b.id);
    await f.reopen();
    final restored = await f.repository.lastOpenedArchive();
    check(
        restored?.id == b.id &&
            Formation.fromJson(restored!.document).sunValue == 222,
        'Reopened DB lost last-active document');
    await f.repository.deleteArchive(b.id);
    check(await f.repository.lastOpenedArchive() == null,
        'Deleted archive returned stale document');
    await f.reopen();
    check(await f.repository.lastOpenedArchive() == null,
        'Deleted pointer resurrected after DB reopen');
  });
  await test('tab-ready-open-activate-history-and-flushall-remember-active',
      (f) async {
    final initial = EditorSession(f.repository, name: '起始阵');
    final tabs = f.tabs(initial: initial);
    await tabs.ready;
    check(
        (await f.repository.lastOpenedArchive())?.id == initial.sourceArchiveId,
        'Initial named tab was not remembered');
    final b = EditorSession(f.repository, name: '阵B');
    await tabs.open(b, newTab: true);
    final c = EditorSession(f.repository, name: '阵C');
    await tabs.open(c, newTab: true);
    await tabs.activate(1);
    check((await f.repository.lastOpenedArchive())?.id == b.sourceArchiveId,
        'Last activated tab was not remembered');
    final d = EditorSession(f.repository, name: '阵D');
    await tabs.open(d);
    check((await f.repository.lastOpenedArchive())?.id == d.sourceArchiveId,
        'Current-tab replacement was not remembered');
    await tabs.goBack();
    check((await f.repository.lastOpenedArchive())?.id == b.sourceArchiveId,
        'Back navigation was not remembered');
    await tabs.goForward();
    check((await f.repository.lastOpenedArchive())?.id == d.sourceArchiveId,
        'Forward navigation was not remembered');
    await tabs.activate(0);
    check(await tabs.flushAll(), 'Flush all failed');
    check(
        (await f.repository.lastOpenedArchive())?.id == initial.sourceArchiveId,
        'Flush all remembered iteration-last instead of active');
    await tabs.close(0);
    check(
        (await f.repository.lastOpenedArchive())?.id ==
            tabs.active.sourceArchiveId,
        'Closing active tab did not remember replacement');
  });
  await test('blank-tabs-close-without-archives-or-pointer-overwrite',
      (f) async {
    final initial = EditorSession(f.repository, name: '最后打开的阵');
    final tabs = f.tabs(initial: initial);
    await tabs.ready;
    final id = initial.sourceArchiveId;
    final before = (await f.repository.listArchives()).length;
    await tabs.newBlank();
    await tabs.flushAll();
    check(
        tabs.active.sourceArchiveId == null &&
            (await f.repository.listArchives()).length == before,
        'New blank autosaved');
    check((await f.repository.lastOpenedArchive())?.id == id,
        'Blank tab overwrote previous valid pointer');
    await tabs.close(tabs.activeIndex);
    await tabs.close(0);
    await tabs.flushAll();
    check(tabs.sessions.length == 1 && tabs.active.sourceArchiveId == null,
        'Closing final tab did not leave transient blank');
    check(
        (await f.repository.listArchives()).length == before &&
            (await f.repository.lastOpenedArchive())?.id == id,
        'Blank replacement created archive or lost resume target');
  });
  stdout.writeln(jsonEncode({
    'cases': results,
    'passed': results.where((r) => r['status'] == 'pass').length,
    'total': results.length
  }));
  exit(results.every((r) => r['status'] == 'pass') ? 0 : 1);
}
