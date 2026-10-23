// Native shared-sidebar acceptance. Two retained secondary engines, ONE side NSWindow.
// Target FLUTTER_TARGET=tool/sidebar_windows.dart; only temporary SQLite/files.
// Main bar buttons use actual Flutter pointers. No native header/driver remains.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'library_windows.dart' as helper;

const base = '/tmp/pvz-sidebar-native';
const native = MethodChannel('pvz_formation_editor/windows');
const library = MethodChannel('pvz_formation_editor/library');
Element? onstage(bool Function(Widget) predicate) {
  Element? result;
  void visit(Element e) {
    if (predicate(e.widget)) result = e;
    e.debugVisitOnstageChildren(visit);
  }

  visit(WidgetsBinding.instance.rootElement!);
  return result;
}

Future<void> libraryKey(String key) async {
  await library.invokeMethod('activateWindow');
  await helper.until(() => onstage((w) => w.key == ValueKey(key)) != null,
      'Visible library target $key');
  await Scrollable.ensureVisible(onstage((w) => w.key == ValueKey(key))!,
      duration: Duration.zero, alignment: .5);
  await Future<void>.delayed(const Duration(milliseconds: 140));
  final box = onstage((w) => w.key == ValueKey(key))!.renderObject as RenderBox;
  final p = box.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: p, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 1, position: p));
  await Future<void>.delayed(const Duration(milliseconds: 220));
}

Future<String> runId() async =>
    (await helper.read('$base/meta.json'))!['run'] as String;
