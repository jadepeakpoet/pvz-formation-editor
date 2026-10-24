// Actual Windows runner and live game; every preset uses a real pointer click.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/library/game_panel.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/platform/app_theme.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';
import 'package:pvz_formation_editor/platform/game_writes.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/domain/plant_game_state.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/domain/placement_layout.dart';
import 'settle_frames.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

List<Element> find(bool Function(Widget) test) {
  final result = <Element>[];
  void visit(Element e) {
    if (test(e.widget)) result.add(e);
    e.debugVisitOnstageChildren(visit);
  }

  visit(WidgetsBinding.instance.rootElement!);
  return result;
}

Future<void> settle() => settleFrames();
Future<void> tap(Element e) async {
  await Scrollable.ensureVisible(e, duration: Duration.zero);
  await settle();
  final box = e.renderObject as RenderBox;
  final point = box.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 97, position: point, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 97, position: point));
  await settle();
}

Future<void> tapKey(String key) {
  final matches = find((w) => w.key == ValueKey(key));
  return tap(key.startsWith('library-menu-') ? matches.first : matches.single);
}

String composition(Formation f) {
  final rows = f.pieces
      .map((p) =>
          '${p.type}:${p.row}:${p.col}:${p.asleep}:${p.effects.join(',')}:${PlantGameState.of(p)}')
      .toList()
    ..sort();
  return jsonEncode([f.mapId, rows]);
}

