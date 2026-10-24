// Real Flutter engine benchmark. Prepared separately from functional acceptance.
// Run only after functional smoke tests finish; writes no user files/preferences.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/original_catalog.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/shovel_targets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

final results = <String, Object?>{};
int checksum = 0;
Map<String, Object> summary(List<double> samples,
    {int operationsPerSample = 1}) {
  final sorted = [...samples]..sort();
  double percentile(double p) =>
      sorted[(math.max(0, (sorted.length * p).ceil() - 1)).toInt()];
  return {
    'unit': 'ms',
    'samples': samples,
    'sampleCount': samples.length,
    'operationsPerSample': operationsPerSample,
    'median': percentile(.5),
    'p95': percentile(.95),
    'p99': percentile(.99),
    'min': sorted.first,
    'max': sorted.last,
  };
}

Future<void> measure(String key, int count, Future<void> Function() body,
    {int warmup = 1, int operations = 1}) async {
  for (var i = 0; i < warmup; i++) {
    await body();
  }
  final values = <double>[];
  for (var i = 0; i < count; i++) {
    final watch = Stopwatch()..start();
    await body();
    watch.stop();
    values.add(watch.elapsedMicroseconds / 1000);
  }
  results[key] = summary(values, operationsPerSample: operations);
  stdout.writeln('$key ${jsonEncode(results[key])}');
}

Formation fixture(int count) => Formation(
        pieces: List.generate(count, (i) {
      final type =
          const ['pea', 'sunflower', 'pumpkin', 'pot', 'ladder'][i % 5];
      return Piece(
          id: 'benchmark-$i',
          type: type,
          row: (i ~/ 9) % 6,
          col: i % 9,
          layer: ObjectSpec.byId(type).layer);
    }));

Future<void> paint(Formation doc,
    {bool raster = false, bool png = false}) async {
  final recorder = ui.PictureRecorder();
  BoardPainter(document: doc, helpers: false)
      .paint(Canvas(recorder), const Size(800, 600));
  final picture = recorder.endRecording();
  try {
    if (raster || png) {
      final image = await picture.toImage(800, 600);
      try {
        if (png) {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          checksum ^= bytes!.lengthInBytes;
        }
      } finally {
        image.dispose();
      }
    }
  } finally {
    picture.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final output = Platform.environment['PVZ_PERFORMANCE_OUTPUT'] ??
      '${Directory.systemTemp.path}/pvz-performance-report.json';
  final dir = await Directory.systemTemp.createTemp('pvz-performance-');
  FormationRepository? repo;
  EditorSession? session;
  final report = <String, Object?>{
    'environment': {
      'dart': Platform.version,
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'engine': 'flutter_tester, debug kernel, software rendering expected',
      'canvas': {'width': 800, 'height': 600, 'pixelRatio': 1},
      'frameTiming': 'not collected: offscreen PictureRecorder workloads have no '
          'reliable native vsync FrameTiming; these results do not establish 60fps',
      'preferences':
          'not loaded or changed; database uses disposable temporary directory',
    },
    'notes': [
      'Dense fixtures intentionally overlap objects across 54 cells; stress cases are not normal game formations.',
      'Percentiles use nearest rank; single-sample operations cannot estimate a latency distribution.',
      'Timings include Dart scheduling/GC and are diagnostic, without pass/fail thresholds.',
      'Index benchmark is a reproducible domain surrogate, not measured LibraryBrowser widget latency.',
    ],
    'results': results,
  };
  try {
    // A fresh process is necessary for this single cold-start sample.
    await measure('assets.coldLoad', 1, OriginalAssets.ensureLoaded, warmup: 0);
    await measure('assets.cachedLoad', 20, OriginalAssets.ensureLoaded);
    final presets = OriginalCatalog.formations;
    report['presetCount'] = presets.length;
    await measure('presets.decodeAll', 5, () async {
      for (final p in presets) {
        checksum ^= p.decode().pieces.length;
      }
    }, operations: presets.length);
    late List<Map<String, Object>> index;
    await measure('presets.buildSearchIndex', 5, () async {
      index = [
        for (final p in presets)
          {
            'name': p.name.toLowerCase(),
            'map': p.decode().mapId,
            'cannons': p.decode().pieces.where((p) => p.type == 'cob').length,
          }
      ];
      checksum ^= index.length;
    }, operations: presets.length);
    await measure('presets.indexFilter1000', 10, () async {
      for (var i = 0; i < 1000; i++) {
        final query = const ['炮', '无炮', '水', '八', ''][i % 5];
        checksum ^= index
            .where((e) =>
                (e['name'] as String).contains(query) &&
                (i % 2 == 0 || e['cannons'] == i % 10))
            .length;
      }
    }, operations: 1000);
    for (final count in [80, 500, 1500, 5000]) {
      final doc = fixture(count);
      final samples = count == 5000 ? 3 : 7;
      await measure('board.$count.record', samples, () => paint(doc));
      await measure('board.$count.recordAndRaster', samples,
          () => paint(doc, raster: true));
      await measure('export.$count.png800x600', count == 5000 ? 2 : 3,
          () => paint(doc, png: true),
          warmup: 0);
    }
    final dense = fixture(5000);
    await measure('shovel.5000objects.1000smartHits', 3, () async {
      for (var i = 0; i < 1000; i++) {
        final point = Offset(
            40 + (i * 37 % 720).toDouble(), 80 + (i * 53 % 500).toDouble());
        checksum ^= ShovelTargets.at(dense, point, '智能').length;
      }
    }, warmup: 0, operations: 1000);
    repo = await FormationRepository.open('${dir.path}/benchmark.sqlite');
    final database = repo;
    // Turn persistence off to isolate editing latency from SQLite queue work.
    session =
        EditorSession(database, document: fixture(80), persistDraft: false);
    final editing = session;
    await measure('session.1000edits', 1, () async {
      for (var i = 0; i < 1000; i++) {
        editing.execute('performance edit', editing.document.copy(sunValue: i));
      }
    }, warmup: 0, operations: 1000);
    await measure('session.1000undo', 1, () async {
      for (var i = 0; i < 1000; i++) {
        editing.undo();
      }
    }, warmup: 0, operations: 1000);
    await measure('session.1000redo', 1, () async {
      for (var i = 0; i < 1000; i++) {
        editing.redo();
      }
    }, warmup: 0, operations: 1000);
    editing.dispose();
    session = null;
    // Real persisted editing: report synchronous enqueue separately from drain.
    session = EditorSession(database, document: fixture(80));
    final persisted = session;
    await persisted.flush();
    await measure('sqlite.enqueue1000edits', 1, () async {
      for (var i = 0; i < 1000; i++) {
        persisted.execute(
            'persisted performance edit', persisted.document.copy(sunValue: i));
      }
    }, warmup: 0, operations: 1000);
    await measure('sqlite.flush1000queuedEdits', 1, persisted.flush,
        warmup: 0, operations: 1000);
    if (persisted.error != null) throw StateError('${persisted.error}');
    report['archiveVersions'] =
        (await database.listVersions(persisted.sourceArchiveId!)).length;
    report['checksum'] = checksum;
    report['status'] = 'complete';
  } catch (error, stack) {
    report['status'] = 'failed';
    report['error'] = '$error';
    report['stack'] = '$stack';
    exitCode = 1;
  } finally {
    session?.dispose();
    await repo?.close();
    await dir.delete(recursive: true);
    await File(output)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln('Performance report: $output');
  }
  exit(exitCode);
}
