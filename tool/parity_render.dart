// Compile/run with the real Flutter engine using the commands in docs/parity-render.md.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/original_catalog.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['PVZ_PARITY_DIR'] ?? '/tmp/pvz-parity';
  final manifestPath =
      Platform.environment['PVZ_PARITY_MANIFEST'] ?? 'docs/parity-cases.json';
  final results = <Map<String, dynamic>>[];
  var failures = 0;
  try {
    await OriginalAssets.ensureLoaded();
    final cases = <Map<String, dynamic>>[];
    void add(String id, Formation formation) =>
        cases.add({'id': id, 'formation': formation.toJson()});
    for (final map in BoardMap.all.where((m) => m.originalIndex != null)) {
      add('map-${map.originalIndex}', Formation(mapId: map.id));
    }
    for (final key in Formation().display.keys) {
      for (final value in [false, true]) {
        add('setting-$key-$value',
            Formation(display: {...Formation().display, key: value}));
      }
    }
    for (var columns = 0; columns <= 10; columns++) {
      add(
          'setting-fog-$columns',
          Formation(
              mapId: 'fog',
              fogColumns: columns,
              display: {...Formation().display, '迷雾': true}));
    }
    add(
        'setting-seedSlots',
        Formation(
            seedSlots: ObjectSpec.all
                .where((s) => s.category == '植物')
                .take(10)
                .map((s) => s.id)
                .toList()));
    for (final spec in ObjectSpec.all) {
      final data =
          OriginalAssets.sprites[OriginalAssets.names[spec.id] ?? spec.id];
      final parts = data?['images'] as List? ?? [];
      final rows = parts.fold<int>(
          1,
          (n, p) =>
              (p['rows'] as num).toInt() > n ? (p['rows'] as num).toInt() : n);
      final cols = parts.fold<int>(
          1,
          (n, p) =>
              (p['cols'] as num).toInt() > n ? (p['cols'] as num).toInt() : n);
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          add(
              'object-${spec.id}-frame-$r-$c',
              Formation(pieces: [
                Piece(
                    id: 'subject',
                    type: spec.id,
                    row: 1,
                    col: 2,
                    layer: spec.layer,
                    frameRow: r,
                    frameCol: c)
              ]));
        }
      }
      for (final effect in ['模仿者', '灰烬', '冰冻', '魅惑', '半透明', '阴影', '高亮']) {
        add(
            'object-${spec.id}-effect-$effect',
            Formation(pieces: [
              Piece(
                  id: 'subject',
                  type: spec.id,
                  row: 1,
                  col: 2,
                  layer: spec.layer,
                  effects: {effect})
            ]));
      }
      for (final flip in ['horizontal', 'vertical', 'both']) {
        add(
            'object-${spec.id}-flip-$flip',
            Formation(pieces: [
              Piece(
                  id: 'subject',
                  type: spec.id,
                  row: 1,
                  col: 2,
                  layer: spec.layer,
                  flipped: flip != 'vertical',
                  flippedVertical: flip != 'horizontal')
            ]));
      }
    }
    for (final entry in OriginalCatalog.formations) {
      cases.add({'id': 'preset-${entry.index}', 'presetString': entry.source});
    }
    final manifest = File(manifestPath);
    if (manifest.existsSync()) {
      final parsed = jsonDecode(manifest.readAsStringSync());
      for (final entry in (parsed is List ? parsed : parsed['cases']) as List) {
        final item = Map<String, dynamic>.from(entry as Map);
        cases.removeWhere((e) => e['id'] == item['id']);
        cases.add(item);
      }
    }
    Directory('$root/flutter').createSync(recursive: true);
    final filter = Platform.environment['PVZ_PARITY_FILTER'];
    final previous = File('$root/render-results.json');
    if (filter != null && previous.existsSync()) {
      results.addAll(
          ((jsonDecode(previous.readAsStringSync()) as Map)['cases'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map)));
    }
    for (final item in cases) {
      final id = item['id'] as String;
      if (const {'toolbox', 'full', 'window'}.contains(item['kind'])) continue;
      if (filter != null && !RegExp(filter).hasMatch(id)) continue;
      if (!RegExp(r'^[a-zA-Z0-9_\-\u4e00-\u9fff]+$').hasMatch(id)) {
        throw FormatException('Unsafe case id: $id');
      }
      results.removeWhere((e) => e['id'] == id);
      try {
        final raw = item['formation'] ?? item['document'];
        Formation formation;
        if (raw != null) {
          formation = Formation.fromJson(Map<String, dynamic>.from(raw as Map));
        } else if (item['presetString'] is String) {
          formation = WebsiteCodec.decode(item['presetString'] as String);
        } else if (item['partialFamily'] != null) {
          final family = item['partialFamily'];
          final index = item['presetIndex'] as int;
          final presets = family == 'cob'
              ? OriginalCatalog.cobLayouts
              : family == 'gloom'
                  ? OriginalCatalog.gloomLayouts
                  : throw FormatException('Unknown partial family: $family');
          formation = presets[index].decode();
        } else if (item['presetIndex'] is int) {
          formation =
              OriginalCatalog.formations[item['presetIndex'] as int].decode();
        } else if (item['control'] != null) {
          formation = WebsiteCodec.decode('0,0 2 3 0 0 0000001');
        } else {
          throw FormatException(
              'Case $id has no document, source string or preset index');
        }
        if (item['soil'] is bool) {
          formation = formation.copy(
              display: {...formation.display, '泥土': item['soil'] as bool});
        }
        if (item['control'] != null) {
          const controls = {
            'cSoil': '泥土',
            'rSeed': '卡槽',
            'rClear': '小推车',
            'rBrain': '脑子',
            'rCtc': '继续标识'
          };
          final key = controls[item['control']];
          if (key == null) {
            throw FormatException(
                'Unknown display control: ${item['control']}');
          }
          formation = formation.copy(display: {
            ...formation.display,
            key: item['checked'] == true,
            if (key == '卡槽') '阳光': item['checked'] == true
          });
        }
        final output = '$root/flutter/$id.png';
        final recorder = ui.PictureRecorder();
        BoardPainter(
                document: formation,
                growthEffects: [
                  for (final effect in item['growthEffects'] as List? ?? [])
                    GrowthEffect(
                        row: effect['row'] as int,
                        col: effect['col'] as int,
                        frame: effect['frame'] as int,
                        water: effect['water'] as bool?)
                ],
                background: item['background'] != false,
                helpers: item['helpers'] != false)
            .paint(Canvas(recorder), const Size(800, 600));
        final picture = recorder.endRecording();
        final image = await picture.toImage(800, 600);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(output).writeAsBytesSync(bytes!.buffer
            .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
        image.dispose();
        picture.dispose();
        final missingSprites = formation.pieces
            .where((p) => !OriginalAssets.sprites
                .containsKey(OriginalAssets.names[p.type] ?? p.type))
            .map((p) => p.type)
            .toSet()
            .toList();
        results.add({
          'id': id,
          'missingSpriteTemplates': missingSprites,
          'status': 'rendered',
          'png': output,
          'width': 800,
          'height': 600,
          'formation': formation.toJson(),
          'objectBounds': [
            for (final p in formation.pieces)
              {
                'id': p.id,
                'type': p.type,
                'rect': [
                  BoardGeometry(formation)
                      .pieceBounds(p)
                      .left
                      .floor()
                      .clamp(0, 799),
                  BoardGeometry(formation)
                      .pieceBounds(p)
                      .top
                      .floor()
                      .clamp(0, 599),
                  BoardGeometry(formation)
                      .pieceBounds(p)
                      .right
                      .ceil()
                      .clamp(1, 800),
                  BoardGeometry(formation)
                      .pieceBounds(p)
                      .bottom
                      .ceil()
                      .clamp(1, 600)
                ]
              }
          ],
          if (item['reference'] != null) 'reference': item['reference']
        });
      } catch (error) {
        failures++;
        results.add({'id': id, 'status': 'error', 'error': '$error'});
      }
    }
    File('$root/render-results.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'cases': results,
      'rendered': results.where((e) => e['status'] == 'rendered').length,
      'failed': results.where((e) => e['status'] == 'error').length,
      'note': 'Rendering success alone is not reference parity.'
    }));
    stdout.writeln(
        'Rendered ${results.length - failures}/${results.length}; errors $failures. $root/render-results.json');
    exit(failures == 0 ? 0 : 1);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