void check(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

@pragma('vm:entry-point')
Future<void> toolboxMain() => app.toolboxMain();
@pragma('vm:entry-point')
Future<void> libraryMain() => app.libraryMain();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OriginalAssets.ensureLoaded();
  final reportFile = File(Platform.environment['PVZ_BULK_REPORT']!);
  final report = <String, dynamic>{'results': <Map<String, dynamic>>[]};
  final results = report['results'] as List<Map<String, dynamic>>;
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  final repository = await FormationRepository.open(
      '${reportFile.parent.path}/live-preset-${newId()}.sqlite');
  GameFormationSnapshot? original;
  int? pid;
  Future<void> save() async {
    report['flutterErrors'] = errors;
    await reportFile.writeAsString(jsonEncode(report));
  }

  try {
    final requestedPid = int.tryParse(Platform.environment['PVZ_GAME_PID'] ?? '');
    final game = (await GameBridge.listGames()).firstWhere((g) =>
        g.canWrite && (requestedPid == null || g.pid == requestedPid));
    pid = game.pid;
    original = await GameBridge.readFormation(pid);
    report['pid'] = pid;
    report['initial'] = original.toJson();
    await save();
    // Reproduce the user's exact failure before the full catalog sweep.
    final sample = FormationExchange.decode(
        'LI5HDH/tAib/1HrXeldAXDjByF1AjX7kwjV5EJA18df513mXEtPBVT91RHxWRlfGVk91dlZnUYJejHa/VuVRBBhSVDSeSVlW');
    await GameWrites(Directory.systemTemp).apply(pid, sample);
    final sampleRead = await GameBridge.readFormation(pid);
    check(composition(sampleRead.formation) == composition(sample),
        'Historical sample live readback');
    report['historicalSample'] = {
      'pass': true,
      'objects': sampleRead.formation.pieces.length
    };
    await save();
    runApp(MaterialApp(
        theme: buildAppTheme(),
        home: app.LibraryPage(repository: repository, showTitle: false)));
    await settle();
    await settle();
    await settle();
    final dynamic library =
        (find((w) => w is app.LibraryPage).single as StatefulElement).state;
    final limit = int.tryParse(Platform.environment['PVZ_BULK_LIMIT'] ?? '') ??
        LibraryPresets.all.length;
    final selectedIds = (Platform.environment['PVZ_BULK_IDS'] ?? '')
        .split(',')
        .where((v) => v.isNotEmpty)
        .toSet();
    final presets = Platform.environment['PVZ_ENTRYPOINTS_ONLY'] == '1'
        ? <LibraryPreset>[]
        : LibraryPresets.all
            .where((p) => selectedIds.isEmpty || selectedIds.contains(p.id))
            .take(limit);
    for (final preset in presets) {
      final layout = PlacementLayout.prepare(preset.document);
      final row = <String, dynamic>{
        'id': preset.id,
        'name': preset.name,
        'map': preset.mapId,
        'objects': preset.document.pieces.length,
        'ignoredObjects': layout.skippedObjects,
        'simplifiedAppearances': layout.simplifiedAppearances,
      };
      try {
        final field =
            find((w) => w.key == const ValueKey('library-search')).single;
        final editable = find((w) =>
                w is EditableText &&
                w.controller == (field.widget as TextField).controller).single
            as StatefulElement;
        (editable.state as EditableTextState).updateEditingValue(
            TextEditingValue(
                text: preset.name,
                selection:
                    TextSelection.collapsed(offset: preset.name.length)));
        await settle();
        // At 810px the selected result's detail panel is retained alongside the list.
        await tapKey('library-item-preset:${preset.id}');
        await settle();
        await tapKey('library-apply-game');
        for (var i = 0; i < 250 && library.applyingArchiveToGame == true; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        check(library.applyingArchiveToGame == false, 'Application timed out');
        final actual = await GameBridge.readFormation(pid);
        check(composition(actual.formation) == composition(
            layout.document),
            'Readback differs: ${find((w) => w is SnackBar).map((e) => (e.widget as SnackBar).content).toList()}');
        check(actual.formation.sunValue == original.formation.sunValue,
            'Sun changed');
        row['pass'] = true;
        row['applied'] = true;
        row['readbackObjects'] = actual.formation.pieces.length;
      } catch (e) {
        row['pass'] = false;
        row['error'] = '$e';
        row['visibleMessages'] = find((w) => w is Text)
            .map((e) => (e.widget as Text).data)
            .whereType<String>()
            .where((s) => s.contains('失败'))
            .toList();
      }
      results.add(row);
      await save();
      final context = find((w) => w is app.LibraryPage).single;
      ScaffoldMessenger.of(context).clearSnackBars();
      stdout.writeln(
          '${results.length}/$limit ${row['pass'] == true ? 'PASS' : 'FAIL'} ${preset.name}');
    }
    final archiveManifest = Platform.environment['PVZ_ARCHIVE_COPIES'];
    if (archiveManifest != null) {
      final archiveResults = <Map<String, dynamic>>[];
      report['userArchives'] = archiveResults;
      final sources = jsonDecode(await File(archiveManifest).readAsString()) as List;
      var index = 0;
      for (final source in sources) {
        final copied = await FormationRepository.open(source['copy'] as String);
        for (final archive in await copied.listArchives()) {
          final id = 'user-verification-${index++}';
          final document = Formation.fromJson(archive.document);
          final gameLayout = PlacementLayout.prepare(document).document;
          await repository.saveArchive(id: id, name: id, document: document.toJson());
          await library.refresh();
          await settle();
          final search = find((w) => w.key == const ValueKey('library-search')).single;
          final editable = find((w) => w is EditableText &&
              w.controller == (search.widget as TextField).controller).single as StatefulElement;
          (editable.state as EditableTextState).updateEditingValue(TextEditingValue(
              text: id, selection: TextSelection.collapsed(offset: id.length)));
          await settle();
          await tapKey('library-item-archive:$id');
          final before = await GameBridge.readFormation(pid);
          await tapKey('library-apply-game');
          for (var i = 0; i < 250 && library.applyingArchiveToGame == true; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          final after = await GameBridge.readFormation(pid);
          final messages = find((w) => w is Text).map((e) => (e.widget as Text).data ?? '').join('\n');
          final rejected = messages.contains('失败');
          final unsupported = gameLayout.pieces.any((p) =>
              (!WebsiteCodec.plantIds.contains(p.type) &&
                  !{'grave', 'ladder', 'rake'}.contains(p.type)) ||
              p.scale != 1 || p.opacity != 1 || p.flipped || p.flippedVertical ||
              p.effects.any((effect) => effect != '模仿者') ||
              (p.type == 'cob' && p.frameRow != 0));
          check(rejected == unsupported, 'Unexpected rejection for user archive $id');
          final matched = composition(after.formation) ==
              composition(rejected ? before.formation : gameLayout);
          archiveResults.add({'id': id, 'pass': matched,
            'rejected': rejected, if (rejected) 'messages': messages});
          await save();
          check(matched, 'User archive $id readback differs');
          ScaffoldMessenger.of(find((w) => w is app.LibraryPage).single).clearSnackBars();
        }
        await copied.close();
      }
    }
    if (Platform.environment['PVZ_VERIFY_ENTRYPOINTS'] == '1') {
      await tapKey('library-section-预制名阵');
      final entryResults = <String>[];
      Future<void> verify(String name, Formation expected) async {
        final actual = await GameBridge.readFormation(pid!);
        check(composition(actual.formation) == composition(PlacementLayout.prepare(expected).document),
            '$name readback differs');
        check(actual.formation.sunValue == original!.formation.sunValue,
            '$name sun changed');
        entryResults.add(name);
        report['entrypoints'] = entryResults;
        await save();
      }

      Future<void> finishLibraryApply() async {
        for (var i = 0; i < 250 && library.applyingArchiveToGame == true; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      final search =
          find((w) => w.key == const ValueKey('library-search')).single;
      final editable = find((w) =>
              w is EditableText &&
              w.controller == (search.widget as TextField).controller).single
          as StatefulElement;
      (editable.state as EditableTextState).updateEditingValue(
          const TextEditingValue(
              text: '[0] PE-', selection: TextSelection.collapsed(offset: 7)));
      await settle();
      final preset = LibraryPresets.all.first;
      await tapKey('library-menu-preset:${preset.id}');
      await tap(
          find((w) => w is PopupMenuItem<String> && w.value == 'apply-game')
              .single);
      await finishLibraryApply();
      await verify('preset-more-menu', preset.document);
      await repository.saveArchive(
          id: 'live-archive',
          name: 'Live verification',
          document: sample.toJson());
      await library.refresh();
      await settle();
      await tapKey('library-section-我的存档');
      final search2 =
          find((w) => w.key == const ValueKey('library-search')).single;
      final editable2 = find((w) =>
              w is EditableText &&
              w.controller == (search2.widget as TextField).controller).single
          as StatefulElement;
      (editable2.state as EditableTextState)
          .updateEditingValue(TextEditingValue.empty);
      await settle();
      await tapKey('library-item-archive:live-archive');
      await tapKey('library-apply-game');
      await finishLibraryApply();
      await verify('archive-detail', sample);
      await tapKey('library-menu-archive:live-archive');
      await tap(
          find((w) => w is PopupMenuItem<String> && w.value == 'apply-game')
              .single);
      await finishLibraryApply();
      await verify('archive-more-menu', sample);
      final visual = Formation(mapId: 'pool', pieces: [
        Piece(id: 'empty-cob', type: 'cob', row: 0, col: 0, layer: 10, frameCol: 2),
        Piece(id: 'damaged-nut', type: 'wallnut', row: 1, col: 0, layer: 10, frameCol: 3),
        Piece(id: 'armed-mine', type: 'potato', row: 1, col: 1, layer: 10, frameCol: 1),
      ]);
      final session =
          EditorSession(repository, document: visual, persistDraft: false);
      runApp(MaterialApp(
          theme: buildAppTheme(),
          home: app.EditorPage(
              session: session,
              toolboxOnly: true,
              continueArchive: (_) async {})));
      await settle();
      await settle();
      await tapKey('toolbox-tab-4');
      await settle();
      final dynamic editor =
          (find((w) => w is app.EditorPage).single as StatefulElement).state;
      await tapKey('formation-inject-game');
      for (var i = 0; i < 250 && editor.gameBusy == true; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await verify('editor-load-export-visual-states', visual);
      await tapKey('formation-read-game');
      for (var i = 0; i < 250 && editor.gameBusy == true; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      check(
          composition(FormationExchange.decode(editor.inputFormation.text)) ==
              composition(visual),
          'Editor read button result');
      entryResults.add('editor-read-game');
      runApp(MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
              body: GamePanel(
                  target: sample,
                  onArchive: (_) async {},
                  onEdit: (_) async {}))));
      await settle();
      await settle();
      await tap(find((w) => w is Text && w.data == '应用到游戏').single);
      await settle();
      await settle();
      await verify('game-panel', sample);
    }
    report['completed'] = true;
    report['passed'] = results.where((r) => r['pass'] == true).length;
    report['failed'] = results.where((r) => r['pass'] != true).length;
    report['applied'] = results.where((r) => r['applied'] == true).length;
    report['expectedRejections'] = results.where((r) => r['expectedRejection'] == true).length;
  } catch (e, st) {
    report['fatal'] = '$e\n$st';
  } finally {
    if (original != null && pid != null) {
      try {
        await GameWrites(Directory.systemTemp).apply(pid, original.formation);
        final restored = await GameBridge.readFormation(pid);
        report['restoredOriginal'] =
            composition(restored.formation) == composition(original.formation);
      } catch (e) {
        report['restoreError'] = '$e';
      }
    }
    await save();
    await repository.close();
  }
  stdout.writeln(jsonEncode({
    'historicalSample': report['historicalSample'],
    'passed': report['passed'],
    'failed': report['failed'],
    'fatal': report['fatal']
  }));
  exit(report['fatal'] == null && report['failed'] == 0 &&
      report['restoredOriginal'] == true ? 0 : 1);
}
