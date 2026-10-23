// Real source-style catalog input: row/column intersection and immediate card use.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final session = EditorSession(repo, persistDraft: false);
  final boundary = GlobalKey();
  final h = ParityHarness(boundary,
      await Directory('/tmp/pvz-web-catalog').create(recursive: true));
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          home: app.EditorPage(
              session: session, continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  final dynamic page =
      (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  h.expect(
      h
          .all((w) =>
              w is ButtonStyleButton &&
              w.child is Text &&
              (w.child as Text).data == '默认外表')
          .isEmpty,
      'Catalog must not expose a standalone default-appearance button');

  await page.toggleSeedChooser(false);
  page.selectToolboxTab(2);
  await h.settle();
  Future<void> tapKey(String key) =>
      h.tapElement(h.find((w) => w.key == ValueKey(key)));
  Future<void> closePickerWith(String key) async {
    await tapKey(key);
    for (var attempt = 0; attempt < 20; attempt++) {
      if (h.all((w) => w.key == const ValueKey('batch-clear-picker')).isEmpty) {
        return;
      }
      await h.settle();
    }
    throw StateError('Type picker did not close after selection/cancel');
  }

  Checkbox checkbox(String key) =>
      h.find((w) => w.key == ValueKey(key)).widget as Checkbox;
  Radio<bool> radio(String key) =>
      h.find((w) => w.key == ValueKey(key)).widget as Radio<bool>;
  void checkCells(Set<(int, int)> expected, String reason) {
    final actual = Set<(int, int)>.from(page.cells as Set);
    h.expect(actual.length == expected.length && actual.containsAll(expected),
        reason);
  }

  h.expect(
      radio('original-rHowGrow0').groupValue == false &&
          h.all((w) => w.key == const ValueKey('batch-row-0')).isEmpty,
      'Single selection radio must be default and hide batch axes');
  h.expect(h.all((w) => w is Text && w.data == '种植').isEmpty,
      'Catalog must not expose an extra planting button');
  final appearanceField = h
      .find((w) => w.key == const ValueKey('original-sGrowSelect'))
      .renderObject as RenderBox;
  h.expect(appearanceField.size.width <= 144,
      'Default appearance field should stay compact');
  await tapKey('original-rHowGrow1');
  h.expect(
      radio('original-rHowGrow1').groupValue == true &&
          h
              .all((w) => w.key == const ValueKey('web-batch-controls'))
              .isNotEmpty,
      'Batch radio must reveal the source controls');
  await tapKey('batch-row-1');
  checkCells({}, 'Rows without columns must select no cells');
  await tapKey('batch-col-0');
  await tapKey('batch-col-2');
  await h.screenshot('axis-intersection');
  checkCells(
      {(1, 0), (1, 2)}, 'Selected cells must be the row/column intersection');
  final beforeCard = session.undoDepth;
  await tapKey('original-card-pea');
  h.expect(
      session.document.pieces.length == 2 &&
          session.document.pieces.every((p) =>
              p.type == 'pea' && p.row == 1 && (p.col == 0 || p.col == 2)) &&
          session.undoDepth == beforeCard + 1,
      'Clicking a card must plant the intersection in one undo step');
  await h.tap('(点击隐藏行列)');
  h.expect(
      page.batchSelectionMode == true &&
          h.all((w) => w.key == const ValueKey('batch-row-0')).isEmpty,
      'Hiding row/column controls must retain batch mode');
  checkCells({(1, 0), (1, 2)}, 'Hiding axes must retain their selection');
  final beforeCanvas = session.document.fingerprint;
  final board = h
      .find((w) => w is CustomPaint && w.painter is BoardPainter)
      .renderObject as RenderBox;
  await h.tapAt(
      board.localToGlobal(BoardGeometry(session.document).cellCenter(0, 4)));
  checkCells(
      {(1, 0), (1, 2)}, 'Ordinary canvas click must not toggle batch cells');
  h.expect(session.document.fingerprint == beforeCanvas,
      'Batch mode canvas click must not plant independently');
  await h.tap('陆路');
  checkCells({
    for (final row in [0, 1, 4, 5])
      for (var col = 0; col < 9; col++) (row, col)
  }, 'Land shortcut must select all land rows and columns');
  await h.tap('水路');
  checkCells({
    for (final row in [2, 3])
      for (var col = 0; col < 9; col++) (row, col)
  }, 'Water shortcut must select pool rows and columns');
  await h.tap('重置批量选择');
  checkCells({}, 'Reset must clear the row/column intersection');
  h.expect(
      (page.batchRows as Set).isEmpty && (page.batchColumns as Set).isEmpty,
      'Reset must clear both axes');
  session.execute(
      'typed clear fixture',
      Formation(pieces: [
        Piece(id: 'support', type: 'lily', row: 2, col: 0, layer: 0),
        Piece(id: 'plant', type: 'pea', row: 2, col: 0, layer: 10),
        Piece(id: 'shell', type: 'pumpkin', row: 2, col: 0, layer: 20),
        Piece(id: 'other', type: 'pea', row: 1, col: 1, layer: 10),
      ]));
  await h.settle();
  await tapKey('batch-row-2');
  await tapKey('batch-col-0');
  final beforeDelete = session.document.fingerprint;
  final depthBeforePicker = session.undoDepth;
  h.expect(
      h.all((w) => w is Text && w.data == '一键预选').length == 1 &&
          h.all((w) => w is Text && w.data == '铲除').length == 1,
      'Quick selection and clear controls need their own headings');
  await h.tap('清除指定植物');
  h.expect(
      h.all((w) => w.key == const ValueKey('batch-clear-picker')).isNotEmpty &&
          session.document.fingerprint == beforeDelete,
      'Type picker must open without clearing anything');
  await closePickerWith('batch-clear-cancel');
  h.expect(
      session.document.fingerprint == beforeDelete &&
          session.undoDepth == depthBeforePicker,
      'Cancel must not change formation');
  await h.tap('清除指定植物');
  await closePickerWith('batch-clear-kind-普通植物');
  h.expect(h.all((w) => w.key == const ValueKey('batch-clear-picker')).isEmpty,
      'Picking a type must close and clear without another confirmation');
  h.expect(
      session.document.pieces
              .map((p) => p.id)
              .toSet()
              .containsAll(['support', 'shell', 'other']) &&
          !session.document.pieces.any((p) => p.id == 'plant'),
      'Typed clear must remove only matching selected objects');
  session.undo();
  await h.settle();
  h.expect(session.document.fingerprint == beforeDelete,
      'Typed clear undo must restore the exact formation');
  await h.tap('清除指定植物');
  page.updateBatchSelection({1}, {1});
  await h.settle();
  await closePickerWith('batch-clear-kind-普通植物');
  h.expect(session.document.fingerprint == beforeDelete,
      'Changed selection must reject an obsolete type picker');
  page.updateBatchSelection({2}, {0});
  await h.settle();
  await h.tap('清除指定植物');
  session.execute('external update during clear picker',
      session.document.copy(sunValue: session.document.sunValue + 1));
  await h.settle();
  final external = session.document.fingerprint,
      externalDepth = session.undoDepth;
  await closePickerWith('batch-clear-kind-普通植物');
  h.expect(
      session.document.fingerprint == external &&
          session.undoDepth == externalDepth,
      'Changed board must reject an obsolete type picker');
  session.undo();
  await h.settle();
  await h.tap('清空选中区域');
  h.expect(session.document.pieces.single.id == 'other',
      'All clear must preserve objects outside the selected intersection');
  session.undo();
  await h.settle();
  await h.tap('清空地图');
  h.expect(
      session.document.pieces.isEmpty, 'Clear map must remove every object');
  session.undo();
  await h.settle();
  h.expect(session.document.fingerprint == beforeDelete,
      'Clear map must be undoable');
  session.readOnly = true;
  page.update();
  await h.settle();
  for (final key in [
    'batch-clear-type',
    'batch-clear-selection',
    'batch-clear-map'
  ]) {
    h.expect(
        (h.find((w) => w.key == ValueKey(key)).widget as ButtonStyleButton)
                .onPressed ==
            null,
        'Readonly clear control must be disabled');
  }
  session.readOnly = false;
  page.update();
  await h.settle();
  await tapKey('original-rHowGrow0');
  h.expect(
      page.batchSelectionMode == false &&
          h.all((w) => w.key == const ValueKey('batch-row-0')).isEmpty &&
          h.all((w) => w.key == const ValueKey('web-batch-controls')).isEmpty,
      'Single radio must close batch mode controls');
  await tapKey('original-flip-horizontal');
  h.expect(
      checkbox('original-flip-horizontal').value == true &&
          checkbox('original-flip-vertical').value == false,
      'Horizontal flip must have its own checkbox state');
  await tapKey('original-flip-vertical');
  await tapKey('original-flip-horizontal');
  h.expect(
      checkbox('original-flip-horizontal').value == false &&
          checkbox('original-flip-vertical').value == true,
      'Flip checkboxes must remain independent');
  await h.screenshot('web-catalog-controls');
  h.expect(h.errors.isEmpty,
      h.errors.map((error) => error.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS source radios, axis intersection, direct batch planting, canvas exclusion, shortcuts/reset, typed/all clear with undo and independent flip checkboxes');
  runApp(const SizedBox.shrink());
  await h.settle();
  session.dispose();
  await repo.close();
  exit(0);
}
