// Native three-engine tab acceptance target. Temporary SQLite; no channel mocks.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'library_windows.dart' as helper;

const base = '/tmp/pvz-tabs-native';
const native = MethodChannel('pvz_formation_editor/windows');
const library = MethodChannel('pvz_formation_editor/library');
@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  await app.toolboxMain();
  final run = (await helper.read('$base/meta.json'))!['run'] as String;
  int previous = -1;
  while (true) {
    final state = WindowBridge.latestState;
    if (state != null && WindowBridge.supported) {
      final element =
          helper.find((w) => w is app.EditorPage) as StatefulElement?;
      final dynamic controller = element?.state;
      await helper.write('$base/$run/toolbox-state.json',
          {...state, 'liveOutput': controller?.outputFormation.text ?? ''});
    }
    final cmd = await helper.read('$base/$run/toolbox-command.json');
    if (cmd != null && cmd['id'] != previous) {
      previous = cmd['id'] as int;
      final result = await native.invokeMethod('editState', cmd['state']);
      await helper.write(
          '$base/$run/toolbox-ack.json', {'id': previous, 'accepted': result});
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
}

@pragma('vm:entry-point')
Future<void> libraryMain() async {
  await app.libraryMain();
  final run = (await helper.read('$base/meta.json'))!['run'] as String;
  int previous = -1;
  while (true) {
    final cmd = await helper.read('$base/$run/library-command.json');
    if (cmd == null || cmd['id'] == previous) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      continue;
    }
    previous = cmd['id'] as int;
    final ack = <String, dynamic>{'id': previous, 'status': 'pass'};
    try {
      await library.invokeMethod('activateWindow');
      await helper.until(
          () =>
              helper.find((w) =>
                  w.key == const ValueKey('library-section-我的存档') ||
                  w.key == const ValueKey('library-detail-back')) !=
              null,
          'Library UI focused and loaded');
      if (helper.find((w) => w.key == const ValueKey('library-detail-back')) !=
          null) {
        await helper.key('library-detail-back', library);
      }
      await helper.key('library-section-我的存档', library);
      final archiveId =
          cmd['name'] == 'new-tab' ? 'qa-archive-second' : 'qa-archive';
      await helper.key('library-item-archive:$archiveId', library);
      switch (cmd['name']) {
        case 'current':
          await helper.key('library-open-current', library);
          break;
        case 'new-tab':
          await helper.key('library-open-tab', library);
          break;
        case 'copy':
          await helper.key('library-copy-code', library);
          ack['clipboard'] = (await Clipboard.getData('text/plain'))?.text;
          break;
        default:
          throw StateError('Unknown library command');
      }
    } catch (e, stack) {
      ack.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
    }
    await helper.write('$base/$run/library-ack.json', ack);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const MethodChannel('pvz_formation_editor/lifecycle')
      .setMethodCallHandler((call) async {
    if (call.method != 'prepareExit') throw MissingPluginException();
    for (final guard in app.exitGuards.reversed.toList()) {
      if (!await guard()) return false;
    }
    return true;
  });
  await OriginalAssets.ensureLoaded();
  final run = '${DateTime.now().microsecondsSinceEpoch}-$pid';
  await Directory('$base/$run').create(recursive: true);
  await helper.write('$base/meta.json', {'run': run, 'pid': pid});
  final path = '$base/$run/test.sqlite';
  final repo = await FormationRepository.open(path);
  final initial = EditorSession(repo, name: 'Original blank');
  final tabs = EditorTabsController(repo, initial: initial);
  final source = Formation(
      mapId: 'day',
      pieces: [Piece(id: 'source', type: 'pea', row: 0, col: 0, layer: 10)]);
  await repo.saveArchive(
      id: 'qa-archive', name: 'Native tabs archive', document: source.toJson());
  await repo.saveArchive(
      id: 'qa-archive-second',
      name: 'Native second archive',
      document: source.copy(pieces: [
        Piece(id: 'second', type: 'sunflower', row: 1, col: 1, layer: 10)
      ]).toJson());
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  runApp(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: app.EditorWorkspace(
          controller: tabs, libraryPath: path, continueArchive: (_) async {})));
  final rows = <Map<String, dynamic>>[];
  int sequence = 0;
  dynamic page() =>
      (helper.find((w) => w is app.EditorPage) as StatefulElement).state;
  Future<Map<String, dynamic>> diag() async => Map<String, dynamic>.from(
      (await native.invokeMethod('diagnostics')) as Map);
  Future<Map<String, dynamic>> command(String name) async {
    final id = ++sequence;
    await helper
        .write('$base/$run/library-command.json', {'id': id, 'name': name});
    final end = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(end)) {
      final ack = await helper.read('$base/$run/library-ack.json');
      if (ack?['id'] == id) {
        helper.check(
            ack!['status'] == 'pass', 'Library $name: ${ack['error']}');
        return ack;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    throw TimeoutException('Library command $name');
  }

  Future<Map<String, dynamic>> sync() async {
    final end = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(end)) {
      final state = await helper.read('$base/$run/toolbox-state.json');
      if (state?['documentToken'] == page().documentToken &&
          state?['documentJson'] == jsonEncode(tabs.active.document.toJson()) &&
          state?['liveOutput'] ==
              FormationExchange.encode(tabs.active.document)) {
        return state!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    throw TimeoutException('Toolbox token/document/liveOutput convergence');
  }

  Future<void> test(
      String id, Future<void> Function(Map<String, dynamic>) body) async {
    final row = <String, dynamic>{'id': id, 'status': 'pass'};
    try {
      await body(row);
      helper.check(errors.isEmpty, 'Flutter errors $errors');
    } catch (e, stack) {
      row['actualTabs'] = tabs.sessions
          .map((s) => {'name': s.name, 'archive': s.sourceArchiveId})
          .toList();
      row.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
    }
    rows.add(row);
    final report = {
      'scope':
          'actual native three-engine Workspace, library and toolbox; temporary database; no channel mocks',
      'pid': pid,
      'run': run,
      'cases': rows,
      'errors': errors
    };
    await helper.write('$base/$run/report.json', report);
    await helper.write('$base/report.json', report);
  }

  await helper.until(
      () =>
          WindowBridge.supported &&
          helper.find((w) => w.key == const ValueKey('editor-tabs-strip')) !=
              null,
      'Native Workspace ready');
  final originalState = page();
  await test('tabs.library-current-independent', (row) async {
    final before = await diag();
    await helper.key('main-sidebar-library', native);
    await command('current');
    await helper.until(() => tabs.active.sourceArchiveId == 'qa-archive',
        'Library current open');
    helper.check(tabs.sessions.length == 1 && !tabs.active.readOnly,
        'Current opens editable without additional tab');
    helper.check(
        identical(page(), originalState), 'Workspace editor State changed');
    final after = await diag();
    helper.check(
        jsonEncode(before['mainFrame']) == jsonEncode(after['mainFrame']),
        'Library changed main frame');
    row['diagnostics'] = after;
    row['toolbox'] = await sync();
  });
  await test('tabs.library-new-retains-first', (row) async {
    final first = tabs.active;
    await command('new-tab');
    await helper.until(() => tabs.sessions.length == 2, 'Library new tab');
    helper.check(tabs.sessions.first == first && tabs.active.id != first.id,
        'New archive tab did not preserve original work copy');
    await helper.key('editor-tab-${first.id}', native);
    await helper.until(
        () => identical(tabs.active, first), 'Actual tab pointer activation');
    row['toolbox'] = await sync();
    helper.check(
        identical(page(), originalState), 'Tab pointer recreated editor');
  });
  await test('tabs.library-clipboard-toolkit', (row) async {
    final ack = await command('copy');
    helper.check(ack['clipboard'] == FormationExchange.encode(source),
        'Actual native clipboard is not Toolkit source code');
    row['clipboard'] = ack['clipboard'];
  });
  await test('tabs.identical-blank-stale-token-and-close', (row) async {
    while (tabs.sessions.length > 1) {
      await helper.key('editor-close-tab-${tabs.active.id}', native);
    }
    await helper.key('editor-close-tab-${tabs.active.id}', native);
    await helper.until(
        () => tabs.active.document.pieces.isEmpty, 'Last close blank');
    final blank = tabs.active;
    final state = await sync();
    final draftsBefore = (await repo.listDrafts()).length;
    await helper.key('editor-new-tab', native);
    await helper.until(() => tabs.sessions.length == 2, 'Second blank');
    final current = await sync();
    helper.check(
        state['documentToken'] != current['documentToken'] &&
            tabs.active.document.fingerprint == blank.document.fingerprint,
        'Identical blanks reused token');
    final stale = {
      ...state,
      'documentJson': jsonEncode(Formation(pieces: [
        Piece(id: 'stale', type: 'pea', row: 0, col: 0, layer: 10)
      ]).toJson())
    };
    final id = ++sequence;
    await helper
        .write('$base/$run/toolbox-command.json', {'id': id, 'state': stale});
    final end = DateTime.now().add(const Duration(seconds: 12));
    Map<String, dynamic>? ack;
    while (DateTime.now().isBefore(end)) {
      ack = await helper.read('$base/$run/toolbox-ack.json');
      if (ack?['id'] == id) break;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    helper.check(
        ack?['id'] == id &&
            ack?['accepted'] == false &&
            tabs.active.document.pieces.isEmpty,
        'Actual secondary stale-token edit crossed tabs');
    await tabs.flushAll();
    helper.check((await repo.listDrafts()).length == draftsBefore,
        'Untouched blank tabs persisted');
    row['toolbox'] = await sync();
  });
  await helper.write('$base/$run/done.json', {
    'pass': rows.where((r) => r['status'] == 'pass').length,
    'fail': rows.where((r) => r['status'] == 'fail').length,
    'pid': pid
  });
}
