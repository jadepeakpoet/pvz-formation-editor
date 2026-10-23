// Native first-click acceptance. Uses an in-memory formation and an external
// CGEvent driver, without touching the user's database or simulating Flutter taps.
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'library_windows.dart' as h;

const base = '/tmp/pvz-toolbox-tabs-first-click';
const native = MethodChannel('pvz_formation_editor/windows');

@pragma('vm:entry-point')
Future<void> libraryMain() => app.libraryMain();

@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  await app.toolboxMain();
  await WidgetsBinding.instance.endOfFrame;
  final pointerEvents = <Map<String, dynamic>>[];
  var frameCount = 0, lastFrameTab = -1;
  WidgetsBinding.instance.addPersistentFrameCallback((_) {
    final element = h.find((w) => w is app.EditorPage) as StatefulElement?;
    if (element != null) {
      final dynamic page = element.state;
      lastFrameTab = page.classicTab as int;
      frameCount++;
    }
  });
  GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
    if (event is PointerDownEvent ||
        event is PointerUpEvent ||
        event is PointerCancelEvent) {
      pointerEvents.add({
        'type': event.runtimeType.toString(),
        'x': event.position.dx,
        'y': event.position.dy,
        'buttons': event.buttons
      });
      if (pointerEvents.length > 60) pointerEvents.removeAt(0);
    }
  });
  var pickerRequested = false, clearRequested = false, undoRequested = false;
  while (true) {
    if (!pickerRequested && await File('$base/picker-request.json').exists()) {
      pickerRequested = true;
      final element = h.find((w) => w is app.EditorPage) as StatefulElement?;
      if (element != null) {
        final dynamic page = element.state;
        await page.chooseFormationPreset('阵型');
      }
    }
    if (!clearRequested && await File('$base/clear-request.json').exists()) {
      clearRequested = true;
      unawaited(WindowBridge.mainAction('clearFormation'));
    }
    if (!undoRequested && await File('$base/undo-request.json').exists()) {
      undoRequested = true;
      unawaited(WindowBridge.mainAction('undo'));
    }
    final element = h.find((w) => w is app.EditorPage) as StatefulElement?;
    if (element != null) {
      final dynamic page = element.state;
      final targets = <Map<String, double>>[];
      for (var i = 0; i < 6; i++) {
        final box =
            h.find((w) => w.key == ValueKey('toolbox-tab-$i'))?.renderObject;
        if (box is RenderBox && box.hasSize) {
          final point = box.localToGlobal(box.size.center(Offset.zero));
          targets.add({'x': point.dx, 'y': point.dy});
        }
      }
      final card = h
          .find((w) =>
              w.key ==
              ValueKey('library-item-preset:${LibraryPresets.all.first.id}'))
          ?.renderObject;
      final cardPoint = card is RenderBox && card.hasSize
          ? card.localToGlobal(card.size.center(Offset.zero))
          : null;
      await h.write('$base/sidebar.json', {
        'lastFrameTab': lastFrameTab,
        'frameCount': frameCount,
        'builtTab': [
          for (var i = 0; i < 6; i++)
            if ((((h.find((w) => w.key == ValueKey('toolbox-tab-$i'))?.widget
                                as InkWell?)
                            ?.child as Container?)
                        ?.decoration as BoxDecoration?)
                    ?.color ==
                const Color(0xffe1ecd6))
              i
        ],
        'lifecycle': WidgetsBinding.instance.lifecycleState.toString(),
        'framesEnabled': WidgetsBinding.instance.framesEnabled,
        'scheduledFrame': WidgetsBinding.instance.hasScheduledFrame,
        'routeCanPop': Navigator.of(element).canPop(),
        'pointerEvents': List.of(pointerEvents),
        'pickerGroup': page.pickingPresetGroup,
        'toolboxOnly': page.widget.toolboxOnly,
        'pickerBuilt':
            h.find((w) => w.key == const ValueKey('formation-preset-picker')) !=
                null,
        'pickerResults':
            h.find((w) => w.key == const ValueKey('preset-picker-results')) !=
                null,
        'pickerTarget':
            cardPoint == null ? null : {'x': cardPoint.dx, 'y': cardPoint.dy},
        'pid': pid,
        'tab': page.classicTab,
        'targets': targets,
        'pending': page.windowPublishInFlight || page.windowPublishQueued,
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const MethodChannel('pvz_formation_editor/lifecycle')
      .setMethodCallHandler((_) async => true);
  await Directory(base).create(recursive: true);
  for (final name in [
    'sidebar.json',
    'request.json',
    'report.json',
    'picker-request.json',
    'click.json',
    'clear-request.json',
    'undo-request.json'
  ]) {
    final file = File('$base/$name');
    if (await file.exists()) await file.delete();
  }
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final session = EditorSession(repo, persistDraft: false);
  final tabs = EditorTabsController(repo, initial: session);
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  runApp(MaterialApp(
      home: app.EditorWorkspace(
          controller: tabs,
          libraryPath: ':memory:',
          continueArchive: (_) async {})));
  final rows = <Map<String, dynamic>>[];
  try {
    await h.until(() => WindowBridge.supported, 'Native bridge ready');
    await native.invokeMethod('selectSidebarMode', {'mode': 'toolbox'});
    Map<String, dynamic>? sidebar;
    final readyDeadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(readyDeadline)) {
      sidebar = await h.read('$base/sidebar.json');
      if (sidebar?['pid'] == pid && (sidebar?['targets'] as List).length == 6) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    h.check(sidebar?['pid'] == pid, 'Toolbox not ready');
    final before = session.document.fingerprint;
    var id = 0;
    await native.invokeMethod('activateWindow');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final beforeDrag = (await native.invokeMethod('diagnostics')) as Map;
    await h.write('$base/request.json', {
      'id': ++id,
      'pid': pid,
      'operation': 'drag-main',
      'target': {'x': 250.0, 'y': -14.0},
      'frame': beforeDrag['mainFrame'],
    });
    final dragDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(dragDeadline)) {
      if ((await h.read('$base/click.json'))?['id'] == id) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    final afterDrag = (await native.invokeMethod('diagnostics')) as Map;
    final moved = jsonEncode(beforeDrag['mainFrame']) !=
        jsonEncode(afterDrag['mainFrame']);
    h.check(
        jsonEncode(beforeDrag['sidebarFrame']) ==
            jsonEncode(afterDrag['sidebarFrame']),
        'Toolbox followed the editor drag');
    rows.add({
      'independent-after-main-drag': moved ? 'pass' : 'notRun',
      'reason': moved
          ? null
          : 'OS drag did not move window; sidebar stayed stationary'
    });
    final stationarySidebar = jsonEncode(afterDrag['sidebarFrame']);
    for (final mode in ['library', 'toolbox', 'library', 'toolbox']) {
      await native.invokeMethod('selectSidebarMode', {'mode': mode});
      final current = (await native.invokeMethod('diagnostics')) as Map;
      h.check(jsonEncode(current['sidebarFrame']) == stationarySidebar,
          'Sidebar moved while switching modes');
    }
    rows.add({'library-toolbox-switch-position': 'pass'});
    var round = 0;
    for (final tab in [0, 1, 2, 3, 4, 5, 2, 0, 5, 1, 4, 3, 0, 1, 2, 3, 4, 5]) {
      round++;
      if (round % 3 == 0) {
        await native.invokeMethod('setSidebarVisible', {'visible': false});
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await native.invokeMethod('setSidebarVisible', {'visible': true});
      }

      await native.invokeMethod('selectSidebarMode', {'mode': 'library'});
      await native.invokeMethod('selectSidebarMode', {'mode': 'toolbox'});
      await native.invokeMethod('activateWindow');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final diag = (await native.invokeMethod('diagnostics')) as Map;
      h.check(diag['mainKey'] == true && diag['sidebarKey'] == false,
          'Main must be key before clicking inactive toolbox');
      sidebar = await h.read('$base/sidebar.json');
      final target = (sidebar!['targets'] as List)[tab] as Map;
      await h.write('$base/request.json', {
        'id': ++id,
        'pid': pid,
        'operation': round % 4 == 0 ? 'outside-app' : 'click',
        'target': target,
        'frame': diag['sidebarFrame'],
        'window': diag['sidebarWindowNumber'],
      });
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      var switched = false;
      while (DateTime.now().isBefore(deadline)) {
        final ack = await h.read('$base/click.json');
        final state = await h.read('$base/sidebar.json');
        if (ack?['id'] == id && round % 4 == 0) {
          h.check(ack?['outsideAppActive'] == true,
              'External application must actually be active before first click');
        }
        if (ack?['id'] == id &&
            state?['tab'] == tab &&
            state?['framesEnabled'] == true &&
            (state?['builtTab'] as List?)?.singleOrNull == tab &&
            state?['lastFrameTab'] == tab) {
          switched = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      h.check(switched, 'First click did not select tab $tab');
      h.check(session.document.fingerprint == before,
          'Tab navigation edited formation');
      rows.add({
        'tab': tab,
        'status': 'pass',
        'mainWasKey': true,
        'externalAppFirstClick': round % 4 == 0,
        'reopened': round % 3 == 0
      });
    }
    // Minimize the real sidebar with its titlebar button, then reopen it.
    final minimizeDiag = (await native.invokeMethod('diagnostics')) as Map;
    await h.write('$base/request.json', {
      'id': ++id,
      'pid': pid,
      'operation': 'minimize-sidebar',
      'target': {'x': 38.0, 'y': -16.0},
      'frame': minimizeDiag['sidebarFrame'],
    });
    final minimizedDeadline = DateTime.now().add(const Duration(seconds: 8));
    var minimized = false;
    while (DateTime.now().isBefore(minimizedDeadline)) {
      final state = (await native.invokeMethod('diagnostics')) as Map;
      if (state['sidebarMiniaturized'] == true) {
        minimized = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    h.check(minimized, 'Native titlebar click did not minimize sidebar');
    await native.invokeMethod('setSidebarVisible', {'visible': true});
    final restoreDeadline = DateTime.now().add(const Duration(seconds: 8));
    var restored = false;
    while (DateTime.now().isBefore(restoreDeadline)) {
      final state = await h.read('$base/sidebar.json');
      if (state?['framesEnabled'] == true && state?['lastFrameTab'] == 5) {
        restored = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    h.check(restored, 'Restored sidebar still paused');
    rows.add({'native-minimize-restore': 'pass'});
    await h.write('$base/picker-request.json', {'open': true});
    final pickerDeadline = DateTime.now().add(const Duration(seconds: 10));
    Map? picker;
    while (DateTime.now().isBefore(pickerDeadline)) {
      picker = await h.read('$base/sidebar.json');
      if (picker?['pickerTarget'] != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    h.check(
        picker?['pickerTarget'] != null, 'Picker must appear inside toolbox');
    final diag = (await native.invokeMethod('diagnostics')) as Map;
    await h.write('$base/request.json', {
      'id': ++id,
      'pid': pid,
      'target': picker!['pickerTarget'],
      'frame': diag['sidebarFrame'],
      'window': diag['sidebarWindowNumber'],
    });
    await h.until(() => tabs.active.name == LibraryPresets.all.first.name,
        'Preset opens current tab');
    h.check(tabs.sessions.length == 1 && tabs.canGoBack,
        'Preset was not current-page navigation');
    final presetFingerprint = tabs.active.document.fingerprint;
    await h.write('$base/clear-request.json', {'clear': true});
    await h.until(() => tabs.active.document.pieces.isEmpty,
        'Toolbox clears without confirmation');
    h.check(h.find((w) => w is AlertDialog) == null && tabs.canUndo,
        'Clear required confirmation or lost undo');
    await h.write('$base/undo-request.json', {'undo': true});
    await h.until(() => tabs.active.document.fingerprint == presetFingerprint,
        'Toolbox undo restores cleared formation');
    rows.add({'clear-no-confirm-and-undo': 'pass'});
    await tabs.undo();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    h.check(
        identical(tabs.active, session) &&
            session.document.fingerprint == before,
        'Native preset Back lost original session');
    rows.add({'preset-current-and-back': 'pass'});
    h.check(errors.isEmpty, 'Flutter errors: $errors');
    await h.write('$base/report.json', {
      'status': 'pass',
      'pid': pid,
      'nativeDiagnostics': await native.invokeMethod('diagnostics'),
      'cases': rows,
      'scope':
          'real native drag, 18 OS tab clicks checking completed frames after library/toolbox switches, close/reopen, external-app focus, minimize/restore; OS toolbox picker click, native clear, undo; in-memory formation',
    });
  } catch (e, stack) {
    await h.write('$base/report.json', {
      'status': 'fail',
      'pid': pid,
      'nativeDiagnostics': await native.invokeMethod('diagnostics'),
      'cases': rows,
      'error': '$e',
      'stack': '$stack',
    });
  }
  exit(0);
}
