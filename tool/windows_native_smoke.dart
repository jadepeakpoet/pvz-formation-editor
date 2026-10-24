// Runs against the actual Windows runner; no simulated window or game channel.
import 'dart:convert';
import 'dart:io';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';
import 'package:pvz_formation_editor/platform/game_writes.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/toolkit_codec.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';

@pragma('vm:entry-point')
Future<void> toolboxMain() => app.toolboxMain();
@pragma('vm:entry-point')
Future<void> libraryMain() => app.libraryMain();

bool sizeMatches(dynamic raw, double width, double height) {
  final size = raw as List;
  return ((size[0] as num) - width).abs() <= 0.5 &&
      ((size[1] as num) - height).abs() <= 0.5;
}

dynamic editorState() {
  dynamic found;
  void visit(Element element) {
    if (element is StatefulElement &&
        element.widget is app.EditorPage &&
        !(element.widget as app.EditorPage).toolboxOnly) found = element.state;
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement!.visitChildren(visit);
  return found;
}

String composition(Formation f) {
  final items = f.pieces
      .map((p) =>
          '${p.type}:${p.row}:${p.col}:${p.asleep}:${p.effects.join(',')}')
      .toList()
    ..sort();
  return jsonEncode([f.mapId, items]);
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<Map<dynamic, dynamic>> diagnostics() async => (await WindowBridge.channel
    .invokeMapMethod<dynamic, dynamic>('diagnostics'))!;
Future<void> main() async {
  final reportPath = Platform.environment['PVZ_NATIVE_SMOKE_REPORT'];
  if (reportPath == null) {
    throw StateError('Explicit native smoke report path required');
  }
  final report = <String, dynamic>{};
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await OriginalAssets.ensureLoaded();
    final databasePath =
        '${File(reportPath).parent.path}/native-windows-test.sqlite';
    final repository = await FormationRepository.open(databasePath);
    runApp(MaterialApp(
        home: app.EditorPage(
            session: EditorSession(repository),
            libraryPath: databasePath,
            continueArchive: (_) async {})));
    for (var i = 0; i < 150 && !WindowBridge.supported; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    check(WindowBridge.supported, 'Native window bridge initialized');
    await Future<void>.delayed(const Duration(seconds: 2));
    final toolbox = await diagnostics();
    report['toolbox'] = toolbox;
    check(sizeMatches(toolbox['mainContentSize'], 810, 695), 'Main geometry');
    check(sizeMatches(toolbox['sidebarContentSize'], 410, 695),
        'Sidebar geometry');
    check(
        (toolbox['mainFrame'] as List)[1] ==
            (toolbox['sidebarFrame'] as List)[1],
        'Window tops aligned');
    check(
        (toolbox['mainFrame'] as List)[3] ==
            (toolbox['sidebarFrame'] as List)[3],
        'Window heights aligned');
    check(toolbox['toolboxReady'] == true, 'Toolbox engine handshake');
    report['toolbox'] = toolbox;
    await WindowBridge.selectMode('library');
    await Future<void>.delayed(const Duration(seconds: 2));
    final library = await diagnostics();
    check(
        library['libraryReady'] == true && library['sidebarMode'] == 'library',
        'Library engine handshake and mode');
    check(library['sidebarWindowNumber'] == toolbox['sidebarWindowNumber'],
        'Both modes reuse one native side window');
    check(sizeMatches(library['sidebarContentSize'], 410, 695),
        'Library geometry');
    report['library'] = library;
    await WindowBridge.selectMode('toolbox');
    final games = await GameBridge.listGames();
    final game = games.firstWhere((g) => g.canWrite);
    var current = await GameBridge.readFormation(game.pid);
    report['gameBefore'] = {
      'pid': game.pid,
      'map': current.formation.mapId,
      'objects': current.formation.pieces.length,
      'sun': current.formation.sunValue
    };
    if (Platform.environment['PVZ_NATIVE_APPLY_SAMPLE'] == '1') {
      final sample = ToolkitCodec.decode(
          'LI43jH/kRlzjZrhRF3RUpjJeOFHFZEXTHtMe0tlawVVE7GI0efJc8npSWMdVLhV261Y=');
      final after =
          await GameWrites(Directory.systemTemp).apply(game.pid, sample);
      check(composition(after.formation) == composition(sample),
          'Actual Dart/native sample composition');
      check(after.formation.sunValue == current.formation.sunValue,
          'Sun preserved by lineup injection');
      current = await GameBridge.readFormation(game.pid);
      check(composition(current.formation) == composition(sample),
          'Read back after native loop resumed');
      report['gameAfter'] = {
        'map': current.formation.mapId,
        'objects': current.formation.pieces.length,
        'sun': current.formation.sunValue
      };
    }
    final editor = editorState();
    check(editor != null, 'Actual editor state');
    final originalFingerprint = editor.s.document.fingerprint;
    await editor.gameFormationAction(read: true);
    final fetched =
        FormationExchange.decode(editor.inputFormation.text as String);
    check(composition(fetched) == composition(current.formation),
        'Fetch fills lineup input');
    check(editor.s.document.fingerprint == originalFingerprint,
        'Fetch does not change the editor');
    if (Platform.environment['PVZ_NATIVE_APPLY_SAMPLE'] == '1') {
      await editor.navigateFormation(fetched, name: 'Native verification');
      editor.refreshFormationOutput();
      await editor.gameFormationAction(read: false);
      final verified = await GameBridge.readFormation(game.pid);
      check(composition(verified.formation) == composition(fetched),
          'Direct Apply to game action');
    }
    report['directGameActions'] = true;
    report['pass'] = true;
    await File(reportPath).writeAsString(jsonEncode(report));
    exit(0);
  } catch (e, st) {
    report['pass'] = false;
    report['error'] = '$e\n$st';
    await File(reportPath).writeAsString(jsonEncode(report));
    exit(1);
  }
}
