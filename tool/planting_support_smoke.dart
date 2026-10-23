import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:pvz_formation_editor/editor/shovel_targets.dart';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/planting_support.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/planting_preferences.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  await OriginalAssets.ensureLoaded();
  await OriginalAssets.ensureHitMasks(OriginalAssets.names.keys);
  final repo = await FormationRepository.open(':memory:');
  final s = EditorSession(repo, persistDraft: false);
  final key = GlobalKey();
  final h = ParityHarness(key,
      await Directory('/tmp/pvz-planting-support').create(recursive: true));
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: key,
      child: MaterialApp(
          home: app.EditorPage(session: s, continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  final dynamic page =
      (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  void plant(int row, int col) {
    page.tool = '放置';
    page.beginGesture(BoardGeometry(s.document).cellCenter(row, col));
    page.finishGesture();
  }

  bool has(String type, int row, int col) => s.document.pieces
      .any((p) => p.type == type && p.row == row && p.col == col);
  await h.run('support.hover-preview',
      'Hover shows missing supports at cell anchors, follows planting settings and never edits the document',
      () async {
    Future<BoardPainter> preview(
        Formation document, String type, int row, int col,
        {bool lily = true, String pot = 'roof'}) async {
      s.execute('预览夹具', document);
      page.tool = '放置';
      page.selectedType = type;
      page.autoLily = lily;
      page.autoPotMode = pot;
      page.updatePlantingPointer(null);
      await h.settle();
      final before = s.document.fingerprint, depth = s.undoDepth;
      page.updatePlantingPointer(
          BoardGeometry(document).cellCenter(row, col) + const Offset(9, 3));
      await h.settle();
      h.expect(s.document.fingerprint == before && s.undoDepth == depth,
          'Hover persisted a support or changed undo history');
      return (h
              .find((w) => w is CustomPaint && w.painter is BoardPainter)
              .widget as CustomPaint)
          .painter as BoardPainter;
    }

    final water = Formation(mapId: 'pool');
    var painter = await preview(water, 'pea', 2, 1);
    h.expect(
        painter.plantingSupportPreviews.single.type == 'lily' &&
            painter.plantingSupportPreviews.single.row == 2 &&
            painter.plantingSupportPreviews.single.col == 1,
        'Missing water lily preview');
    await h.screenshot('support-water-preview');
    Future<Uint8List> pixels(BoardPainter value) async {
      final recorder = ui.PictureRecorder();
      value.paint(Canvas(recorder), const Size(800, 600));
      final picture = recorder.endRecording();
      final image = await picture.toImage(800, 600);
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final copy = Uint8List.fromList(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      image.dispose();
      picture.dispose();
      return copy;
    }

    final actual = await pixels(painter);
    final without = await pixels(BoardPainter(
        document: water,
        plantingPreview: painter.plantingPreview,
        plantingPosition: painter.plantingPosition));
    final base = BoardGeometry(water)
        .pieceBounds(painter.plantingSupportPreviews.single);
    var changed = 0;
    for (var y = base.top.floor().clamp(0, 599);
        y < base.bottom.ceil().clamp(0, 600);
        y++) {
      for (var x = base.left.floor().clamp(0, 799);
          x < base.right.ceil().clamp(0, 800);
          x++) {
        final at = (y * 800 + x) * 4;
        if (actual[at] != without[at] ||
            actual[at + 1] != without[at + 1] ||
            actual[at + 2] != without[at + 2]) changed++;
      }
    }
    h.expect(
        changed > 100, 'Lily preview was not actually painted in its cell');
    h.expect(
        (await pixels(BoardPainter(
                    document: water,
                    helpers: false,
                    plantingPreview: painter.plantingPreview,
                    plantingPosition: painter.plantingPosition,
                    plantingSupportPreviews: painter.plantingSupportPreviews)))
                .toString() ==
            (await pixels(BoardPainter(document: water, helpers: false)))
                .toString(),
        'Export included transient support previews');
    painter = await preview(Formation(mapId: 'roof'), 'pea', 1, 2);
    h.expect(
        painter.plantingSupportPreviews.single.type == 'pot' &&
            painter.plantingSupportPreviews.single.frameRow == 1,
        'Missing plain roof pot preview');
    await h.screenshot('support-roof-preview');
    painter = await preview(Formation(mapId: 'roof'), 'cob', 1, 2);
    h.expect(
        painter.plantingSupportPreviews.map((p) => p.col).join(',') == '2,3',
        'Two-cell plant must preview each missing pot');
    painter = await preview(Formation(mapId: 'day'), 'pea', 1, 2, pot: 'land');
    h.expect(painter.plantingSupportPreviews.single.type == 'pot',
        'Land pot setting ignored');
    for (final type in [
      'pea',
      'cattail',
      'tangle',
      'seashroom',
      'coffee',
      'lily'
    ]) {
      painter = await preview(water, type, 2, 1, lily: type != 'pea');
      h.expect(
          painter.plantingSupportPreviews.isEmpty, 'Unexpected base for $type');
    }
    painter = await preview(Formation(mapId: 'roof'), 'pea', 1, 2, pot: 'off');
    h.expect(painter.plantingSupportPreviews.isEmpty, 'Disabled pot previewed');
    painter = await preview(
        water.copy(pieces: [
          Piece(id: 'base', type: 'lily', row: 2, col: 1, layer: 0)
        ]),
        'pea',
        2,
        1);
    h.expect(
        painter.plantingSupportPreviews.isEmpty, 'Existing base duplicated');
    page.cancelPlanting();
    page.autoLily = true;
    page.autoPotMode = 'roof';
    s.execute('清理预览夹具', Formation());
    await h.settle();
  });
  await h.run('coffee.independent-slot',
      'Coffee overlays plant, shell and base, remains one slot and undoes atomically',
      () async {
    final fixture = Formation(mapId: 'roof', pieces: [
      Piece(id: 'base', type: 'pot', row: 1, col: 2, layer: 0),
      Piece(id: 'main', type: 'fume', row: 1, col: 2, layer: 10),
      Piece(id: 'shell', type: 'pumpkin', row: 1, col: 2, layer: 20),
      Piece(id: 'ladder', type: 'ladder', row: 1, col: 2, layer: 25),
    ]);
    s.execute('coffee fixture', fixture);
    page.selectedType = 'coffee';
    plant(1, 2);
    h.expect(
        s.document.pieces.length == 5 &&
            fixture.pieces
                .every((p) => s.document.pieces.any((q) => q.id == p.id)) &&
            s.document.pieces.singleWhere((p) => p.type == 'coffee').layer ==
                30,
        'Coffee replaced underlying plant/shell/base or has wrong draw layer');
    s.undo();
    h.expect(
        s.document.fingerprint == fixture.fingerprint, 'Coffee undo failed');
    s.redo();
    final pieces = List<Piece>.of(s.document.pieces);
    page.replacePlanting(pieces,
        Piece(id: 'new-coffee', type: 'coffee', row: 1, col: 2, layer: 30));
    h.expect(
        pieces.length == 5 &&
            pieces.where((p) => p.type == 'coffee').single.id == 'new-coffee',
        'Coffee did not replace only its own slot');
    page.replacePlanting(
        pieces, Piece(id: 'upgrade', type: 'gloom', row: 1, col: 2, layer: 10));
    h.expect(
        pieces.any((p) => p.type == 'coffee') &&
            pieces.any((p) => p.type == 'pumpkin') &&
            pieces.any((p) => p.type == 'pot'),
        'Main-plant upgrade removed independent slots');
    s.execute(
        'aquatic fixture',
        Formation(pieces: [
          Piece(id: 'cat', type: 'cattail', row: 2, col: 2, layer: 10)
        ]));
    page.selectedType = 'pumpkin';
    plant(2, 2);
    page.selectedType = 'coffee';
    plant(2, 2);
    h.expect(
        has('cattail', 2, 2) &&
            has('pumpkin', 2, 2) &&
            has('coffee', 2, 2) &&
            !has('lily', 2, 2),
        'Attachments added incompatible lily under cattail');
  });
  await h.run('replacement.normal-imitater',
      'Normal and Imitater placements replace each other; matching forms still cycle states',
      () async {
    for (final type in ['pea', 'pumpkin', 'cob', 'lily', 'pot', 'coffee']) {
      for (final wasMimic in [false, true]) {
        final target = Piece(
            id: 'form-target',
            type: type,
            row: 2,
            col: 2,
            layer: ObjectSpec.byId(type).layer,
            effects: wasMimic ? {'模仿者'} : {});
        s.execute('form fixture', Formation(pieces: [target]));
        final before = s.document.fingerprint;
        final depth = s.undoDepth;
        page.selectedType = type;
        page.plantingEffects.clear();
        if (!wasMimic) page.plantingEffects.add('模仿者');
        plant(2, 2);
        final placed = s.document.pieces.where((p) => p.type == type).single;
        h.expect(
            placed.effects.contains('模仿者') == !wasMimic &&
                placed.id != target.id,
            '$type did not replace opposite form');
        h.expect(s.undoDepth == depth + 1, 'Replacement must be one undo step');
        s.undo();
        h.expect(
            s.document.fingerprint == before, 'Form replacement undo failed');
        s.redo();
        plant(2, 2);
        h.expect(
            s.document.pieces.where((p) => p.type == type).single.id ==
                placed.id,
            '$type matching form no longer cycles existing object');
      }
    }
    page.plantingEffects.clear();
  });
  await h.run('support.imitater',
      'Automatic lily and pot inherit Imitater in placement and preview without changing existing bases',
      () async {
    for (final mapId in ['pool', 'roof']) {
      final baseType = mapId == 'pool' ? 'lily' : 'pot';
      s.execute('mimic support fixture', Formation(mapId: mapId));
      page.selectedType = 'pea';
      page.plantingEffects.clear();
      page.plantingEffects.add('模仿者');
      page.tool = '放置';
      page.updatePlantingPointer(BoardGeometry(s.document).cellCenter(2, 2));
      await h.settle();
      final painter = (h
              .find((w) => w is CustomPaint && w.painter is BoardPainter)
              .widget as CustomPaint)
          .painter as BoardPainter;
      h.expect(
          painter.plantingSupportPreviews.single.type == baseType &&
              painter.plantingSupportPreviews.single.effects.contains('模仿者'),
          'Mimic $baseType missing from preview');
      final before = s.document.fingerprint;
      plant(2, 2);
      h.expect(
          s.document.pieces
              .where((p) => p.type == baseType)
              .single
              .effects
              .contains('模仿者'),
          'Automatic $baseType must inherit Imitater');
      s.undo();
      h.expect(
          s.document.fingerprint == before, 'Mimic plant/support undo failed');
      final base =
          Piece(id: 'existing-base', type: baseType, row: 2, col: 2, layer: 0);
      s.execute(
          'existing normal support', Formation(mapId: mapId, pieces: [base]));
      plant(2, 2);
      h.expect(
          s.document.pieces.firstWhere((p) => p.id == base.id).effects.isEmpty,
          'Existing normal base must remain unchanged');
      page.plantingEffects.clear();
      s.execute('normal support fixture', Formation(mapId: mapId));
      plant(2, 2);
      h.expect(
          s.document.pieces
              .where((p) => p.type == baseType)
              .single
              .effects
              .isEmpty,
          'Ordinary plants must create normal supports');
      page.plantingEffects.clear();
      page.plantingEffects.add('模仿者');
    }
    page.plantingEffects.clear();
  });
  await h.run('shovel.top-bank',
      'Original top shovel bank toggles tool, highlights/removes one plant, preserves undo and readonly',
      () async {
    final fixture = Formation(mapId: 'day', pieces: [
      Piece(id: 'target', type: 'pea', row: 1, col: 1, layer: 10),
      Piece(id: 'under-hud', type: 'tallnut', row: 0, col: 7, layer: 10),
    ]);
    s.execute('bank fixture', fixture);
    page.cancelPlanting();
    await h.settle();
    h.expect(OriginalAssets.image('image/ShovelBank.png') != null,
        'Original bank artwork missing');
    final depth = s.undoDepth;
    for (final expected in ['铲除', '选择', '铲除']) {
      await h.tapElement(
          h.find((w) => w.key == const ValueKey('board-shovel-bank')));
      h.expect(
          page.tool == expected &&
              !page.gesture &&
              s.document.fingerprint == fixture.fingerprint &&
              s.undoDepth == depth,
          'Top bank click edited underlying plant or failed to toggle');
      h.expect(
          h.all((w) => w.key == const ValueKey('board-shovel-cursor')).length ==
              (expected == '铲除' ? 1 : 0),
          'Shovel must appear immediately on pickup and disappear on return');
    }
    h.expect(page.plantingPointer != null,
        'Picking up shovel cleared pointer before first movement');
    final cursor =
        h.find((w) => w.key == const ValueKey('board-shovel-cursor'));
    final cursorPosition = cursor.findAncestorWidgetOfExactType<Positioned>()!;
    final cursorStack = cursor.findAncestorWidgetOfExactType<Stack>()!;
    h.expect(
        identical(cursorStack.children.last, cursorPosition) &&
            cursor.findAncestorWidgetOfExactType<IgnorePointer>()!.ignoring,
        'Selected shovel must paint above the HUD without intercepting clicks');
    await h.screenshot('shovel.cursor-above-bank');
    final geometry = BoardGeometry(s.document);
    final pea = s.document.pieces.first;
    final bounds = geometry.pieceBounds(pea);
    final point = [
      for (var y = bounds.top; y < bounds.bottom; y++)
        for (var x = bounds.left; x < bounds.right; x++) Offset(x, y)
    ].firstWhere((p) => geometry.spriteContains(pea, p));
    page.updatePlantingPointer(point);
    await h.settle();
    final painter = h
        .find((w) => w is CustomPaint && w.painter is BoardPainter)
        .widget as CustomPaint;
    h.expect(
        (painter.painter as BoardPainter).shovelTargetIds.single == 'target',
        'Top shovel did not share smart target highlight');
    final box =
        page.plantingBoardKey.currentContext.findRenderObject() as RenderBox;
    await h.tapAt(box.localToGlobal(point));
    h.expect(
        s.document.pieces.single.id == 'under-hud' && s.undoDepth == depth + 1,
        'Top shovel removed wrong plant or broke undo grouping');
    s.undo();
    h.expect(s.document.fingerprint == fixture.fingerprint,
        'Top shovel undo failed');
    s.readOnly = true;
    await h.settle();
    final previousTool = page.tool;
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('board-shovel-bank')));
    h.expect(
        page.tool == previousTool &&
            s.document.fingerprint == fixture.fingerprint,
        'Readonly top shovel changed document/tool');
    s.readOnly = false;
    s.execute(
        'hide bank', fixture.copy(display: {...fixture.display, '卡槽': false}));
    await h.settle();
    h.expect(h.all((w) => w.key == const ValueKey('board-shovel-bank')).isEmpty,
        'Hidden seed bank retained shovel control');
  });
  await h.run('cards.toggle',
      'Repeated card clicks cancel planting or remove seed slot; preserve mimic indices and undo',
      () async {
    page.selectToolboxTab(2);
    page.cancelPlanting();
    await h.settle();
    final before = s.document.fingerprint;
    final depth = s.undoDepth;
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('original-card-pea')));
    h.expect(
        page.tool == '放置' && page.selectedType == 'pea', 'Card not selected');
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('original-card-pea')));
    h.expect(
        page.tool == '选择' &&
            page.plantingPointer == null &&
            s.document.fingerprint == before &&
            s.undoDepth == depth,
        'Second click must cancel preview without editing formation');
    final dropdown = h
        .find((w) =>
            w is DropdownButton<String> &&
            w.items!.any((item) => item.value == '智能'))
        .widget as DropdownButton<String>;
    h.expect(
        !dropdown.items!.any((item) => item.value == '最上层') &&
            dropdown.items!.any((item) => item.value == '智能'),
        'Invalid shovel options');
    final fixture = Formation(
        seedSlots: ['pea', 'pea', 'sunflower'], imitaterSeedSlots: {1});
    s.execute('seed fixture', fixture);
    page.selectToolboxTab(0);
    await h.settle();
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('seed-choice-normal-pea')));
    h.expect(
        s.document.seedSlots.join(',') == 'pea,sunflower' &&
            s.document.imitaterSeedSlots.single == 0,
        'Repeat card did not remove normal seed');
    s.undo();
    h.expect(s.document.fingerprint == fixture.fingerprint,
        'Seed removal not undoable');
    s.redo();
    await h.settle();
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('seed-choice-normal-pea')));
    h.expect(
        s.document.seedSlots.join(',') == 'pea,sunflower,pea' &&
            s.document.imitaterSeedSlots.single == 0,
        'Card cannot be reselected');
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('board-seed-return-0')));
    h.expect(
        s.document.seedSlots.join(',') == 'sunflower,pea' &&
            s.document.imitaterSeedSlots.isEmpty,
        'Click chosen mimic slot did not remove it');
    h.expect(page.tool == '选择', 'Removing selected card left planting active');
    s.undo();
    h.expect(
        s.document.imitaterSeedSlots.single == 0, 'Mimic slot undo failed');
    await page.toggleSeedChooser(false);
  });
  await h.run('defaults.water.undo',
      'Water plant and missing lily form one undo command', () async {
    h.expect(
        page.autoLily == true && page.autoPotMode == 'roof', 'Defaults wrong');
    plant(2, 0);
    h.expect(
        has('pea', 2, 0) && has('lily', 2, 0) && s.document.pieces.length == 2,
        'Missing automatic lily');
    s.undo();
    h.expect(s.document.pieces.isEmpty, 'Undo left a support');
    s.redo();
    h.expect(has('pea', 2, 0) && has('lily', 2, 0), 'Redo missing support');
    final lily = s.document.pieces.firstWhere((p) => p.type == 'lily');
    page.selectedType = 'sunflower';
    plant(2, 0);
    h.expect(
        s.document.pieces.where((p) => p.type == 'lily').single.id == lily.id,
        'Existing support replaced/duplicated');
  });
  await h.run('roof.modes', 'Roof-only, all-land and disabled pot modes',
      () async {
    s.execute('roof', Formation(mapId: 'roof'));
    page.selectedType = 'pea';
    plant(0, 0);
    h.expect(has('pot', 0, 0) && has('pea', 0, 0), 'Roof pot missing');
    s.execute('land', Formation(mapId: 'day'));
    plant(0, 0);
    h.expect(!has('pot', 0, 0), 'Roof mode added land pot');
    page.autoPotMode = 'land';
    plant(0, 1);
    h.expect(has('pot', 0, 1), 'All-land mode missing pot');
    page.autoPotMode = 'ground';
    s.execute('ground-only-roof', Formation(mapId: 'roof'));
    plant(0, 0);
    h.expect(!has('pot', 0, 0), 'Ground-only mode added roof pot');
    s.execute('ground-only-land', Formation(mapId: 'day'));
    plant(0, 0);
    h.expect(has('pot', 0, 0), 'Ground-only mode missing land pot');
    page.autoPotMode = 'off';
    s.execute('off-roof', Formation(mapId: 'roof'));
    plant(0, 0);
    h.expect(!has('pot', 0, 0), 'Off mode added pot');
  });
  await h.run('support.checkbox-options',
      'Roof/ground checkboxes are independent and settings omit extra tools',
      () async {
    page.autoPotMode = 'roof';
    page.classicTab = 2;
    page.update();
    await h.settle();
    Checkbox option(String name) =>
        h.find((w) => w.key == ValueKey('original-auto-pot-$name')).widget
            as Checkbox;
    h.expect(option('roof').value == true && option('land').value == false,
        'Default pot options must be roof on, ground off');
    h.expect(h.all((w) => w.key == const ValueKey('auto-pot-mode')).isEmpty,
        'Old dropdown still visible');
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('original-auto-pot-land')));
    h.expect(
        page.autoPotMode == 'land' &&
            option('roof').value == true &&
            option('land').value == true,
        'Both pot locations should be enabled');
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('original-auto-pot-roof')));
    h.expect(
        page.autoPotMode == 'ground' &&
            option('roof').value == false &&
            option('land').value == true,
        'Ground must remain independently enabled');
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('original-auto-pot-land')));
    h.expect(page.autoPotMode == 'off', 'Unchecking both must disable pots');
    await h.tapElement(
        h.find((w) => w.key == const ValueKey('original-auto-pot-roof')));
    h.expect(page.autoPotMode == 'roof', 'Roof-only option must restore');
    page.classicTab = 5;
    page.update();
    await h.settle();
    h.expect(h.all((w) => w is ExpansionTile).isEmpty,
        'Settings should not contain extra tools section');
    await h.screenshot('settings-without-extra-tools');
    page.classicTab = 2;
    page.update();
    await h.settle();
    await h.screenshot('support-checkbox-options');
  });
  await h.run('batch.width',
      'Batch two-cell plants receive two supports without duplicates',
      () async {
    s.execute('pool', Formation());
    page.autoLily = true;
    page.autoPotMode = 'roof';
    page.selectedType = 'cob';
    page.cells.clear();
    page.cells.add((2, 0));
    page.cells.add((2, 1));
    page.batchPlace();
    h.expect(
        s.document.pieces.length == 3 &&
            has('lily', 2, 0) &&
            has('lily', 2, 1) &&
            has('cob', 2, 0),
        'Batch supports or occupied-width wrong');
    s.undo();
    h.expect(s.document.pieces.isEmpty, 'Batch undo left supports');
    s.execute('roof', Formation(mapId: 'roof'));
    plant(0, 0);
    h.expect(has('pot', 0, 0) && has('pot', 0, 1),
        'Wide roof plant missing second pot');
  });
  await h.run('terrain.exclusions',
      'Native aquatics, bases, nonplants, blocked terrain and switches',
      () async {
    for (final type in [
      'lily',
      'pot',
      'tangle',
      'seashroom',
      'rake',
      'zombie'
    ]) {
      final p = Piece(
          id: 'p',
          type: type,
          row: 2,
          col: 0,
          layer: ObjectSpec.byId(type).layer);
      final pieces = [p];
      PlantingSupport.addMissing(pieces, p, BoardMap.byId('pool'));
      h.expect(pieces.length == 1, 'Unexpected support for $type');
    }
    s.execute('water off', Formation());
    page.selectedType = 'pea';
    page.autoLily = false;
    plant(2, 0);
    h.expect(s.document.pieces.length == 1, 'Disabled water setting ignored');
    final blocked =
        Piece(id: 'blocked', type: 'pea', row: 0, col: 0, layer: 10);
    final pieces = [blocked];
    PlantingSupport.addMissing(pieces, blocked, BoardMap.byId('day3'),
        potMode: 'land');
    h.expect(pieces.length == 1, 'Added pot to blocked terrain');
  });
  await h.run('replacement.cannon-overlap',
      'New footprint replaces both cannons; front cell permits planting and bases preserve cannon',
      () async {
    final original = Formation(mapId: 'day', pieces: [
      Piece(id: 'left', type: 'cob', row: 0, col: 0, layer: 10),
      Piece(id: 'right', type: 'cob', row: 0, col: 2, layer: 10),
    ]);
    s.execute('two cannons', original);
    page.selectedType = 'cob';
    plant(0, 1);
    h.expect(s.document.pieces.length == 1 && has('cob', 0, 1),
        'Shifted cannon must replace both overlapping cannons');
    s.undo();
    h.expect(s.document.fingerprint == original.fingerprint,
        'Undo did not restore both cannons');
    s.redo();
    h.expect(s.document.pieces.length == 1 && has('cob', 0, 1),
        'Redo did not restore shifted cannon');
    for (final type in ['pea', 'pumpkin', 'ladder']) {
      s.execute('two cannons', original);
      page.selectedType = type;
      plant(0, 1);
      h.expect(!has('cob', 0, 0) && has('cob', 0, 2) && has(type, 0, 1),
          'Front-cell $type failed to replace cannon only on its footprint');
    }
    for (final type in ['lily', 'pot']) {
      s.execute('two cannons', original);
      page.selectedType = type;
      plant(0, 1);
      h.expect(has('cob', 0, 0) && has('cob', 0, 2) && has(type, 0, 1),
          'Base $type removed cannon');
    }
  });
  await h.run('replacement.cannon',
      'Planting clears all previous plants across the footprint but preserves supports',
      () async {
    page.autoLily = true;
    page.autoPotMode = 'roof';
    s.execute(
        'stack fixture',
        Formation(pieces: [
          Piece(id: 'leaf0', type: 'lily', row: 2, col: 0, layer: 0),
          Piece(id: 'leaf1', type: 'lily', row: 2, col: 1, layer: 0),
          Piece(id: 'old0', type: 'pea', row: 2, col: 0, layer: 70),
          Piece(id: 'old1', type: 'pumpkin', row: 2, col: 1, layer: 20),
          Piece(id: 'ladder1', type: 'ladder', row: 2, col: 1, layer: 25),
          Piece(id: 'coffee', type: 'coffee', row: 2, col: 1, layer: 30),
        ]));
    final before = s.document.fingerprint;
    page.selectedType = 'cob';
    plant(2, 0);
    h.expect(
        s.document.pieces.length == 3 &&
            has('cob', 2, 0) &&
            s.document.pieces.any((p) => p.id == 'leaf0') &&
            s.document.pieces.any((p) => p.id == 'leaf1'),
        'Cannon left previous plants in either cell');
    s.undo();
    h.expect(s.document.fingerprint == before,
        'Replacement undo lost previous plants');
    page.selectedType = 'wallnut';
    plant(2, 1);
    h.expect(
        has('wallnut', 2, 1) &&
            has('pumpkin', 2, 1) &&
            has('coffee', 2, 1) &&
            has('lily', 2, 1),
        'Single-cell replacement failed');
    page.selectedType = 'pumpkin';
    plant(2, 1);
    h.expect(has('wallnut', 2, 1) && has('pumpkin', 2, 1),
        'Pumpkin removed inner plant');
    page.selectedType = 'pot';
    plant(2, 1);
    h.expect(has('pot', 2, 1) && has('wallnut', 2, 1) && !has('lily', 2, 1),
        'Manual base removed upper plant');
  });
  await h.run('aquatic.no-lily',
      'Aquatics remove existing lilies, never add them, and undo restores prior art',
      () async {
    for (final type in ['cattail', 'tangle', 'seashroom']) {
      s.execute(
          'aquatic fixture',
          Formation(pieces: [
            Piece(id: 'leaf', type: 'lily', row: 2, col: 1, layer: 0),
            Piece(id: 'plant', type: 'pea', row: 2, col: 1, layer: 10),
          ]));
      final before = s.document.fingerprint;
      page.selectedType = type;
      page.autoLily = true;
      plant(2, 1);
      h.expect(has(type, 2, 1) && !has('lily', 2, 1),
          'Aquatic retained/created lily: $type');
      s.undo();
      h.expect(s.document.fingerprint == before,
          'Aquatic undo lost original lily: $type');
    }
  });
  await h.run('preferences.persist.sync',
      'Preferences survive reload and travel in native window state', () async {
    final file = File('/tmp/pvz-planting-support/preferences.json');
    await const PlantingPreferences(autoLily: false, potMode: 'land')
        .save(file: file);
    final restored = await PlantingPreferences.load(file: file);
    h.expect(!restored.autoLily && restored.potMode == 'land',
        'Preferences not persisted');
    await const PlantingPreferences(potMode: 'ground').save(file: file);
    h.expect((await PlantingPreferences.load(file: file)).potMode == 'ground',
        'Independent ground-only preference did not persist');
    final state = page.windowState() as Map;
    h.expect(
        state['autoLily'] == page.autoLily &&
            state['autoPotMode'] == page.autoPotMode,
        'Preferences missing from bridge');
    await file.writeAsString('{"potMode":"unknown"}');
    final defaults = await PlantingPreferences.load(file: file);
    h.expect(defaults.autoLily && defaults.potMode == 'roof',
        'Invalid preferences did not default safely');
  });
  await h.run('shovel.transparent-overlap-and-gesture',
      'Transparent lower-row pixels pass through; one drag never tunnels through a removed sprite',
      () async {
    const path = 'qa-smart-shovel-mask';
    final pixels = Uint8List(32 * 32 * 4);
    // Four frames, each with a different opaque quadrant.
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        final frameX = x ~/ 16, frameY = y ~/ 16;
        if ((x % 16 < 8) == (frameX == 0) && (y % 16 < 8) == (frameY == 0)) {
          final i = (y * 32 + x) * 4;
          pixels[i] = pixels[i + 1] = pixels[i + 2] = pixels[i + 3] = 255;
        }
      }
    }
    final decoded = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        pixels, 32, 32, ui.PixelFormat.rgba8888, decoded.complete);
    OriginalAssets.images[path] = await decoded.future;
    final saved = OriginalAssets.sprites['Peashooter'];
    OriginalAssets.sprites['Peashooter'] = {
      'px': 0,
      'py': 0,
      'images': [
        {
          'path': path,
          'x': -40,
          'y': -157.5,
          'w': 80,
          'h': 160,
          'rw': 16,
          'rh': 16,
          'rows': 2,
          'cols': 2
        }
      ]
    };
    try {
      await OriginalAssets.ensureHitMasks(['pea']);
      for (final map in ['pool', 'roof']) {
        for (final flip in [false, true]) {
          for (final vertical in [false, true]) {
            for (final scale in [.5, 1.0, 1.8]) {
              for (var frame = 0; frame < 4; frame++) {
                final piece = Piece(
                    id: 'test',
                    type: 'pea',
                    row: 2,
                    col: 3,
                    layer: 10,
                    flipped: flip,
                    flippedVertical: vertical,
                    scale: scale,
                    frameRow: frame ~/ 2,
                    frameCol: frame % 2);
                final doc = Formation(mapId: map, pieces: [piece]);
                final g = BoardGeometry(doc);
                for (var quadrant = 0; quadrant < 4; quadrant++) {
                  final local = Offset(
                      quadrant.isEven ? -20 : 20, quadrant < 2 ? -80 : 0);
                  final point = g.pieceCenter(piece) +
                      Offset(local.dx * scale * (flip ? -1 : 1),
                          local.dy * scale * (vertical ? -1 : 1));
                  final ids = ShovelTargets.at(doc, point, '智能');
                  h.expect(ids.contains('test') == (quadrant == frame),
                      'Wrong alpha hit for $map/$flip/$vertical/$scale/$frame/$quadrant');
                }
              }
            }
          }
        }
      }
      final upper = Piece(
          id: 'upper',
          type: 'pea',
          row: 1,
          col: 3,
          layer: 10,
          frameRow: 1,
          frameCol: 1);
      final lower = Piece(
          id: 'lower',
          type: 'pea',
          row: 2,
          col: 3,
          layer: 10,
          frameRow: 0,
          frameCol: 0);
      final doc = Formation(pieces: [upper, lower]);
      final g = BoardGeometry(doc);
      final passThrough = g.pieceCenter(lower) + const Offset(20, -100);
      h.expect(ShovelTargets.at(doc, passThrough, '智能').single == 'upper',
          'Transparent lower sprite stole upper-row hit');
      final covered = g.pieceCenter(lower) + const Offset(-20, -100);
      final both = doc.copy(pieces: [upper.copy(frameCol: 0), lower]);
      s.execute('overlapping rows', both);
      page.tool = '铲除';
      page.shovelFilter = '智能';
      h.expect(ShovelTargets.at(both, covered, '智能').single == 'lower',
          'Opaque foreground must win');
      final before = s.document.fingerprint;
      final depth = s.undoDepth;
      page.beginGesture(covered);
      for (var move = 0; move < 8; move++) {
        page.touch(covered + Offset(move * .1, 0));
      }
      h.expect(page.shovelTargets(covered).isEmpty,
          'Preview highlighted newly exposed target in same drag');
      page.finishGesture();
      h.expect(
          s.document.pieces.length == 1 &&
              s.document.pieces.single.id == 'upper' &&
              s.undoDepth == depth + 1,
          'One drag tunneled through multiple rows');
      s.undo();
      h.expect(s.document.fingerprint == before, 'Undo failed');
      s.redo();
      h.expect(s.document.pieces.single.id == 'upper', 'Redo failed');
      page.beginGesture(covered);
      page.finishGesture();
      h.expect(s.document.pieces.isEmpty,
          'Next press cannot shovel revealed target');
    } finally {
      OriginalAssets.sprites['Peashooter'] = saved;
    }
  });
  await h.run('shovel.visible.delete.undo',
      'Smart clicks outside cell and shell Delete remain atomic', () async {
    final tall = Piece(id: 'tall', type: 'tallnut', row: 2, col: 3, layer: 10);
    s.execute('fixture', Formation(pieces: [tall]));
    final before = s.document.fingerprint;
    final geometry = BoardGeometry(s.document);
    final bounds = geometry.pieceBounds(tall);
    final point = [
      for (var y = bounds.top; y < bounds.center.dy; y += 1)
        for (var x = bounds.left; x < bounds.right; x += 1) Offset(x, y)
    ].firstWhere((p) =>
        geometry.hit(p)?.$1 != tall.row && geometry.spriteContains(tall, p));
    page.tool = '铲除';
    page.shovelFilter = '智能';
    page.beginGesture(point);
    page.finishGesture();
    h.expect(s.document.pieces.isEmpty,
        'Visible upper sprite click did not remove plant');
    s.undo();
    h.expect(s.document.fingerprint == before, 'Smart shovel undo lost plant');
    s.execute(
        'fixture',
        Formation(pieces: [
          Piece(id: 'shell', type: 'pumpkin', row: 2, col: 3, layer: 20),
          Piece(id: 'ladder', type: 'ladder', row: 2, col: 3, layer: 25),
          tall,
        ]));
    final shellBefore = s.document.fingerprint;
    page.selectedId = 'shell';
    page.removeSelected();
    h.expect(s.document.pieces.single.id == 'tall',
        'Delete shell left attached ladder');
    s.undo();
    h.expect(s.document.fingerprint == shellBefore,
        'Delete undo did not restore shell and ladder');
  });
  await h.report();
  await File('/tmp/pvz-planting-support-report.json')
      .writeAsString(jsonEncode(h.cases));
  s.dispose();
  await repo.close();
  exit(h.cases.every((c) => c['status'] == 'pass') ? 0 : 1);
}
