// Real three-engine shared-side-window document persistence acceptance.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'library_windows.dart' as h;

const base = '/tmp/pvz-document-native';
const native = MethodChannel('pvz_formation_editor/windows');
const library = MethodChannel('pvz_formation_editor/library');
Element? find(bool Function(Widget) predicate) {
  Element? result;
  void visit(Element e) {
    if (predicate(e.widget)) result = e;
    e.debugVisitOnstageChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  return result;
}

Future<void> libraryTap(bool Function(Widget) predicate) async {
  await library.invokeMethod('activateWindow');
  await Future<void>.delayed(const Duration(milliseconds: 140));
  await h.until(() => find(predicate)?.renderObject is RenderBox,
      'Visible library pointer target');
  await Scrollable.ensureVisible(find(predicate)!,
      duration: Duration.zero, alignment: .5);
  await Future<void>.delayed(const Duration(milliseconds: 140));
  final box = find(predicate)!.renderObject as RenderBox;
  final point = box.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 9, position: point, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 9, position: point));
  await Future<void>.delayed(const Duration(milliseconds: 350));
}

Future<void> libraryKey(String key) =>
    libraryTap((w) => w.key == ValueKey(key));

@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  await app.toolboxMain();
  while (true) {
    if (WindowBridge.latestState != null) {
      await h.write('$base/toolbox.json', WindowBridge.latestState!);
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
}

@pragma('vm:entry-point')
Future<void> libraryMain() async {
  await app.libraryMain();
  int previous = -1;
  while (true) {
    final command = await h.read('$base/library-command.json');
    if (command == null || command['id'] == previous) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      continue;
    }
    previous = command['id'] as int;
    final ack = <String, dynamic>{'id': previous, 'status': 'pass'};
    try {
      await library.invokeMethod('activateWindow');
      await h.until(
          () => find((w) => w is app.LibraryPage) != null, 'library loaded');
      if (find((w) => w.key == const ValueKey('library-detail-back')) != null) {
        await libraryKey('library-detail-back');
      }
      await h.until(
          () => find((w) => w.key == const ValueKey('library-search')) != null,
          'library list');
      if (command['name'] == 'preset-current') {
        await libraryKey('library-section-预制名阵');
        await libraryKey('library-item-preset:original-0');
        await libraryKey('library-open-current');
      }
      if (command['name'] == 'snapshot') {
        await libraryKey('library-refresh');
        final dynamic state =
            (find((w) => w is app.LibraryPage) as StatefulElement).state;
        ack['archives'] = (state.archives as List<ArchiveRecord>)
            .map((a) => {
                  'id': a.id,
                  'name': a.name,
                  'fingerprint': Formation.fromJson(a.document).fingerprint
                })
            .toList();
      }
      if (command['name'] == 'rollback') {
        await libraryKey('library-section-我的存档');
        await libraryKey('library-menu-archive:${command['archiveId']}');
        await libraryTap(
            (w) => w is PopupMenuItem<String> && w.value == 'versions');
        await h.until(() => find((w) => w is SimpleDialogOption) != null,
            'history dialog');
        await libraryTap((w) => w is SimpleDialogOption);
      }
    } catch (e, stack) {
      ack.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
    }
    await h.write('$base/library-ack.json', ack);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const MethodChannel('pvz_formation_editor/lifecycle')
      .setMethodCallHandler((call) async => call.method == 'prepareExit');
  await Directory(base).create(recursive: true);
  for (final name in [
    'toolbox',
    'library-command',
    'library-ack',
    'report',
    'done'
  ]) {
    final f = File('$base/$name.json');
    if (await f.exists()) await f.delete();
  }
  await OriginalAssets.ensureLoaded();
  final path = '$base/$pid.sqlite';
  final repo = await FormationRepository.open(path);
  final tabs = EditorTabsController(repo);
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: app.EditorWorkspace(
          controller: tabs, libraryPath: path, continueArchive: (_) async {})));
  final cases = <Map<String, dynamic>>[];
  int sequence = 0;
  Future<Map<String, dynamic>> command(String name, {String? archiveId}) async {
    final id = ++sequence;
    await h.write('$base/library-command.json',
        {'id': id, 'name': name, 'archiveId': archiveId});
    final end = DateTime.now().add(const Duration(seconds: 25));
    while (DateTime.now().isBefore(end)) {
      final ack = await h.read('$base/library-ack.json');
      if (ack?['id'] == id) {
        h.check(ack!['status'] == 'pass', 'Library command $name: $ack');
        return ack;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    throw TimeoutException('Library command $name');
  }

  Future<void> mode(String mode) async {
    final state = await native.invokeMapMethod('diagnostics');
    if (state?['sidebarVisible'] != true || state?['sidebarMode'] != mode) {
      await h.key('main-sidebar-$mode', native);
    }
  }

  Future<void> canonicalName() async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(end)) {
      final state = await h.read('$base/toolbox.json');
      if (state?['name'] == tabs.active.name &&
          state?['documentJson'] == jsonEncode(tabs.active.document.toJson())) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    throw StateError(
        'Toolbox name/document did not adopt primary canonical state');
  }

  Future<void> plant(int row, int col) async {
    await native.invokeMethod('activateWindow');
    await Future<void>.delayed(const Duration(milliseconds: 140));
    final box = find((w) => w is CustomPaint && w.painter is BoardPainter)!
        .renderObject as RenderBox;
    final point = box.localToGlobal(
        BoardGeometry(tabs.active.document).cellCenter(row, col));
    GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: 7, position: point, buttons: 1));
    GestureBinding.instance
        .handlePointerEvent(PointerUpEvent(pointer: 7, position: point));
    await tabs.active.flush();
  }

  Future<void> test(
      String id, Future<void> Function(Map<String, dynamic>) body) async {
    final row = <String, dynamic>{'id': id, 'status': 'pass'};
    try {
      await body(row);
      h.check(errors.isEmpty, 'Flutter errors $errors');
    } catch (e, stack) {
      row.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
    }
    cases.add(row);
    await h.write('$base/report.json', {
      'scope':
          'actual macOS shared NSWindow and three retained engines; real Flutter pointers; temporary database; no channel mocks',
      'pid': pid,
      'cases': cases,
      'errors': errors
    });
  }

  await h.until(() => WindowBridge.supported, 'primary native ready');
  String? archiveId;
  await test('document.template-save-name-across-engines', (row) async {
    await mode('library');
    await command('preset-current');
    await h.until(
        () => tabs.active.document.pieces.isNotEmpty && !tabs.active.readOnly,
        'editable template workcopy');
    await tabs.active.flush();
    archiveId = tabs.active.sourceArchiveId!;
    await h.key('document-rename', native);
    final field = find((w) => w.key == const ValueKey('document-name-input'))!
        .widget as TextField;
    field.controller!.text = '原生工作流存档';
    await h.key('document-rename', native);
    await h.key('archive-save', native);
    h.check(
        find((w) => w is AlertDialog) == null, 'Save showed Save As dialog');
    await canonicalName();
    final saved =
        (await repo.listArchives()).singleWhere((a) => a.id == archiveId);
    h.check(saved.name == tabs.active.name && saved.name == '原生工作流存档',
        'Primary/archive/tab name mismatch');
    await mode('library');
    final snapshot = await command('snapshot');
    h.check(
        (snapshot['archives'] as List)
            .any((a) => a['id'] == archiveId && a['name'] == saved.name),
        'Library retained old canonical name');
    row.addAll({
      'archiveId': archiveId,
      'name': saved.name,
      'diagnostics': await native.invokeMethod('diagnostics')
    });
  });
  await test('document.autosave-history-rollback-same-identity', (row) async {
    await mode('toolbox');
    final oldId = archiveId!;
    await plant(0, 2);
    await h.key('archive-save', native);
    final edited = tabs.active.document.fingerprint;
    final versions = await repo.listVersions(oldId);
    h.check(versions.isNotEmpty, 'Actual pointer edit has no history');
    await mode('library');
    await command('rollback', archiveId: oldId);
    await h.until(() => tabs.active.document.fingerprint != edited,
        'actual library history rollback');
    h.check(
        tabs.active.sourceArchiveId == oldId &&
            versions.any((v) =>
                Formation.fromJson(v.document).fingerprint ==
                tabs.active.document.fingerprint),
        'Rollback created new identity or wrong document');
    await canonicalName();
    await plant(0, 3);
    await tabs.active.flush();
    h.check(tabs.active.error == null && tabs.active.sourceArchiveId == oldId,
        'Restored session cannot continue saving');
    h.check((await repo.listVersions(oldId)).length >= versions.length + 2,
        'Rollback/next edit history missing');
    row.addAll({
      'archiveId': oldId,
      'name': tabs.active.name,
      'versions': (await repo.listVersions(oldId)).length,
      'diagnostics': await native.invokeMethod('diagnostics')
    });
  });
  await h.write('$base/done.json', {
    'pid': pid,
    'pass': cases.where((c) => c['status'] == 'pass').length,
    'fail': cases.where((c) => c['status'] != 'pass').length
  });
}
