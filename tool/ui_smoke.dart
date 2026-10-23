// Real pointer smoke for the current editor surface. Specialized suites cover
// cards, mirrors, presets/navigation, transfer, replacement and batch operations;
// see parity_ui, plant_state, formation_navigation, formation_io and live_output.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/seed_chooser.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

class ResponsiveBinding extends ParityBinding {
  Size viewport = const Size(1240, 800);
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(size: viewport, devicePixelRatio: 1);
}

Future<void> main() async {
  final binding = ResponsiveBinding();
  await OriginalAssets.ensureLoaded();
  final dir = await Directory.systemTemp.createTemp('pvz-current-ui-');
  final repo = await FormationRepository.open('${dir.path}/test.sqlite');
  final session = EditorSession(repo);
  final boundary = GlobalKey();
  final h = ParityHarness(
      boundary,
      await Directory('/tmp/pvz-full-editor/ui-screenshots')
          .create(recursive: true));
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

  await h.run('current-ui.drag-grouped-undo',
      'Actual plant card and board drag; toolbar Undo/Redo operate one drag atomically',
      () async {
    page.cancelPlanting();
    await h.settle();
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('original-card-pea')));
    final board = h
        .find((w) => w is CustomPaint && w.painter is BoardPainter)
        .renderObject as RenderBox;
    final geometry = BoardGeometry(session.document);
    final first = board.localToGlobal(geometry.cellCenter(0, 0));
    final second = board.localToGlobal(geometry.cellCenter(0, 1));
    GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: 71, position: first, buttons: 1));
    GestureBinding.instance.handlePointerEvent(PointerMoveEvent(
        pointer: 71, position: second, delta: second - first, buttons: 1));
    GestureBinding.instance
        .handlePointerEvent(PointerUpEvent(pointer: 71, position: second));
    await h.settle();
    h.expect(session.document.pieces.length == 2,
        'Dragging must place exactly two plants');
    final placed = session.document.fingerprint;
    await h.tap('撤销');
    h.expect(
        session.document.pieces.isEmpty, 'One Undo must remove entire drag');
    await h.tap('恢复');
    h.expect(session.document.fingerprint == placed,
        'One Redo must restore entire drag exactly');
  });

  await h.run('current-ui.saved-archive',
      'UI edits persist to their associated archive without deprecated draft records',
      () async {
    await session.flush();
    final archives = await repo.listArchives();
    final saved = archives.singleWhere((a) => a.id == session.sourceArchiveId);
    h.expect(
        (saved.document['objects'] as List).length == 2 &&
            (await repo.listDrafts()).isEmpty,
        'UI edit not saved to associated archive');
  });

  await h.run('current-ui.toolbox-scroll',
      'Toolbox clamps at both ends and retains each tab offset across rebuilds and picker switches',
      () async {
    page.selectToolboxTab(2);
    await h.settle();
    final controller = page.toolboxScrollControllers[2] as ScrollController;
    h.expect(controller.hasClients && controller.position.maxScrollExtent > 0,
        'Toolbox has no scrollable content');
    final viewport = h
        .find((w) => w.key == const PageStorageKey('toolbox-scroll-2'))
        .renderObject as RenderBox;
    final point = viewport.localToGlobal(
        Offset(viewport.size.width - 30, viewport.size.height / 2));
    var pointer = 720;
    for (final delta in [const Offset(0, -2000), const Offset(0, 2000)]) {
      GestureBinding.instance.handlePointerEvent(
          PointerDownEvent(pointer: ++pointer, position: point, buttons: 1));
      GestureBinding.instance.handlePointerEvent(PointerMoveEvent(
          pointer: pointer, position: point + delta, delta: delta, buttons: 1));
      GestureBinding.instance.handlePointerEvent(PointerMoveEvent(
          pointer: pointer,
          position: point + delta * 2,
          delta: delta,
          buttons: 1));
      h.expect(
          !controller.position.outOfRange, 'Toolbox rubber-banded during drag');
      GestureBinding.instance.handlePointerEvent(
          PointerUpEvent(pointer: pointer, position: point + delta * 2));
      await h.settle();
      h.expect(
          !controller.position.outOfRange, 'Toolbox bounced after release');
      final edge = delta.dy < 0
          ? controller.position.maxScrollExtent
          : controller.position.minScrollExtent;
      h.expect((controller.offset - edge).abs() < .1,
          'Drag did not reach intended toolbox edge: ${controller.offset} / $edge');
    }
    final offset = controller.position.maxScrollExtent / 2;
    controller.jumpTo(offset);
    page.cancelPlanting();
    await h.settle();
    h.expect((controller.offset - offset).abs() < .1,
        'Toolbox jumped on ordinary UI rebuild');
    page.selectToolboxTab(5);
    await h.settle();
    page.selectToolboxTab(2);
    await h.settle();
    h.expect((controller.offset - offset).abs() < .1,
        'Switching tabs lost toolbox scroll position');
    await page.chooseFormationPreset('阵型');
    await h.settle();
    final picker =
        h.find((w) => w.key == const ValueKey('formation-preset-picker'));
    h.expect(
        ScrollConfiguration.of(picker).getScrollPhysics(picker)
            is ClampingScrollPhysics,
        'Preset list retained elastic scrolling');
    page.selectToolboxTab(2);
    await h.settle();
    h.expect((controller.offset - offset).abs() < .1,
        'Opening picker and returning reset scroll position: ${controller.offset} expected $offset (max ${controller.position.maxScrollExtent})');
  });
  await h.run('current-ui.seed-return-and-geometry',
      'Top selected cards return, lower choices reset, mimic shifts and source panel geometry holds',
      () async {
    final original = session.document;
    session.execute(
        '选卡夹具', original.copy(seedSlots: [], imitaterSeedSlots: {}));
    final previousTab = page.classicTab;
    await h.tapElement(h.find((w) => w.key == const ValueKey('toolbox-tab-0')));
    h.expect(
        page.seedChooserOpen &&
            page.classicTab == previousTab &&
            h
                .all((w) => w.key == const ValueKey('original-seed-chooser'))
                .isEmpty,
        'Seed tab must directly open the board chooser without a separate toolbox page');
    await h.tapElement(h.find((w) => w.key == const ValueKey('toolbox-tab-0')));
    h.expect(!page.seedChooserOpen && page.classicTab == previousTab,
        'Seed tab must toggle closed without changing toolbox page');
    await h.tapElement(h.find((w) => w.key == const ValueKey('toolbox-tab-0')));
    await h.settle();
    final chooser = h.find((w) => w is OriginalSeedChooser);
    final host = chooser.findAncestorWidgetOfExactType<Positioned>()!;
    h.expect(host.left == 13 && host.top == 38,
        'Chooser host no longer matches source coordinate system');
    final background = h.find((w) =>
        w is RawImage &&
        w.image == OriginalAssets.image('image/SeedChooser_Background.png'));
    final panel = background.findAncestorWidgetOfExactType<Positioned>()!;
    h.expect(panel.top == 75 && panel.width == 465 && panel.height == 513,
        'Source main panel must be 465x513 at x13/y113');
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('seed-choice-normal-pea')));
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('seed-imitater-open')));
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('seed-choice-mimic-sunflower')));
    h.expect(
        session.document.seedSlots.join(',') == 'pea,sunflower' &&
            session.document.imitaterSeedSlots.single == 1,
        'Normal/mimic selection failed');
    await h.screenshot('seed-selected-before-return');
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('board-seed-return-0')));
    h.expect(
        session.document.seedSlots.single == 'sunflower' &&
            session.document.imitaterSeedSlots.single == 0,
        'Returning preceding card must shift mimic index');
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('seed-choice-normal-pea')));
    h.expect(session.document.seedSlots.join(',') == 'sunflower,pea',
        'Returned lower card did not become selectable');
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('board-seed-return-0')));
    h.expect(
        session.document.seedSlots.single == 'pea' &&
            session.document.imitaterSeedSlots.isEmpty,
        'Returning mimic must clear its selected index');
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('seed-imitater-open')));
    await h.settle();
    h.expect(
        h.all((w) => w.key == const ValueKey('seed-mimic-grid')).isNotEmpty,
        'Returning mimic did not re-enable side entry');
    await h.screenshot('seed-mimic-source-position');
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('seed-choice-mimic-pea')));
    final depth = session.undoDepth;
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('board-seed-return-1')));
    h.expect(
        session.undoDepth == depth + 1 &&
            session.document.imitaterSeedSlots.isEmpty,
        'Top return must be one undo command');
    session.undo();
    await h.settle();
    h.expect(session.document.imitaterSeedSlots.single == 1,
        'Undo must restore returned mimic at original slot');
    await page.toggleSeedChooser(false);
    session.execute('还原选卡夹具', original);
    await h.settle();
  });
  await h.run('current-ui.narrow-window',
      'Actual 390px viewport relayout retains document and opens/closes card preview without overflow',
      () async {
    final before = session.document.fingerprint;
    binding.viewport = const Size(390, 760);
    binding.handleMetricsChanged();
    await h.settle();
    await h.settle();
    h.expect(binding.renderViews.single.configuration.size.width == 390,
        'Narrow regression did not resize actual rendering viewport');
    page.selectToolboxTab(2);
    await h.settle();
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('original-card-sunflower')));
    h.expect(page.selectedType == 'sunflower' && page.tool == '放置',
        'Plant card inaccessible after narrow relayout');
    page.cancelPlanting();
    await h.settle();
    h.expect(page.tool == '选择' && session.document.fingerprint == before,
        'Cancel narrow-window card changed document');
  });
  await h.run('current-ui.history-shortcuts',
      'Curved history icons and platform key events for undo, restore and save',
      () async {
    h.expect(
        h.all((w) => w is Icon && w.icon == Icons.undo).isNotEmpty &&
            h.all((w) => w is Icon && w.icon == Icons.redo).isNotEmpty,
        'Missing curved arrows');
    h.expect(
        h
            .all((w) =>
                w is Tooltip && (w.message?.contains('恢复刚撤销的操作') ?? false))
            .isNotEmpty,
        'Restore explanation and shortcuts missing');
    var time = 0;
    Future<void> chord(PhysicalKeyboardKey physical, LogicalKeyboardKey logical,
        {bool meta = false, bool shift = false}) async {
      final dispatch = binding.platformDispatcher.onKeyData!;
      void key(
          PhysicalKeyboardKey p, LogicalKeyboardKey l, ui.KeyEventType type) {
        dispatch(ui.KeyData(
            timeStamp: Duration(milliseconds: ++time),
            type: type,
            physical: p.usbHidUsage,
            logical: l.keyId,
            character: null,
            synthesized: true));
      }

      final modifier =
          meta ? PhysicalKeyboardKey.metaLeft : PhysicalKeyboardKey.controlLeft;
      final modifierLogical =
          meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
      key(modifier, modifierLogical, ui.KeyEventType.down);
      if (shift) {
        key(PhysicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftLeft,
            ui.KeyEventType.down);
      }
      key(physical, logical, ui.KeyEventType.down);
      key(physical, logical, ui.KeyEventType.up);
      if (shift) {
        key(PhysicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftLeft,
            ui.KeyEventType.up);
      }
      key(modifier, modifierLogical, ui.KeyEventType.up);
      await h.settle();
    }

    page.canvasFocus.requestFocus();
    await h.settle();
    final before = session.document;
    session.execute('快捷键验证', before.copy(sunValue: 123));
    await h.settle();
    for (final meta in [false, true]) {
      await chord(PhysicalKeyboardKey.keyZ, LogicalKeyboardKey.keyZ,
          meta: meta);
      h.expect(
          session.document.fingerprint == before.fingerprint, 'Undo failed');
      await chord(PhysicalKeyboardKey.keyY, LogicalKeyboardKey.keyY,
          meta: meta);
      h.expect(session.document.sunValue == 123, 'Restore failed');
      await chord(PhysicalKeyboardKey.keyS, LogicalKeyboardKey.keyS,
          meta: meta);
      h.expect(session.matchesArchive, 'Save failed');
    }
    await chord(PhysicalKeyboardKey.keyZ, LogicalKeyboardKey.keyZ, meta: true);
    await chord(PhysicalKeyboardKey.keyZ, LogicalKeyboardKey.keyZ,
        meta: true, shift: true);
    h.expect(session.document.sunValue == 123,
        'Shift+Command+Z compatibility failed');
  });

  await h.report();
  await File('/tmp/pvz-full-editor/ui-current-report.json')
      .writeAsString(jsonEncode({
    'cases': h.cases,
    'flutterErrors': h.errors.map((e) => e.exceptionAsString()).toList(),
    'scope':
        'real headless pointer UI; no native window automation; temporary SQLite'
  }));
  final passed =
      h.cases.every((c) => c['status'] == 'pass') && h.errors.isEmpty;
  runApp(const SizedBox.shrink());
  await h.settle();
  session.dispose();
  await repo.close();
  await dir.delete(recursive: true);
  exit(passed ? 0 : 1);
}