@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  await app.toolboxMain();
  final run = await runId();
  int previous = -1;
  while (true) {
    final state = WindowBridge.latestState;
    final element = helper.find((w) => w is app.EditorPage) as StatefulElement?;
    final dynamic controller = element?.state;
    if (state != null && WindowBridge.supported && controller != null) {
      await helper.write('$base/$run/toolbox-state.json', {
        ...state,
        'liveOutput': controller.outputFormation.text,
        'tab': controller.classicTab,
        'input': controller.inputFormation.text
      });
    }
    final cmd = await helper.read('$base/$run/toolbox-command.json');
    if (cmd != null && cmd['id'] != previous) {
      previous = cmd['id'] as int;
      final ack = <String, dynamic>{'id': previous, 'status': 'pass'};
      try {
        await native.invokeMethod('activateWindow');
        await helper.until(
            () => helper.find((w) => w is app.EditorPage) != null,
            'Toolbox widget ready');
        if (cmd['name'] == 'prepare') {
          await helper.tap((w) => w is Text && w.data == '载入导出', native);
          controller.inputFormation.text = 'retained sidebar input';
        }
        ack.addAll({
          'tab': controller.classicTab,
          'input': controller.inputFormation.text,
          'liveOutput': controller.outputFormation.text
        });
      } catch (e, stack) {
        ack.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
      }
      await helper.write('$base/$run/toolbox-ack.json', ack);
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
}

@pragma('vm:entry-point')
Future<void> libraryMain() async {
  await app.libraryMain();
  final run = await runId();
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
      await helper.until(() => onstage((w) => w is app.LibraryPage) != null,
          'Library visible');
      if (onstage((w) => w.key == const ValueKey('library-detail-back')) !=
          null) await libraryKey('library-detail-back');
      await helper.until(
          () =>
              onstage((w) => w.key == const ValueKey('library-section-我的存档')) !=
              null,
          'Library focused and mounted');
      if (cmd['name'] == 'query') {
        final field = helper
            .find((w) => w.key == const ValueKey('library-search'))!
            .widget as TextField;
        field.controller!.text = 'Sidebar archive';
        field.onChanged!('Sidebar archive');
      }
      if (cmd['name'] == 'current' ||
          cmd['name'] == 'new-tab' ||
          cmd['name'] == 'copy' ||
          cmd['name'] == 'filters') {
        await libraryKey('library-section-我的存档');
        if (cmd['name'] != 'filters') {
          await libraryKey('library-item-archive:qa-sidebar');
        }
        if (cmd['name'] == 'filters') {
          await libraryKey('library-filter-toggle');
          await libraryKey('library-map-pool');
          await libraryKey('library-cannon-0');
          await libraryKey('library-filter-apply');
          ack['matched'] = helper.find((w) =>
                  w.key == const ValueKey('library-item-archive:qa-sidebar')) !=
              null;
        }
        if (cmd['name'] == 'current') {
          await libraryKey('library-open-current');
        }
        if (cmd['name'] == 'new-tab') {
          await libraryKey('library-open-tab');
        }
        if (cmd['name'] == 'copy') {
          await libraryKey('library-copy-code');
          ack['clipboard'] = (await Clipboard.getData('text/plain'))?.text;
        }
      }
      if (cmd['name'] == 'file-handoff') {
        final path = '$base/$run/imported.txt';
        await File(path).writeAsString('0,0 1 2 0 0 0');
        final text = await File(path).readAsString();
        final element =
            helper.find((w) => w is app.LibraryPage) as StatefulElement;
        final dynamic controller = element.state;
        final session = EditorSession(controller.repo as FormationRepository,
            name: 'Sidebar imported file',
            document: FormationExchange.decode(text))
          ..filePath = path
          ..fileFormat = FormationExchange.detectFormat(text).name;
        await controller.edit(session, newTab: true);
        ack['path'] = path;
      }
      final field = helper
          .find((w) => w.key == const ValueKey('library-search'))
          ?.widget as TextField?;
      ack['query'] = field?.controller?.text;
      if (cmd['name'] == 'close') {
        await library.invokeMethod('close');
        ack['closePath'] =
            'native library channel; not a physical window-X click';
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
  final initial = EditorSession(repo, name: 'Shared sidebar blank');
  final tabs = EditorTabsController(repo, initial: initial);
  final source = Formation(
      pieces: [Piece(id: 'source', type: 'pea', row: 0, col: 0, layer: 10)]);
  await repo.saveArchive(
      id: 'qa-sidebar', name: 'Sidebar archive', document: source.toJson());
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: app.EditorWorkspace(
          controller: tabs, libraryPath: path, continueArchive: (_) async {})));
  final rows = <Map<String, dynamic>>[];
  final buttonClicks = <Map<String, dynamic>>[];
  int sequence = 0;
  dynamic page() =>
      (helper.find((w) => w is app.EditorPage) as StatefulElement).state;
  Future<Map<String, dynamic>> diag() async => Map<String, dynamic>.from(
      (await native.invokeMethod('diagnostics')) as Map);
  Future<Map<String, dynamic>> command(String engine, String name) async {
    final id = ++sequence;
    await helper
        .write('$base/$run/$engine-command.json', {'id': id, 'name': name});
    final end = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(end)) {
      final ack = await helper.read('$base/$run/$engine-ack.json');
      if (ack?['id'] == id) {
        helper.check(
            ack!['status'] == 'pass', '$engine $name: ${ack['error']}');
        return ack;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    throw TimeoutException('$engine command $name');
  }

  Future<void> clickMode(String value) async {
    await helper.key('main-sidebar-$value', native);
    buttonClicks.add({'key': 'main-sidebar-$value', 'pointer': true});
  }

  Future<void> checkSelection() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final state = await diag();
    for (final value in ['toolbox', 'library']) {
      final semantics = helper
          .find((w) => w.key == ValueKey('main-sidebar-selection-$value'))!
          .widget as Semantics;
      helper.check(
          semantics.properties.selected ==
              (state['sidebarVisible'] == true &&
                  state['sidebarMode'] == value),
          'Main bar $value selection differs from native visibility/mode');
    }
  }

  Future<Map<String, dynamic>> mode(String value) async {
    final before = await diag();
    if (before['sidebarMode'] != value || before['sidebarVisible'] != true) {
      await clickMode(value);
    }
    final end = DateTime.now().add(const Duration(seconds: 8));
    var state = await diag();
    while ((state['sidebarMode'] != value || state['sidebarVisible'] != true) &&
        DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      state = await diag();
    }
    helper.check(
        state['sidebarMode'] == value && state['sidebarVisible'] == true,
        'Sidebar mode did not become visible $value');
    await checkSelection();
    return state;
  }

  Future<Map<String, dynamic>> sync() async {
    final end = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(end)) {
      final state = await helper.read('$base/$run/toolbox-state.json');
      if (state?['documentToken'] == page().documentToken &&
          state?['documentJson'] == jsonEncode(tabs.active.document.toJson()) &&
          state?['liveOutput'] ==
              FormationExchange.encode(tabs.active.document)) return state!;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    throw TimeoutException('Canonical toolbox/output sync');
  }

  Future<void> test(
      String id, Future<void> Function(Map<String, dynamic>) body) async {
    final row = <String, dynamic>{'id': id, 'status': 'pass'};
    try {
      await body(row);
      helper.check(errors.isEmpty, 'Flutter errors $errors');
    } catch (e, stack) {
      row.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
    }
    rows.add(row);
    final report = {
      'scope':
          'actual macOS shared NSWindow with two retained secondary engines; real Flutter pointers on primary mode buttons; no sidebar header; temporary database; no channel mocks',
      'pid': pid,
      'run': run,
      'cases': rows,
      'errors': errors,
      'buttonClicks': buttonClicks
    };
    await helper.write('$base/$run/report.json', report);
    await helper.write('$base/report.json', report);
  }

  await helper.until(() => WindowBridge.supported, 'Main native bridge ready');
  int? windowNumber;
  Map<String, dynamic>? mainBefore;
  await test('sidebar.shared-mainbar-control', (row) async {
    mainBefore = await diag();
    final shownDeadline = DateTime.now().add(const Duration(seconds: 10));
    while ((mainBefore!['sidebarVisible'] != true ||
            (mainBefore!['sidebarWindowNumber'] as num? ?? 0) <= 0) &&
        DateTime.now().isBefore(shownDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      mainBefore = await diag();
    }
    windowNumber = (mainBefore!['sidebarWindowNumber'] as num).toInt();
    final libraryGeometry = await mode('library');
    helper.check(
        jsonEncode(libraryGeometry['sidebarContentSize']) == '[410.0,640.0]' &&
            libraryGeometry['sidebarHeaderHeight'] == 0 &&
            (libraryGeometry['sidebarHeaderSegments'] as Map).isEmpty,
        'Narrow library and toolbox must keep identical content bounds');
    await command('library', 'snapshot');
    final state = await mode('toolbox');
    helper.check(
        state['sharedSidebarWindow'] == true &&
            state['sidebarWindowNumber'] == windowNumber,
        'Modes must reuse one actual NSWindow');
    helper.check(
        state['toolboxVisible'] == true && state['libraryVisible'] == false,
        'Only selected mode may be visible');
    helper.check(
        jsonEncode(state['mainContentSize']) == '[810.0,695.0]' &&
            state['mainResizable'] == false,
        'Shared sidebar changed fixed main content size');
    final board = helper
        .find((w) => w is CustomPaint && w.painter is BoardPainter)!
        .renderObject as RenderBox;
    helper.check(board.size == const Size(800, 600),
        'Shared sidebar altered PVZ board bounds');
    row['mainBoardBounds'] = [board.size.width, board.size.height];
    row['diagnostics'] = state;
    row['libraryDiagnostics'] = libraryGeometry;
  });
  await test('sidebar.hide-show-retains-state', (row) async {
    await command('toolbox', 'prepare');
    await mode('library');
    await command('library', 'query');
    await mode('toolbox');
    final retained = await command('toolbox', 'snapshot');
    helper.check(
        retained['tab'] == 4 && retained['input'] == 'retained sidebar input',
        'Toolbox state lost during mode switch');
    await clickMode('toolbox');
    helper.check((await diag())['sidebarVisible'] == false,
        'Main toggle failed to hide sidebar');
    await checkSelection();
    await clickMode('toolbox');
    final shown = await diag();
    helper.check(
        shown['sidebarVisible'] == true &&
            shown['sidebarWindowNumber'] == windowNumber &&
            shown['sidebarMode'] == 'toolbox',
        'Show did not restore same mode/window');
    await mode('library');
    helper.check(
        (await command('library', 'snapshot'))['query'] == 'Sidebar archive',
        'Library search lost');
    row['diagnostics'] = shown;
    await command('library', 'close');
    helper.check((await diag())['sidebarVisible'] == false,
        'Native close channel did not hide shared sidebar');
    await checkSelection();
    row['closePath'] = 'native library channel; not physical X';
    await mode('toolbox');
    await mode('library');
    helper.check(
        (await command('library', 'snapshot'))['query'] == 'Sidebar archive',
        'Close and different-mode restore lost library query');
  });
  await test('sidebar.archive-open-auto-toolbox-tabs', (row) async {
    await command('library', 'current');
    await helper.until(() => tabs.active.sourceArchiveId == 'qa-sidebar',
        'Archive current open');
    helper.check(tabs.sessions.length == 1 && !tabs.active.readOnly,
        'Current open must be editable current tab');
    helper.check((await diag())['sidebarMode'] == 'toolbox',
        'Archive open must return to toolbox');
    final first = tabs.active;
    await sync();
    await mode('library');
    await command('library', 'new-tab');
    await helper.until(() => tabs.sessions.length == 2, 'Archive new tab');
    helper.check(tabs.sessions.first == first && tabs.active.id != first.id,
        'New tab lost old work copy');
    await helper.key('editor-tab-${first.id}', native);
    row['toolbox'] = await sync();
    helper.check((await diag())['sidebarMode'] == 'toolbox',
        'New-tab open must return to toolbox');
  });
  await test('sidebar.filters-clipboard-file-handoff', (row) async {
    await mode('library');
    helper.check((await command('library', 'filters'))['matched'] == true,
        'New combined filter did not match source');
    final copy = await command('library', 'copy');
    helper.check(copy['clipboard'] == FormationExchange.encode(source),
        'Actual native clipboard is not Toolkit code');
    row['clipboard'] = copy['clipboard'];
    final file = await command('library', 'file-handoff');
    await helper.until(
        () => tabs.active.name == 'Sidebar imported file', 'File handoff');
    helper.check(
        tabs.active.filePath == file['path'] &&
            tabs.active.fileFormat == 'website',
        'File association lost across engines');
    helper.check((await diag())['sidebarMode'] == 'toolbox',
        'File open did not return to toolbox');
    row['toolbox'] = await sync();
    row['diagnostics'] = await diag();
  });
  await helper.write('$base/$run/done.json', {
    'pass': rows.where((r) => r['status'] == 'pass').length,
    'fail': rows.where((r) => r['status'] == 'fail').length,
    'pid': pid
  });
}
