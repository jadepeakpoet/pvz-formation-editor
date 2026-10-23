import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
  final key = GlobalKey();
  final h = ParityHarness(
      key, await Directory('/tmp/pvz-plant-state').create(recursive: true));
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
  void click({bool move = false}) {
    final p = BoardGeometry(session.document).cellCenter(0, 0);
    page.beginGesture(p);
    if (move) page.touch(p);
    page.finishGesture();
  }

  await h.run('preview.before-first-plant',
      'Native inactive-window movement and pointer entry preview an empty board',
      () async {
    final before = session.document.fingerprint;
    final board = h.find((w) => w is CustomPaint && w.painter is BoardPainter);
    final box = board.renderObject as RenderBox;
    final target = BoardGeometry(session.document).cellCenter(1, 2);
    final global = box.localToGlobal(target);
    page.updateNativePlantingPointer({'x': global.dx, 'y': global.dy});
    await h.settle();
    BoardPainter painter() =>
        (h.find((w) => w is CustomPaint && w.painter is BoardPainter).widget
                as CustomPaint)
            .painter as BoardPainter;
    h.expect(
        painter().plantingPreview?.type == 'pea' &&
            (painter().plantingPosition! - target).distance < .01 &&
            session.document.pieces.isEmpty,
        'Preview required a first planting');
    page.updateNativePlantingPointer(null);
    await h.settle();
    h.expect(painter().plantingPreview == null, 'Native exit did not clear');
    final region = h
        .find((w) =>
            w is MouseRegion &&
            w.onHover != null &&
            w.onEnter != null &&
            w.child is Listener)
        .widget as MouseRegion;
    region.onEnter!(PointerEnterEvent(position: target));
    await h.settle();
    h.expect(
        painter().plantingPreview != null &&
            session.document.fingerprint == before,
        'Entry preview edited document or required movement/click');
    region.onExit!(const PointerExitEvent());
    await h.settle();
  });
  final original = Piece(
      id: 'plant',
      type: 'wallnut',
      row: 0,
      col: 0,
      layer: ObjectSpec.byId('wallnut').layer,
      flipped: true,
      effects: {'高亮'});
  await h.run('cycle',
      'Same species cycles all frames and wraps; retains identity and properties',
      () async {
    session.execute('fixture', Formation(pieces: [original]));
    page.selectedType = 'wallnut';
    page.tool = '放置';
    final data = OriginalAssets.sprites['Wallnut'];
    final layers = (data['images'] as List)
        .where((p) => !(p['path'] as String).contains('shadow'))
        .toList();
    final rows = (layers.last['rows'] as num).toInt();
    final cols = (layers.last['cols'] as num).toInt();
    h.expect(rows * cols > 1, 'Fixture must have multiple states');
    for (var i = 1; i <= rows * cols; i++) {
      click(move: true);
      final p = session.document.pieces.single;
      h.expect(p.id == original.id && p.flipped && p.effects.contains('高亮'),
          'Properties lost');
      h.expect(
          p.frameRow == (i % (rows * cols)) ~/ cols && p.frameCol == i % cols,
          'State order/wrap or move deduplication failed');
    }
    session.undo();
    h.expect(
        session.document.pieces.single.frameRow == rows - 1 &&
            session.document.pieces.single.frameCol == cols - 1,
        'Undo failed');
    session.redo();
    h.expect(
        session.document.pieces.single.frameRow == 0 &&
            session.document.pieces.single.frameCol == 0,
        'Redo failed');
  });
  await h.run('unselected',
      'Selection tool cycles a plant without an active planting card',
      () async {
    page.tool = '选择';
    click();
    final p = session.document.pieces.single;
    h.expect(p.id == 'plant' && (p.frameRow != 0 || p.frameCol != 0),
        'No state change');
  });
  await h.run('reset',
      'Right click restores first state and undo preserves the previous state',
      () async {
    final previous = session.document.pieces.single;
    final pointer = BoardGeometry(session.document).cellCenter(0, 0);
    final boardListener = h
        .find((w) =>
            w is Listener && w.child is SizedBox && w.onPointerDown != null)
        .widget as Listener;
    boardListener
        .onPointerDown!(PointerDownEvent(buttons: 2, position: pointer));
    final reset = session.document.pieces.single;
    h.expect(
        reset.id == previous.id &&
            reset.frameRow == 0 &&
            reset.frameCol == 0 &&
            reset.flipped == previous.flipped &&
            reset.effects.contains('高亮'),
        'Right click did not preserve properties/reset state');
    session.undo();
    h.expect(
        session.document.pieces.single.frameRow == previous.frameRow &&
            session.document.pieces.single.frameCol == previous.frameCol,
        'Reset undo failed');
    page.resetPlantState(BoardGeometry(session.document).cellCenter(5, 8));
    h.expect(session.document.pieces.single.id == previous.id,
        'Empty-cell reset changed plants');
  });
  await h.run('imitater-only',
      'Standalone imitater changes existing plant; empty cells do nothing',
      () async {
    page.cancelPlanting();
    page.plantingEffects.clear();
    await h.settle();
    final effect = h
        .find((w) => w.key == const ValueKey('original-effect-模仿者'))
        .widget as Tooltip;
    (effect.child as InkWell).onTap!();
    h.expect(page.tool == '模仿', 'Effect did not select standalone imitater');
    final before = session.document.fingerprint;
    final empty = BoardGeometry(session.document).cellCenter(5, 8);
    page.beginGesture(empty);
    page.finishGesture();
    h.expect(
        session.document.fingerprint == before, 'Empty cell created a plant');
    final plant = session.document.pieces.single;
    click(move: true);
    final mimic = session.document.pieces.single;
    h.expect(
        mimic.id == plant.id &&
            mimic.type == plant.type &&
            mimic.row == plant.row &&
            mimic.col == plant.col &&
            mimic.frameRow == plant.frameRow &&
            mimic.frameCol == plant.frameCol &&
            mimic.flipped == plant.flipped &&
            mimic.effects.contains('模仿者') &&
            mimic.effects.contains('高亮'),
        'Imitation replaced plant or changed state/properties');
    session.undo();
    h.expect(session.document.fingerprint == before, 'Imitation undo failed');
    page.cancelPlanting();
    h.expect(page.tool == '选择' && !page.plantingEffects.contains('模仿者'),
        'Cancel did not clear standalone imitation');
  });
  await h.run('different', 'Different species retains replacement behavior',
      () async {
    page.tool = '放置';
    page.selectedType = 'pea';
    click();
    h.expect(
        session.document.pieces.single.type == 'pea' &&
            session.document.pieces.single.id != 'plant',
        'Replacement failed');
  });
  await h.run('preview',
      'Hover follows pointer without editing; exit and tools hide preview',
      () async {
    page.tool = '放置';
    final before = session.document.fingerprint;
    MouseRegion region() => h
        .find((w) =>
            w is MouseRegion &&
            w.child is Listener &&
            w.onHover != null &&
            w.onExit != null)
        .widget as MouseRegion;
    BoardPainter painter() =>
        (h.find((w) => w is CustomPaint && w.painter is BoardPainter).widget
                as CustomPaint)
            .painter as BoardPainter;
    final pointer = BoardGeometry(session.document).cellCenter(1, 2);
    region().onHover!(PointerHoverEvent(position: pointer));
    await h.settle();
    h.expect(
        painter().plantingPreview?.type == 'pea' &&
            painter().plantingPosition == pointer,
        'Preview does not follow selected plant/pointer');
    h.expect(session.document.fingerprint == before, 'Hover edited document');
    await h.screenshot('planting-preview');
    region().onExit!(const PointerExitEvent());
    await h.settle();
    h.expect(painter().plantingPreview == null, 'Preview remains after exit');
    page.tool = '放置';
    region().onHover!(PointerHoverEvent(position: pointer));
    await h.settle();
    final root =
        h.find((w) => w is Listener && w.child is PopScope).widget as Listener;
    root.onPointerDown!(const PointerDownEvent(buttons: 2));
    await h.settle();
    h.expect(
        page.tool == '选择' &&
            painter().plantingPreview == null &&
            session.document.fingerprint == before,
        'Right click did not cancel safely');
    page.tool = '铲除';
    region().onHover!(PointerHoverEvent(position: pointer));
    await h.settle();
    h.expect(painter().plantingPreview == null, 'Shovel shows plant preview');
  });
  await h.run('roof.sprite-state-hit',
      'Roof sprite clicks outside the grid cycle the actual plant with hover feedback and undo', () async {
    for (final mapId in ['roof', 'moonRoof', 'roof6', 'moonRoof6']) {
      final plant = Piece(id: 'roof-nut', type: 'wallnut', row: 0, col: 0,
          layer: ObjectSpec.byId('wallnut').layer);
      session.execute('roof fixture', Formation(mapId: mapId, pieces: [
        plant, Piece(id: 'roof-pot', type: 'pot', row: 0, col: 0,
            layer: ObjectSpec.byId('pot').layer),
      ], display: {'卡槽': false, '阳光': false}));
      page.tool = '选择';
      page.batchSelectionMode = false;
      page.update();
      await OriginalAssets.ensureHitMasks(['wallnut', 'pot']);
      await h.settle();
      final geometry = BoardGeometry(session.document);
      final bounds = geometry.pieceBounds(plant);
      Offset? target;
      for (var y = bounds.top; y < bounds.bottom && target == null; y += 2) {
        for (var x = bounds.left; x < bounds.right; x += 2) {
          final point = Offset(x, y);
          if (geometry.hit(point) == null && geometry.spriteContains(plant, point)) {
            target = point;
            break;
          }
        }
      }
      h.expect(target != null, '$mapId fixture needs visible pixels outside ground grid');
      final before = session.document.fingerprint;
      page.updatePlantingPointer(target);
      await h.settle();
      BoardPainter painter() => (h.find((w) => w is CustomPaint && w.painter is BoardPainter).widget as CustomPaint).painter as BoardPainter;
      h.expect(painter().stateHoverId == plant.id &&
          session.document.fingerprint == before, 'Roof hover must fade the plant without writing');
      final region = h.find((w) => w is MouseRegion && w.child is Listener && w.onHover != null).widget as MouseRegion;
      h.expect(region.cursor == SystemMouseCursors.click, 'State hover must show click cursor');
      final box = h.find((w) => w is CustomPaint && w.painter is BoardPainter).renderObject as RenderBox;
      final depth = session.undoDepth;
      await h.tapAt(box.localToGlobal(target!));
      final changed = session.document.pieces.firstWhere((p) => p.id == plant.id);
      h.expect(changed.frameCol != 0 || changed.frameRow != 0,
          '$mapId sprite click outside grid did not change plant state');
      h.expect(session.undoDepth == depth + 1 && session.document.pieces.length == 2,
          'State click must preserve plant and pot in one undo step');
      final after = session.document.fingerprint;
      session.undo();
      h.expect(session.document.fingerprint == before, 'Roof state undo must restore exactly');
      session.redo();
      h.expect(session.document.fingerprint == after, 'Roof state redo must restore exactly');
      page.updatePlantingPointer(null);
      await h.settle();
      h.expect(painter().stateHoverId == null,
          'Leaving plant must clear state feedback');
    }
  });
  await h.run('cactus.short-state-hit',
      'Tall cactus uses its short silhouette so the plant behind it remains clickable', () async {
    await OriginalAssets.ensureHitMasks(['cactus', 'wallnut']);
    for (final mapId in ['day', 'roof']) {
      final cactus = Piece(id: 'tall-cactus', type: 'cactus', row: 1, col: 0,
          layer: 10, frameRow: 2);
      final nut = Piece(id: 'behind-nut', type: 'wallnut', row: 0, col: 0, layer: 10);
      session.execute('cactus fixture', Formation(mapId: mapId, pieces: [nut, cactus],
          display: {'卡槽': false, '阳光': false}));
      page.tool = '选择';
      page.update();
      await h.settle();
      final geometry = BoardGeometry(session.document);
      final short = cactus.copy(frameRow: 0, frameCol: 0);
      final bounds = geometry.pieceBounds(cactus);
      Offset? target;
      for (var y = bounds.top; y < bounds.bottom && target == null; y += 2) {
        for (var x = bounds.left; x < bounds.right; x += 2) {
          final point = Offset(x, y);
          if (geometry.spriteContains(cactus, point) &&
              !geometry.spriteContains(short, point) && geometry.spriteContains(nut, point)) {
            target = point;
            break;
          }
        }
      }
      h.expect(target != null, 'Need overlapping tall cactus and rear nut pixels');
      final List<Piece> targets = page.piecesAtPointer(target!);
      h.expect(targets.first.id == nut.id && !targets.any((p) => p.id == cactus.id),
          'Tall cactus must not capture clicks outside short silhouette');
      page.updatePlantingPointer(target);
      await h.settle();
      final painter = (h.find((w) => w is CustomPaint && w.painter is BoardPainter).widget as CustomPaint).painter as BoardPainter;
      h.expect(painter.stateHoverId == nut.id &&
          session.document.pieces.every((p) => p.opacity == 1),
          'Hover must fade only actual target without persisting opacity');
      final box = h.find((w) => w is CustomPaint && w.painter is BoardPainter).renderObject as RenderBox;
      await h.tapAt(box.localToGlobal(target));
      h.expect(session.document.pieces.firstWhere((p) => p.id == nut.id).frameCol != 0 &&
          session.document.pieces.firstWhere((p) => p.id == cactus.id).frameRow == 2,
          'Pointer must cycle rear plant while retaining tall cactus state');
    }
  });
  await h.run('mushroom.awake-default',
      'Fume and gloom default awake in preview, single and batch planting while explicit frames remain selectable', () async {
    for (final type in ['fume', 'gloom']) {
      session.execute('empty fixture', Formation(mapId: 'day'));
      page.selectedType = type;
      page.tool = '放置';
      page.growMode = 1;
      page.plantingFrameRow = 0;
      page.plantingFrameCol = 0;
      final Piece preview = page.plantingPiece(0, 0, preview: true);
      h.expect(preview.frameRow == 1 && preview.frameCol == 0,
          '$type preview must default awake');
      click();
      h.expect(session.document.pieces.single.frameRow == 1,
          '$type single planting must default awake');
      page.updateBatchSelection({1}, {1, 2});
      page.batchPlace();
      h.expect(session.document.pieces.length == 3 &&
          session.document.pieces.every((p) => p.frameRow == 1),
          '$type batch planting must default awake');
      page.growMode = 0;
      final Piece manual = page.plantingPiece(0, 0);
      h.expect(manual.frameRow == 0, 'Manual sleeping state must remain available');
      page.growMode = 3;
      final Piece explicit = page.plantingPiece(0, 0);
      h.expect(explicit.frameRow == 0, 'Explicit first-row state must remain available');
    }
    page.growMode = 1;
    page.selectedType = 'wallnut';
    final Piece other = page.plantingPiece(0, 0);
    h.expect(other.frameRow == 0, 'Other plant defaults must be unchanged');
  });
  await h.report();
  session.dispose();
  await repo.close();
  exit(h.cases.every((c) => c['status'] == 'pass') ? 0 : 1);
}
