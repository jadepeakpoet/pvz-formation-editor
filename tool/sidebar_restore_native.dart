// Native Windows acceptance: real minimize/restore, isolated in-memory document.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'live_preset_apply_smoke.dart' as ui;

@pragma('vm:entry-point')
Future<void> toolboxMain() => app.toolboxMain();
@pragma('vm:entry-point')
Future<void> libraryMain() => app.libraryMain();

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
Future<Map<dynamic, dynamic>> diagnostics() async =>
    (await WindowBridge.channel.invokeMapMethod<dynamic, dynamic>('diagnostics'))!;
Future<void> waitFor(Future<bool> Function() ready, String message) async {
  for (var i = 0; i < 200; i++) {
    try {
      if (await ready()) return;
    } on MissingPluginException {
      // The first Dart frame can precede registration of the native channel.
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = Directory(Platform.environment['PVZ_SIDEBAR_RESTORE_ROOT']!);
  final errors = <String>[];
  FlutterError.onError = (error) => errors.add(error.exceptionAsString());
  final report = <String, dynamic>{};
  final repository = await FormationRepository.open(':memory:');
  final session = EditorSession(repository, persistDraft: false);
  try {
    await OriginalAssets.ensureLoaded();
    runApp(MaterialApp(home: app.EditorPage(session: session,
        libraryPath: ':memory:', continueArchive: (_) async {})));
    await waitFor(() async => (await diagnostics())['toolboxReady'] == true,
        'Native sidebar not ready');
    await waitFor(() async => (await diagnostics())['sidebarVisible'] == true,
        'Native sidebar not shown');
    Future<void> minimize(int stage) async {
      final state = await diagnostics();
      await File('${root.path}/minimize-$stage.ready.json').writeAsString(jsonEncode({
        'pid': pid, 'hwnd': state['sidebarWindowNumber']}));
      await waitFor(() => File('${root.path}/minimize-$stage.done').exists(),
          'Owned native test driver did not minimize the sidebar');
      check((await diagnostics())['sidebarMinimized'] == true, 'Sidebar is not minimized');
    }
    await minimize(1);
    await ui.tapKey('main-sidebar-toolbox');
    await waitFor(() async {
      final state = await diagnostics();
      return state['sidebarVisible'] == true && state['sidebarMinimized'] == false;
    }, 'Clicking the toolbox button hid the minimized sidebar');
    report['minimizedClickRestores'] = true;
    await ui.tapKey('main-sidebar-toolbox');
    await waitFor(() async => (await diagnostics())['sidebarVisible'] == false,
        'Normal visible sidebar should still toggle hidden');
    await ui.tapKey('main-sidebar-toolbox');
    await waitFor(() async => (await diagnostics())['sidebarVisible'] == true,
        'Hidden sidebar should toggle visible');
    report['normalVisibilityToggle'] = true;
    await minimize(2);
    await WindowBridge.setVisible(false);
    check((await diagnostics())['sidebarVisible'] == false,
        'Explicit hide must not become a restore');
    await WindowBridge.selectMode('toolbox');
    final restored = await diagnostics();
    check(restored['sidebarVisible'] == true && restored['sidebarMinimized'] == false,
        'Explicit show must restore a previously minimized sidebar');
    report['explicitHideAndShow'] = true;
    check(errors.isEmpty, 'Flutter errors: $errors');
    report['status'] = 'pass';
  } catch (error, stack) {
    report['status'] = 'fail'; report['error'] = '$error\n$stack';
  }
  report['flutterErrors'] = errors;
  await File('${root.path}/report.json').writeAsString(jsonEncode(report));
  session.dispose(); await repository.close();
  exit(report['status'] == 'pass' ? 0 : 1);
}
