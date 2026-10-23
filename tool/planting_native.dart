// Actual AVAudioPlayer/native diagnostics; temporary editor only.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/original_audio.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'library_windows.dart' as h;

@pragma('vm:entry-point')
Future<void> toolboxMain() => app.toolboxMain();
@pragma('vm:entry-point')
Future<void> libraryMain() => app.libraryMain();
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const MethodChannel('pvz_formation_editor/lifecycle')
      .setMethodCallHandler((call) async => call.method == 'prepareExit');
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final session = EditorSession(repo, persistDraft: false);
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add('$e');
  runApp(MaterialApp(
      home: app.EditorPage(session: session, continueArchive: (_) async {})));
  const channel = MethodChannel('pvz_formation_editor/windows');
  final report = <String, dynamic>{
    'pid': pid,
    'scope':
        'actual macOS AVAudioPlayer and native diagnostics; real Flutter board water pointer; no channel mocks',
    'status': 'pass'
  };
  try {
    await h.until(() => WindowBridge.supported, 'native ready');
    await OriginalAudio.setSoundVolume(.5);
    Future<Map> diag() async =>
        (await OriginalAudio.channel.invokeMapMethod('diagnostics'))!;
    final loaded = await diag();
    h.check(
        (loaded['soundSources'] as List)
            .toSet()
            .containsAll(['plant1', 'plant2', 'plant_water']),
        'Three native sources not loaded');
    report['loaded'] = loaded;
    final plays = <Map>[];
    for (final source in ['plant1', 'plant2', 'plant_water']) {
      final result = await OriginalAudio.channel.invokeMethod<bool>(
          'playPlantingSound', {'source': source, 'volume': .5});
      final state = await diag();
      h.check(
          result == true &&
              state['soundPlaying'] == true &&
              state['lastPlantingSource'] == source &&
              state['soundVolume'] == .5,
          'Native playback failed $source: $state');
      plays.add(state);
    }
    report['plays'] = plays;
    await channel.invokeMethod('activateWindow');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final board = h
        .find((w) => w is CustomPaint && w.painter is BoardPainter)!
        .renderObject as RenderBox;
    final pointer =
        board.localToGlobal(BoardGeometry(session.document).cellCenter(2, 1));
    GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: 1, position: pointer, buttons: 1));
    GestureBinding.instance
        .handlePointerEvent(PointerUpEvent(pointer: 1, position: pointer));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    final water = await diag();
    h.check(
        session.document.pieces.any((p) => p.row == 2 && p.col == 1) &&
            water['lastPlantingSource'] == 'plant_water',
        'Actual water pointer did not select water sound');
    report['actualWater'] = water;
    await OriginalAudio.setSoundVolume(0);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await OriginalAudio.playPlantingSound();
    final muted = await diag();
    h.check(muted['soundPlaying'] == false && muted['soundVolume'] == 0,
        'Muted native player still active');
    report['muted'] = muted;
    h.check(errors.isEmpty, 'Flutter errors $errors');
  } catch (e, stack) {
    report.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
  }
  report['errors'] = errors;
  await File('/tmp/pvz-planting-native-report.json')
      .writeAsString(jsonEncode(report));
}
