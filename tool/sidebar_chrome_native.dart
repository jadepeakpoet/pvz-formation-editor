// Focused native chrome/style acceptance; previous mode-control suite is separate.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_browser.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'library_windows.dart' as h;

const base = '/tmp/pvz-sidebar-chrome';
const windows = MethodChannel('pvz_formation_editor/windows');
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

@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  await app.toolboxMain();
  await h.until(
      () => WindowBridge.supported && find((w) => w is app.EditorPage) != null,
      'toolbox ready');
  final report = <String, dynamic>{'status': 'pass'};
  try {
    h.check(find((w) => w is Text && w.data == '布阵器工具箱') == null,
        'Repeated Flutter toolbox title remains');
    final tab =
        find((w) => w is Text && w.data == '卡槽选卡')!.renderObject as RenderBox;
    final y = tab.localToGlobal(Offset.zero).dy;
    h.check(y < 20, 'Toolbox tabs still reserve duplicate title space: $y');
    report['firstTabY'] = y;
  } catch (e, stack) {
    report.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
  }
  await h.write('$base/toolbox.json', report);
}

@pragma('vm:entry-point')
Future<void> libraryMain() async {
  await app.libraryMain();
  await h.until(
      () => find((w) => w is LibraryBrowser) != null, 'library browser ready');
  final report = <String, dynamic>{'status': 'pass'};
  try {
    final browser = find((w) => w is LibraryBrowser)!.widget as LibraryBrowser;
    h.check(
        browser.showTitle == false &&
            find((w) => w is Text && w.data == '存档库') == null,
        'Repeated Flutter library title remains');
    for (final key in [
      'library-new',
      'library-import',
      'library-refresh',
      'library-search',
      'library-filter-toggle'
    ]) {
      h.check(find((w) => w.key == ValueKey(key)) != null,
          'Library action lost: $key');
    }
    await h.key(
        'library-refresh', const MethodChannel('pvz_formation_editor/library'));
    await h.until(
        () => find((w) => w.key == const ValueKey('library-search')) != null,
        'Library refresh actions ready');
    report['refreshPointer'] = true;
  } catch (e, stack) {
    report.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
  }
  await h.write('$base/library.json', report);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const MethodChannel('pvz_formation_editor/lifecycle')
      .setMethodCallHandler((call) async => call.method == 'prepareExit');
  await Directory(base).create(recursive: true);
  for (final name in ['toolbox', 'library', 'ready', 'continue', 'report']) {
    final file = File('$base/$name.json');
    if (await file.exists()) await file.delete();
  }
  await OriginalAssets.ensureLoaded();
  final path = '$base/$pid.sqlite';
  final repo = await FormationRepository.open(path);
  final tabs = EditorTabsController(repo, initial: EditorSession(repo));
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: app.EditorWorkspace(
          controller: tabs, libraryPath: path, continueArchive: (_) async {})));
  final report = <String, dynamic>{
    'status': 'pass',
    'pid': pid,
    'scope':
        'actual macOS chrome; real primary/library pointers; temp database; no platform mocks'
  };
  try {
    await h.until(() => WindowBridge.supported, 'main native ready');
    await h.until(
        () => File('$base/toolbox.json').existsSync(), 'toolbox checks');
    report['toolbox'] = await h.read('$base/toolbox.json');
    h.check((report['toolbox'] as Map)['status'] == 'pass',
        'Toolbox chrome: ${report['toolbox']}');
    Future<Map> diag() async => (await windows.invokeMapMethod('diagnostics'))!;
    Future<void> checkStyle(String selected) async {
      for (final mode in ['toolbox', 'library']) {
        final element = find((w) => w.key == ValueKey('main-sidebar-$mode'))!;
        final button = element.widget as OutlinedButton;
        final active = mode == selected;
        h.check(
            button.style!.backgroundColor!.resolve({}) ==
                Color(active ? 0xffdceade : 0xffedf1f3),
            'Button $mode fill differs');
        final box = element.renderObject as RenderBox;
        h.check(
            box.size.height == 26, 'Button $mode height ${box.size.height}');
        final semantics =
            find((w) => w.key == ValueKey('main-sidebar-selection-$mode'))!
                .widget as Semantics;
        h.check(semantics.properties.selected == active,
            'Button selection mismatch');
      }
    }

    await checkStyle('toolbox');
    report['toolboxDiagnostics'] = await diag();
    await h.write('$base/ready.json',
        {'pid': pid, ...report['toolboxDiagnostics'] as Map});
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (!File('$base/continue.json').existsSync() &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    h.check(File('$base/continue.json').existsSync(),
        'External screenshot checkpoint timeout');
    await h.key('main-sidebar-library', windows);
    await h.until(
        () => File('$base/library.json').existsSync(), 'library checks');
    report['library'] = await h.read('$base/library.json');
    h.check((report['library'] as Map)['status'] == 'pass',
        'Library chrome: ${report['library']}');
    await checkStyle('library');
    report['libraryDiagnostics'] = await diag();
    h.check(errors.isEmpty, 'Flutter errors $errors');
  } catch (e, stack) {
    report.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
  }
  report['errors'] = errors;
  await h.write('$base/report.json', report);
}
