// Actual Flutter board pointers; only audio's platform channel is simulated.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/original_audio.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  final calls = <Map<String, dynamic>>[];
  ParityBinding.handlers[OriginalAudio.channel.name] = (call) async {
    calls.add({'method': call.method, 'args': call.arguments});
    return call.method == 'playPlantingSound' ? true : null;
  };
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final session = EditorSession(repo, persistDraft: false);
  final key = GlobalKey();
  final dir =
      await Directory('${Directory.systemTemp.path}/pvz-planting-feedback').create(recursive: true);
  final h = ParityHarness(key, dir);
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: key,
      child: MaterialApp(
          home: app.EditorPage(
              session: session, continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  final dynamic page =
      (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  page.tool = '放置';
  Future<void> plant(int row, int col) async {
    final board = h
        .find((w) => w is CustomPaint && w.painter is BoardPainter)
        .renderObject as RenderBox;
    final pointer = board
        .localToGlobal(BoardGeometry(session.document).cellCenter(row, col));
    GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: 1, position: pointer, buttons: 1));
    GestureBinding.instance
        .handlePointerEvent(PointerUpEvent(pointer: 1, position: pointer));
  }

  List<Map<String, dynamic>> played() =>
      calls.where((c) => c['method'] == 'playPlantingSound').toList();
  await h.run('feedback.load',
      'Three real source assets configure through audio channel', () async {
    await OriginalAudio.setSoundVolume(.5);
    final configured =
        calls.where((c) => c['method'] == 'configurePlantingSound').toList();
    h.expect(
        configured.length == 3 &&
            configured
                .map((c) => (c['args'] as Map)['source'])
                .toSet()
                .containsAll(['plant1', 'plant2', 'plant_water']),
        'Three sounds not loaded');
    h.expect(
        OriginalAudio.soundStatus.value == 'ready', 'Audio setup not ready');
  });
  await h.run('feedback.land-lifecycle',
      'Actual land pointer creates transient six-frame effect without timer edits',
      () async {
    session.execute(
        'soil',
        session.document
            .copy(display: {...session.document.display, '泥土': true}));
    await h.settle();
    await plant(0, 0);
    h.expect(
        session.document.pieces.length == 1 && page.growthEffects.length == 1,
        'Pointer plant/effect missing');
    h.expect(
        ['plant1', 'plant2'].contains((played().last['args'] as Map)['source']),
        'Land sound source wrong');
    final revision = session.revision;
    // Software rendering can consume the full 650ms between frames. Age only
    // this transient birth timestamp to inspect later frames deterministically.
    page.plantingBirths[(0, 0)] = page.plantingClock.elapsedMilliseconds - 510;
    final effects = page.growthEffects as List<GrowthEffect>;
    h.expect(effects.isNotEmpty && effects.single.frame >= 4,
        'Growth later frames missing');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    h.expect(page.growthEffects.isEmpty && session.revision == revision,
        'Growth expiry changed saved formation');
  });
  await h
      .run('feedback.water', 'Actual water-row planting selects water source',
          () async {
    await plant(2, 1);
    h.expect((played().last['args'] as Map)['source'] == 'plant_water',
        'Water source not selected');
    h.expect(page.growthEffects.any((dynamic e) => e.row == 2 && e.col == 1),
        'Water growth missing');
  });
  await h.run('feedback.visibility-volume',
      'Hidden soil has sound only; zero volume suppresses playback', () async {
    page.clearPlantingFeedback();
    session.execute(
        'hide soil',
        session.document
            .copy(display: {...session.document.display, '泥土': false}));
    await h.settle();
    final before = played().length;
    await plant(0, 2);
    h.expect(played().length == before + 1 && page.growthEffects.isEmpty,
        'Hidden soil must retain only sound');
    await OriginalAudio.setSoundVolume(0);
    final silent = played().length;
    await plant(0, 3);
    h.expect(played().length == silent, 'Zero volume played sound');
  });
  await h.run('feedback.terrain',
      'Actual pointers follow all-water, flood, reversed and restricted terrain; props stay silent',
      () async {
    await OriginalAudio.setSoundVolume(.5);
    final observations = <Map<String, dynamic>>[];
    Future<void> checkCell(String map, int row, int col, int terrain,
        {String type = 'pea'}) async {
      page.clearPlantingFeedback();
      session.execute('terrain fixture', Formation(mapId: map, display: {'泥土': true}));
      page.selectedType = type;
      await h.settle();
      final before = played().length;
      await plant(row, col);
      final effects = page.growthEffects as List<GrowthEffect>;
      final shouldFeedback = terrain != 0 && type == 'pea';
      h.expect(played().length == before + (shouldFeedback ? 1 : 0),
          '$map/$row/$col/$type audio feedback mismatch');
      h.expect(effects.isNotEmpty == shouldFeedback,
          '$map/$row/$col/$type particle feedback mismatch');
      String? source;
      if (shouldFeedback) {
        source = (played().last['args'] as Map)['source'] as String;
        h.expect(
            terrain == 2
                ? source == 'plant_water'
                : ['plant1', 'plant2'].contains(source),
            '$map/$row/$col wrong terrain audio source $source');
        h.expect(effects.single.water == (terrain == 2),
            '$map/$row/$col wrong terrain particle sheet');
      }
      observations.add({
        'map': map,
        'row': row,
        'col': col,
        'type': type,
        'expectedTerrain': terrain,
        'audioSource': source,
        'particle': effects.isNotEmpty
      });
    }

    await checkCell('allWater', 0, 0, 2);
    await checkCell('flood', 0, 1, 2);
    await checkCell('flood', 5, 1, 1);
    await checkCell('reversal', 0, 2, 2);
    await checkCell('reversal', 2, 2, 1);
    await checkCell('barren', 2, 3, 0);
    await checkCell('day3', 0, 3, 0);
    await checkCell('greenhouseRestricted', 2, 4, 0);
    await checkCell('day', 0, 4, 1, type: 'rake');
    await checkCell('day', 0, 5, 1, type: 'Lawnmower');
    await File('${Directory.systemTemp.path}/pvz-planting-terrain-observations.json')
        .writeAsString(jsonEncode(observations));
  });
  await h.report();
  await File('${Directory.systemTemp.path}/pvz-planting-feedback-report.json')
      .writeAsString(jsonEncode({
    'cases': h.cases,
    'scope':
        'actual Flutter pointers and effect lifecycle; simulated audio channel, real bundled mp3 assets'
  }));
  await OriginalAudio.dispose();
  session.dispose();
  await repo.close();
  exit(h.cases.every((c) => c['status'] == 'pass') ? 0 : 1);
}
