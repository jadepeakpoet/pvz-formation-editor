import 'dart:io';
import 'package:pvz_formation_editor/editor/shovel_targets.dart';
import 'package:pvz_formation_editor/domain/layouts.dart';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';

Future<List<int>> render(Formation doc,
    {bool shovel = false,
    bool helpers = true,
    Offset? pointer,
    Set<String> targets = const {}}) async {
  final recorder = ui.PictureRecorder();
  BoardPainter(
          document: doc,
          shovelPreview: shovel,
          shovelTargetIds: targets,
          plantingPosition: pointer,
          helpers: helpers,
          background: false)
      .paint(Canvas(recorder), const Size(800, 600));
  final picture = recorder.endRecording();
  final image = await picture.toImage(800, 600);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final bytes = List<int>.of(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  image.dispose();
  picture.dispose();
  return bytes;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await OriginalAssets.ensureLoaded();
    await OriginalAssets.ensureHitMasks(OriginalAssets.names.keys);
    if (OriginalAssets.image('image/Shovel.png') == null) {
      throw StateError('Bundled shovel asset missing');
    }
    Piece object(String id, String type, {int col = 3, bool white = false}) =>
        Piece(
            id: id,
            type: type,
            row: 2,
            col: col,
            layer: ObjectSpec.byId(type).layer,
            effects: white ? {'模仿者'} : {});
    final stacked = Formation(pieces: [
      object('pot', 'pot'),
      object('pea', 'pea'),
      object('shell', 'pumpkin', white: true)
    ]);
    final geometry = BoardGeometry(stacked);
    final shell = geometry.pieceBounds(stacked.pieces.last);
    final centre = geometry.pieceCenter(stacked.pieces[1]);
    final rim = Offset(shell.center.dx, shell.bottom - 3);
    if (!ShovelTargets.at(stacked, centre, '智能').contains('pea')) {
      throw StateError('Shell opening must select its inner plant');
    }
    final laddered = OriginalActions.apply(stacked, '智能搭梯');
    final rimIds = ShovelTargets.at(laddered, rim, '智能');
    if (!rimIds.contains('shell') ||
        rimIds.contains('pea') ||
        !rimIds.contains(laddered.pieces.last.id)) {
      throw StateError(
          'Shell rim removes only shell and attached ladder: $rimIds');
    }
    if (ShovelTargets.at(stacked, centre, '容器').single != 'pot' ||
        ShovelTargets.at(stacked, centre, '全部').length != 3) {
      throw StateError('Explicit shovel ranges must remain available');
    }
    final tall = object('tall', 'tallnut');
    final tallDoc = Formation(pieces: [tall]);
    final tallGeometry = BoardGeometry(tallDoc);
    final tallBounds = tallGeometry.pieceBounds(tall);
    final top = [
      for (var y = tallBounds.top; y < tallBounds.center.dy; y += 1)
        for (var x = tallBounds.left; x < tallBounds.right; x += 1) Offset(x, y)
    ].firstWhere((p) =>
        tallGeometry.hit(p)?.$1 != tall.row &&
        tallGeometry.spriteContains(tall, p));
    if (!ShovelTargets.at(tallDoc, top, '智能').contains('tall')) {
      throw StateError(
          'Visible sprite above its logical cell must remain shovelable');
    }
    final mixed = Formation(pieces: [
      object('white', 'pumpkin', white: true),
      object('ordinary', 'pumpkin', col: 5)
    ]);
    final smart = OriginalActions.apply(mixed, '智能搭梯');
    if (smart.pieces.where((p) => p.type == 'ladder').length != 1 ||
        smart.pieces.last.col != 3 ||
        OriginalActions.apply(smart, '智能搭梯').pieces.length !=
            smart.pieces.length) {
      throw StateError(
          'Smart ladders must cover only white shells without duplicates');
    }
    final doc = Formation(display: const {});
    const pointer = Offset(400, 300);
    final baseline = await render(doc, pointer: pointer);
    final preview = await render(doc, shovel: true, pointer: pointer);
    final moved =
        await render(doc, shovel: true, pointer: const Offset(500, 400));
    var visible = 0;
    for (var i = 0; i < preview.length; i += 4) {
      if (preview[i + 3] == baseline[i + 3]) continue;
      visible++;
      final x = (i ~/ 4) % 800, y = (i ~/ 4) ~/ 800;
      if (x < 388 || x >= 452 || y < 245 || y >= 309) {
        throw StateError('Shovel rendered outside pointer bounds');
      }
      if (moved[i + 3] != baseline[i + 3]) {
        throw StateError('Previous pointer retained shovel pixels');
      }
    }
    if (visible < 300) throw StateError('Shovel preview not visible');
    for (final bytes in [
      await render(doc, shovel: true),
      await render(doc, shovel: true, pointer: pointer, helpers: false),
    ]) {
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] != baseline[i]) {
          throw StateError('Inactive/export renderer includes tool preview');
        }
      }
    }
    for (final edge in [Offset.zero, const Offset(800, 600)]) {
      final bytes = await render(doc, shovel: true, pointer: edge);
      if (bytes.every((b) => b == 0)) {
        throw StateError('Shovel disappears at canvas edge');
      }
    }
    final plant = Piece(id: 'target', type: 'pea', row: 1, col: 1, layer: 10);
    final planted = Formation(display: const {}, pieces: [plant]);
    final normal = await render(planted);
    final highlighted = await render(planted, targets: {'target'});
    if (!List.generate(normal.length, (i) => i)
        .any((i) => normal[i] != highlighted[i])) {
      throw StateError('Shovel target did not brighten');
    }
    for (final bytes in [
      await render(planted),
      await render(planted, targets: {'target'}, helpers: false),
    ]) {
      for (var i = 0; i < normal.length; i++) {
        if (normal[i] != bytes[i]) {
          throw StateError('Target highlight persisted or entered export');
        }
      }
    }
    if (plant.effects.contains('高亮')) {
      throw StateError('Target highlight mutated document');
    }
    stdout.writeln(
        'PASS shovel asset, pointer movement, edge clamping, cancellation and helper-free export');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
