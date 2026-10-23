// Native dual-engine performance target. No channel mocks or user preference IO.
// Compile only during preparation; root owns native build and measured runs.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'library_windows.dart' as helpers;
import 'performance_smoke.dart' as stats;

const directory = '/tmp/pvz-performance-windows';
const windows = MethodChannel('pvz_formation_editor/windows');
Future<void> frame() async {
  SchedulerBinding.instance.scheduleFrame();
  await SchedulerBinding.instance.endOfFrame
      .timeout(const Duration(seconds: 15));
}

Future<void> waitFor(Future<bool> Function() condition, String label) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException(label);
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

@pragma('vm:entry-point')
Future<void> libraryMain() => app.libraryMain();
@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  await app.toolboxMain();
  var observedVersion = 0;
  String? previous;
  while (true) {
    final received = WindowBridge.latestState;
    final element =
        helpers.find((w) => w is app.EditorPage) as StatefulElement?;
    if (received != null && element != null) {
      final dynamic page = element.state;
      final appliedJson = jsonEncode(page.s.document.toJson());
      final documentJson = received['documentJson'] as String?;
      if (previous != documentJson) {
        observedVersion++;
        previous = documentJson;
      }
      await helpers.write('$directory/toolbox.json', {
        'pid': pid,
        'documentJson': documentJson,
        'appliedDocumentJson': appliedJson,
        'observedDocumentVersion': observedVersion,
        'documentToken': received['documentToken'],
      });
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const MethodChannel('pvz_formation_editor/lifecycle')
      .setMethodCallHandler((call) async => call.method == 'prepareExit');
  await Directory(directory).create(recursive: true);
  for (final filename in ['toolbox.json', 'report.json']) {
    final file = File('$directory/$filename');
    if (await file.exists()) await file.delete();
  }
  final rows = <String, Object?>{};
  final errors = <String>[];
  final report = <String, Object?>{
    'pid': pid,
    'environment': {
      'mode':
          'native macOS debug; real main + toolbox Flutter engines and channel',
      'os': Platform.operatingSystemVersion,
      'dart': Platform.version,
      'pointer': 'main board GestureBinding mouse events, not OS CGEvents',
      'persistence':
          'in-memory SQLite, nonpersisting EditorSession; no preferences loaded',
      'sync':
          'dispatch to secondary received documentJson AND applied documentJson match',
      'pollIntervalMs': 10,
      'pollLimitation':
          'Both engines poll/write/read files every 10ms. Sync latency includes polling, JSON and filesystem IPC overhead; it is not raw channel latency.',
      'observedVersion':
          'local secondary document-change count, not a transport sequence guarantee',
    },
    'scenarios': rows,
  };
  FormationRepository? repo;
  EditorSession? session;
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  try {
    await OriginalAssets.ensureLoaded();
    repo = await FormationRepository.open(':memory:');
    session =
        EditorSession(repo, persistDraft: false, document: stats.fixture(80));
    final editorSession = session;
    runApp(MaterialApp(
        home: app.EditorPage(
            session: editorSession,
            libraryPath: ':memory:',
            continueArchive: (_) async {})));
    await waitFor(() async => WindowBridge.supported, 'Native bridge ready');
    await windows.invokeMethod('selectSidebarMode', {'mode': 'toolbox'});
    await windows.invokeMethod('activateWindow');
    await frame();
    Future<void> synced(String expected) async {
      await waitFor(() async {
        final state = await helpers.read('$directory/toolbox.json');
        return state?['pid'] == pid &&
            state?['documentJson'] == expected &&
            state?['appliedDocumentJson'] == expected;
      }, 'Secondary canonical document convergence');
    }

    await synced(jsonEncode(editorSession.document.toJson()));
    final dynamic page =
        (helpers.find((w) => w is app.EditorPage) as StatefulElement).state;
    var pointer = 500;
    for (final count in [80, 500]) {
      editorSession.execute(
          'Isolated performance fixture', stats.fixture(count));
      await frame();
      await synced(jsonEncode(editorSession.document.toJson()));
      final board =
          page.plantingBoardKey.currentContext.findRenderObject() as RenderBox;
      for (final tool in ['放置', '铲除']) {
        page.setState(() {
          page.tool = tool;
          page.selectedType = 'pea';
          page.shovelFilter = '智能';
        });
        await frame();
        final response = <double>[];
        final sync = <double>[];
        var changed = 0;
        final mutations = <bool>[];
        final scenarioWatch = Stopwatch()..start();
        for (var i = 0; i < 20; i++) {
          final before = jsonEncode(editorSession.document.toJson());
          final local =
              BoardGeometry(editorSession.document).cellCenter(i ~/ 9, i % 9);
          final position = board.localToGlobal(local);
          final viewport =
              WidgetsBinding.instance.renderViews.first.configuration.size;
          if (!(Offset.zero & viewport).contains(position)) {
            throw StateError(
                'Board pointer $position outside native viewport $viewport');
          }
          final watch = Stopwatch()..start();
          GestureBinding.instance.handlePointerEvent(PointerHoverEvent(
              position: position, kind: PointerDeviceKind.mouse));
          GestureBinding.instance.handlePointerEvent(PointerDownEvent(
              pointer: pointer,
              position: position,
              kind: PointerDeviceKind.mouse,
              buttons: 1));
          GestureBinding.instance.handlePointerEvent(PointerUpEvent(
              pointer: pointer++,
              position: position,
              kind: PointerDeviceKind.mouse));
          await frame();
          response.add(watch.elapsedMicroseconds / 1000);
          final expected = jsonEncode(editorSession.document.toJson());
          final mutated = before != expected;
          mutations.add(mutated);
          if (mutated) changed++;
          await synced(expected);
          sync.add(watch.elapsedMicroseconds / 1000);
        }
        rows['board.$count.${tool == '放置' ? 'plant' : 'smartShovel'}.20'] = {
          'elapsedMs': scenarioWatch.elapsedMicroseconds / 1000,
          'documentChangingEvents': changed,
          'documentChangedPerEvent': mutations,
          'noOpEventCount': mutations.where((changed) => !changed).length,
          'allEventsToEndOfFrame': stats.summary(response),
          'allEventsToSecondaryAppliedSync': stats.summary(sync),
          if (changed > 0)
            'mutatingEventsToEndOfFrame': stats.summary([
              for (var i = 0; i < mutations.length; i++)
                if (mutations[i]) response[i],
            ]),
          if (changed > 0)
            'mutatingEventsToSecondaryAppliedSync': stats.summary([
              for (var i = 0; i < mutations.length; i++)
                if (mutations[i]) sync[i],
            ]),
        };
        await helpers
            .write('$directory/report.json', {...report, 'status': 'running'});
      }
    }
    report['status'] = errors.isEmpty ? 'complete' : 'flutterErrors';
  } catch (e, stack) {
    report.addAll({'status': 'failed', 'error': '$e', 'stack': '$stack'});
  } finally {
    report['flutterErrors'] = errors;
    final view = WidgetsBinding.instance.renderViews.first.configuration;
    report['view'] = {
      'width': view.size.width,
      'height': view.size.height,
      'devicePixelRatio': view.devicePixelRatio
    };
    await helpers.write('$directory/report.json', report);
    // Leave this isolated instance visible for root's native QA lifecycle.
    // Root may close it after collecting the final report.
  }
}
