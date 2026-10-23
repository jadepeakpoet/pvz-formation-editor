// Real Flutter navigation, picker pointers and SQLite. Only file dialog mocked.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/library/library_browser.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final first = EditorSession(repo,
      persistDraft: false,
      name: '我的庭院',
      document: Formation(
          pieces: [Piece(id: 'mine', type: 'pea', row: 0, col: 0, layer: 10)]));
  final tabs = EditorTabsController(repo, initial: first);
  await tabs.ready;
  final key = GlobalKey();
  final h = ParityHarness(key,
      await Directory('/tmp/pvz-formation-navigation').create(recursive: true));
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: key,
      child: MaterialApp(
          home: app.EditorWorkspace(
              controller: tabs, continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  dynamic page() =>
      (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  Future<void> settled() async {
    await h.settle();
    await tabs.ready;
    await h.settle();
  }

  Future<void> selectCells(List<(int, int)> coordinates) async {
    page().selectToolboxTab(2);
    await h.settle();
    await h.tap('批量选择');
    page().updateBatchSelection(
        coordinates.map((cell) => cell.$1).toSet(),
        coordinates.map((cell) => cell.$2).toSet());
    await h.settle();
  }

  await h.run('picker.history',
      'Library-style single click opens current page; back restores name/document',
      () async {
    page().selectToolboxTab(1);
    await h.settle();
    final original = first.document.fingerprint;
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('preset-selector-阵型')));
    h.expect(
        h
            .all((w) => w.key == const ValueKey('formation-preset-picker'))
            .isNotEmpty,
        'Picker did not open');
    await h.tapElement(h.find((w) =>
        w.key ==
        ValueKey('library-item-preset:${LibraryPresets.all.first.id}')));
    await settled();
    h.expect(
        tabs.sessions.length == 1 &&
            tabs.active.name == LibraryPresets.all.first.name &&
            tabs.active.document.fingerprint ==
                LibraryPresets.all.first.document.fingerprint &&
            tabs.canGoBack,
        'Picker did not navigate current page');
    h.expect(
        page().pickingPresetGroup == null &&
            page().classicTab == 1 &&
            h
                .all((w) => w.key == const ValueKey('formation-preset-picker'))
                .isEmpty,
        'Selecting a formation must return to lazy-layout home');
    await tabs.goBack();
    await settled();
    h.expect(
        identical(tabs.active, first) &&
            tabs.active.name == '我的庭院' &&
            tabs.active.document.fingerprint == original,
        'Back lost original name/document');
  });
  await h.run('picker.scene-row-tabs',
      'Partial previews use their own scenes, row defaults and full-formation tab',
      () async {
    final original = tabs.active.document;
    for (final mapId in ['day', 'pool', 'day6', 'day3', 'day1', 'roof']) {
      tabs.active.execute('test scene', original.copy(mapId: mapId));
      for (final group in ['炮位', '无炮']) {
        stdout.writeln('checking layout tabs: $mapId / $group');
        await page().chooseFormationPreset(group);
        await h.settle();
        final expected = BoardMap.byId(mapId).rows == 6 ? 6 : 5;
        h.expect((h.find((w) => w.key == ValueKey('preset-rows-$expected'))
            .widget as ChoiceChip).selected, 'Wrong default tab on $mapId');
        final tabBoxes = [for (final value in [0, 6, 5])
          h.find((w) => w.key == ValueKey('preset-rows-$value')).renderObject as RenderBox];
        h.expect(tabBoxes[0].localToGlobal(Offset.zero).dx <
            tabBoxes[1].localToGlobal(Offset.zero).dx &&
            tabBoxes[1].localToGlobal(Offset.zero).dx <
            tabBoxes[2].localToGlobal(Offset.zero).dx,
            'Preset tabs must be ordered formation / six / five');
        final hint = h.find((w) => w is Text && w.data == '局部布局');
        var fixedHint = false;
        hint.visitAncestorElements((element) {
          if (element.widget is SizedBox &&
              (element.widget as SizedBox).height == 32) {
            fixedHint = true;
            return false;
          }
          return true;
        });
        h.expect(fixedHint, 'Partial hint must reserve the same 32px option row');
        double? browserTop;
        for (final rows in [5, 6]) {
          await h.tapElement(h.find((w) => w.key == ValueKey('preset-rows-$rows')));
          final browserElement = h.find((w) => w is LibraryBrowser);
          final top = (browserElement.renderObject as RenderBox)
              .localToGlobal(Offset.zero).dy;
          browserTop ??= top;
          h.expect((top - browserTop).abs() < .1,
              'Switching partial row tabs moved the list');
          final browser = browserElement.widget as LibraryBrowser;
          h.expect(browser.presets.isNotEmpty, 'Empty layout tab');
          for (final preset in browser.presets) {
            final scene = preset.name.startsWith('泳池-') ? 'pool'
                : preset.name.startsWith('屋顶-') ? 'roof' : 'day';
            h.expect(preset.mapId == scene && preset.document.map.rows == rows,
                'Wrong scene/row for ${preset.name} on $mapId');
          }
        }
        await h.tapElement(h.find((w) => w.key == const ValueKey('preset-rows-0')));
        final fullElement = h.find((w) => w is LibraryBrowser);
        h.expect(((fullElement.renderObject as RenderBox)
            .localToGlobal(Offset.zero).dy - browserTop!).abs() < .1,
            'Full formation option row must not move the list');
        final full = fullElement.widget as LibraryBrowser;
        h.expect(identical(full.presets, LibraryPresets.all),
            'Third tab should list all full formations');
        await h.tapElement(h.find((w) => w.key == const ValueKey('preset-rows-5')));
        final partial = h.find((w) => w is LibraryBrowser).widget as LibraryBrowser;
        h.expect(partial.presets.every((p) => p.id.startsWith('$group-')),
            'Switching back lost partial-layout family');
      }
    }
    await h.screenshot('layout-five-row-tabs');
    await h.tapElement(h.find((w) => w.key == const ValueKey('preset-rows-6')));
    await h.screenshot('layout-six-row-tabs');
    h.expect(tabs.active.document.mapId == 'roof', 'Browsing changed board');
    tabs.active.execute('restore scene', original);
  });

  await h.run('picker.change-map-option',
      'Full presets default to own map and can preserve current scene', () async {
    final previous = tabs.active;
    previous.execute('test scene', previous.document.copy(mapId: 'day'));
    await page().chooseFormationPreset('阵型');
    await h.settle();
    Checkbox option() => h.find((w) =>
        w.key == const ValueKey('original-preset-change-map')).widget as Checkbox;
    h.expect(option().value == true, 'Change-map option must default enabled');
    final source = LibraryPresets.all.firstWhere((p) => p.mapId == 'pool' &&
        p.document.pieces.any((piece) => piece.row == 5));
    await h.tapElement(h.find((w) =>
        w.key == const ValueKey('original-preset-change-map')));
    h.expect((page().windowState() as Map)['presetChangeMap'] == false,
        'Preset map option missing from window state');
    await page().useFormationPreset('阵型', source.sourceIndex);
    await settled();
    h.expect(tabs.active.document.mapId == 'day' &&
        tabs.active.document.pieces.every((p) => p.row < 5) &&
        tabs.active.document.pieces.length == source.document.pieces
            .where((p) => source.document.fits(p, BoardMap.byId('day'))).length,
        'Unchecked preset should preserve map and exclude out-of-bounds plants');
    await tabs.goBack();
    await settled();
    await page().chooseFormationPreset('阵型');
    await h.settle();
    await h.tapElement(h.find((w) =>
        w.key == const ValueKey('original-preset-change-map')));
    await page().useFormationPreset('阵型', source.sourceIndex);
    await settled();
    h.expect(tabs.active.document.fingerprint == source.document.fingerprint,
        'Checked preset should use exact full source and own map');
    await tabs.goBack();
    await settled();
  });

  await h.run('picker.layout-return',
      'Cannon and no-cannon selections also return to lazy-layout home',
      () async {
    for (final group in ['炮位', '无炮']) {
      await page().chooseFormationPreset(group);
      await h.settle();
      final choice = page().presetSources(group).first;
      await page().useFormationPreset(group, choice.index);
      await settled();
      h.expect(
          page().pickingPresetGroup == null &&
              page().classicTab == 1 &&
              h
                  .all(
                      (w) => w.key == const ValueKey('formation-preset-picker'))
                  .isEmpty,
          '$group selection remained in the preset list');
    }
  });
  await h.run(
      'readonly.layout', 'Lazy layouts remain selectable in readonly previews',
      () async {
    await tabs.open(EditorSession(repo,
        document: LibraryPresets.all.first.document,
        name: '只读预览',
        readOnly: true));
    await settled();
    page().selectToolboxTab(1);
    await h.settle();
    final tile = h
        .find((w) => w.key == const ValueKey('preset-selector-炮位'))
        .widget as ListTile;
    h.expect(tile.onTap != null, 'Readonly preview disabled layout picker');
    await page().navigateFormation(Formation(mapId: 'day'), name: '新布局');
    await settled();
    h.expect(!tabs.active.readOnly && tabs.active.name == '新布局',
        'Layout did not become editable');
    await tabs.goBack();
    await settled();
    h.expect(tabs.active.readOnly && tabs.active.name == '只读预览',
        'Readonly history lost');
  });
  await h.run('import.history',
      'Actual import path enters history despite file-operation guard',
      () async {
    final imported = Formation(mapId: 'day', pieces: [
      Piece(id: 'import', type: 'wallnut', row: 1, col: 1, layer: 10)
    ]);
    ParityBinding.handlers['pvz_formation_editor/files'] = (call) async {
      if (call.method == 'pickFormation') {
        return {
          'path': '/tmp/导入测试.pvzf.json',
          'bytes': Uint8List.fromList(utf8.encode(FormationExchange.encode(
              imported,
              format: FormationFormat.project))),
        };
      }
      return null;
    };
    final previous = tabs.active;
    await page().transfer('import');
    await settled();
    h.expect(
        !identical(tabs.active, previous) &&
            tabs.active.document.fingerprint == imported.fingerprint &&
            tabs.active.filePath == '/tmp/导入测试.pvzf.json',
        'Import navigation failed');
    await tabs.goBack();
    await settled();
    h.expect(identical(tabs.active, previous),
        'Import history did not restore previous entry');
  });
  await h.run('maps.undo',
      'Map changes keep the current page and undo restores its document', () async {
    final previous = tabs.active;
    final original = previous.document.fingerprint;
    final name = previous.name;
    await page().applyMapSelection('roof', false);
    await settled();
    h.expect(identical(tabs.active, previous) &&
        previous.document.mapId == 'roof', 'Map replacement failed');
    await page().undoEditing();
    await settled();
    h.expect(identical(tabs.active, previous) &&
        previous.document.fingerprint == original && previous.name == name,
        'Map undo failed');
    page().selectToolboxTab(1);
    await h.settle();
  });
  await h.run('clear.unified-undo',
      'Clear is immediate and the same Undo restores edits, names and navigation',
      () async {
    final doc = Formation(pieces: [
      Piece(id: 'clear-target', type: 'pea', row: 0, col: 0, layer: 10)
    ]);
    await page().navigateFormation(doc, name: '原始名称');
    await settled();
    page().selectToolboxTab(2);
    await h.settle();
    final session = tabs.active;
    await h
        .tapElement(h.find((w) => w.key == const ValueKey('clear-formation')));
    await settled();
    h.expect(
        identical(tabs.active, session) &&
            session.document.pieces.isEmpty &&
            h.all((w) => w is AlertDialog).isEmpty,
        'Clear navigated or asked for confirmation');
    await page().undoEditing();
    await settled();
    h.expect(session.document.fingerprint == doc.fingerprint,
        'Undo did not restore cleared plants');
    session.rename('修改名称');
    await page().undoEditing();
    await settled();
    h.expect(session.name == '原始名称', 'Rename not undoable');
    await page().navigateFormation(Formation(mapId: 'roof'), name: '另一阵型');
    await settled();
    await page().undoEditing();
    await settled();
    h.expect(identical(tabs.active, session) && tabs.active.name == '原始名称',
        'Unified Undo did not restore previous page/name');
    await page().redoEditing();
    await settled();
    h.expect(
        tabs.active.name == '另一阵型', 'Unified Redo did not restore navigation');
    page().selectToolboxTab(1);
    await h.settle();
  });
  await h.run('format.last-wins.undo',
      'Unsupported output offers one-click formatting; later object wins and Undo restores source',
      () async {
    final source = Formation(pieces: [
      Piece(id: 'older', type: 'pea', row: 0, col: 0, layer: 10),
      Piece(
          id: 'later',
          type: 'sunflower',
          row: 0,
          col: 0,
          layer: 90,
          scale: 2,
          frameCol: 1),
    ]);
    await page().navigateFormation(source, name: '待格式化');
    await settled();
    page().selectToolboxTab(4);
    await h.settle();
    h.expect(
        page().outputEncodingError != null, 'Unsupported source not reported');
    await h
        .tapElement(h.find((w) => w.key == const ValueKey('formation-format')));
    await settled();
    h.expect(
        page().outputEncodingError == null &&
            page().outputFormation.text.isNotEmpty &&
            tabs.active.document.pieces.single.id == 'later',
        'Formatting did not produce compatible latest-wins output');
    await page().undoEditing();
    await settled();
    h.expect(
        tabs.active.document.fingerprint == source.fingerprint &&
            tabs.active.name == '待格式化',
        'Undo lost pre-format source');
    page().selectToolboxTab(1);
    await h.settle();
    h.expect(
        h
            .all((w) =>
                w is Text &&
                (w.data == '批量选择与操作' || (w.data ?? '').startsWith('批量放置')))
            .isEmpty,
        'Removed custom batch panel is still visible');
  });
  await h.run('batch.cancel',
      'Visible cancellation clears selected cells without editing', () async {
    page().selectToolboxTab(1);
    await selectCells([(0, 0)]);
    await h.settle();
    final fingerprint = tabs.active.document.fingerprint;
    h.expect(page().cells.isNotEmpty, 'Row and column selection did not select cells');
    final cancel =
        h.find((w) => w.key == const ValueKey('finish-batch-toolbar'));
    await h.tapElement(cancel);
    h.expect(
        page().cells.isEmpty &&
            page().batchSelectionMode == false &&
            tabs.active.document.fingerprint == fingerprint,
        'Visible cancel must clear markers and leave formation unchanged');
  });
  await h.run('batch.save-finish',
      'Successful save clears batch state without adding edit history',
      () async {
    await selectCells([(0, 0)]);
    await h.settle();
    final fingerprint = tabs.active.document.fingerprint;
    final depth = tabs.active.undoDepth;
    await page().saveArchive();
    await h.settle();
    h.expect(
        page().cells.isEmpty &&
            page().batchSelectionMode == false &&
            tabs.active.document.fingerprint == fingerprint &&
            tabs.active.undoDepth == depth,
        'Successful save retained batch state or changed edit history');
    await selectCells([(0, 1)]);
    await h.settle();
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('finish-batch-toolbar')));
    h.expect(page().cells.isEmpty && page().batchSelectionMode == false,
        'Toolbar finish left batch selection active');
  });
  await h.run('batch.delete-selection',
      'Visible delete removes all selected layers and overlapping cannon; one undo restores',
      () async {
    final original = Formation(pieces: [
      Piece(id: 'support', type: 'lily', row: 2, col: 1, layer: 0),
      Piece(id: 'plant', type: 'pea', row: 2, col: 1, layer: 10),
      Piece(id: 'shell', type: 'pumpkin', row: 2, col: 1, layer: 20),
      Piece(id: 'ladder', type: 'ladder', row: 2, col: 1, layer: 30),
      Piece(id: 'cannon', type: 'cob', row: 0, col: 0, layer: 10),
      Piece(id: 'outside', type: 'pea', row: 1, col: 3, layer: 10),
    ]);
    await tabs.open(EditorSession(repo,
        persistDraft: false, document: original, name: '批量删除测试'));
    await settled();
    page().selectToolboxTab(1);
    await selectCells([(2, 1), (0, 1)]);
    await h.settle();
    final depth = tabs.active.undoDepth;
    await h.tap('清空选中区域');
    h.expect(
        tabs.active.document.pieces.length == 1 &&
            tabs.active.document.pieces.single.id == 'outside',
        'Deletion missed selected layer/cannon or removed outside object');
    h.expect(tabs.active.undoDepth == depth + 1,
        'Batch deletion must create one history item');
    await page().undoEditing();
    h.expect(tabs.active.document.fingerprint == original.fingerprint,
        'Undo did not restore exact formation');
    await page().redoEditing();
    h.expect(tabs.active.document.pieces.single.id == 'outside',
        'Redo did not delete same selection');
    page().deleteSelection();
    h.expect(tabs.active.undoDepth == depth + 1,
        'Empty selected cells added history');
    await tabs.open(EditorSession(repo,
        persistDraft: false, document: original, readOnly: true));
    await settled();
    await selectCells([(0, 0)]);
    page().deleteSelection();
    h.expect(
        tabs.active.document.fingerprint == original.fingerprint &&
            tabs.active.undoDepth == 0,
        'Readonly selection was deleted');
  });
  await h.screenshot('garden-toolbox');
  await h.report();
  await File('/tmp/pvz-formation-navigation-report.json')
      .writeAsString(jsonEncode(h.cases));
  final pass = h.cases.every((c) => c['status'] == 'pass');
  tabs.dispose();
  await repo.close();
  exit(pass ? 0 : 1);
}
