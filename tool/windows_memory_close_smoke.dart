import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';

@pragma('vm:entry-point')
Future<void> toolboxMain() => app.toolboxMain();
@pragma('vm:entry-point')
Future<void> libraryMain() => app.libraryMain();
void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> pause() => Future<void>.delayed(const Duration(seconds: 1));
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  app.initializeExitHandling();
  final reportFile = File(Platform.environment['PVZ_MEMORY_REPORT']!);
  final report = <String, dynamic>{};
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  try {
    final path = '${reportFile.parent.path}/memory-close.sqlite';
    final repo = await FormationRepository.open(path);
    final session = EditorSession(repo,
        document: LibraryPresets.all.first.document,
        name: 'Exit autosave verification');
    final tabs = EditorTabsController(repo, initial: session);
    runApp(MaterialApp(
        home: app.EditorWorkspace(
            controller: tabs,
            libraryPath: path,
            continueArchive: (_) async {})));
    for (var i = 0; i < 100 && !WindowBridge.supported; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    check(WindowBridge.supported, 'Native bridge initializes');
    await pause();
    const channel = WindowBridge.channel;
    report['initial'] = await channel.invokeMethod('diagnostics');
    final samples = <int>[ProcessInfo.currentRss];
    for (var i = 0; i < 6; i++) {
      await WindowBridge.selectMode('library');
      await pause();
      final diagnostics = (await channel.invokeMapMethod('diagnostics'))!;
      check(
          diagnostics['libraryReady'] == true, 'Library shares sidebar engine');
      check(
          diagnostics['sidebarEngineCount'] == 1 &&
              diagnostics['hasLibraryEngine'] == false,
          'Repeated mode changes never create an extra engine');
      samples.add(ProcessInfo.currentRss);
      await WindowBridge.selectMode('toolbox');
      await pause();
      samples.add(ProcessInfo.currentRss);
    }
    report['afterSwitching'] = await channel.invokeMethod('diagnostics');
    report['rssSamplesBytes'] = samples;
    if (Platform.environment['PVZ_MEMORY_PROFILE'] == '1') {
      session.rename('Saved immediately before normal close');
      report['expectedId'] = session.id;
      report['database'] = path;
      report['errors'] = errors;
      report['status'] = 'ready-for-normal-close';
      await reportFile.writeAsString(jsonEncode(report));
      return;
    }
    Future<bool> veto() async => false;
    app.exitGuards.add(veto);
    await channel.invokeMethod('requestCloseForTest');
    await pause();
    report['vetoPreservedWindow'] =
        await channel.invokeMethod('diagnostics') != null;
    app.exitGuards.remove(veto);
    session.rename('Saved immediately before normal close');
    report['expectedId'] = session.id;
    report['database'] = path;
    report['errors'] = errors;
    check(errors.isEmpty, 'No Flutter errors during page switching');
    report['status'] = 'requesting-normal-close';
    await reportFile.writeAsString(jsonEncode(report));
    await channel.invokeMethod('requestCloseForTest');
    // Parent checks process exit and the committed SQLite name after WM_CLOSE.
  } catch (error, stack) {
    report['error'] = '$error\n$stack';
    await reportFile.writeAsString(jsonEncode(report));
    exit(1);
  }
}
