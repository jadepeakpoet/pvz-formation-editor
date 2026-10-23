import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<Uint8List> pixels(List<Piece> pieces) async {
  final recorder = ui.PictureRecorder();
  BoardPainter(
          document: Formation(mapId: 'day', pieces: pieces, display: const {}),
          background: false,
          helpers: false)
      .paint(Canvas(recorder), const Size(800, 600));
  final picture = recorder.endRecording();
  final image = await picture.toImage(800, 600);
  final bytes = (await image.toByteData())!.buffer.asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

Future<void> frontCovers(Piece back, Piece front, String message,
    {bool hit = true}) async {
  final a = await pixels([back]);
  // Keep the pot's 5px plant lift in the reference without drawing its body.
  final b = await pixels([front, if (back.type == 'pot') back.copy(scale: 0)]);
  // Intentionally supply front first: the painter must sort, not use input order.
  final both = await pixels([front, back]);
  var overlap = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i + 3] != 255 || b[i + 3] != 255) continue;
    if (a[i] == b[i] && a[i + 1] == b[i + 1] && a[i + 2] == b[i + 2]) {
      continue;
    }
    overlap++;
    check(
        (both[i] - b[i]).abs() <= 2 &&
            (both[i + 1] - b[i + 1]).abs() <= 2 &&
            (both[i + 2] - b[i + 2]).abs() <= 2,
        '$message: front pixel obscured at ${i ~/ 4 % 800},${i ~/ 3200}');
    if (hit) {
      final g = BoardGeometry(Formation(mapId: 'day', pieces: [front, back]));
      check(
          g.hitPieces(Offset((i ~/ 4 % 800) + .5, (i ~/ 3200) + .5)).first.id ==
              front.id,
          '$message: hit disagrees with visible front');
    }
  }
  check(overlap > 20, '$message: requires meaningful opaque sprite overlap');
}

Piece piece(String type, String id, int row, int layer) =>
    Piece(id: id, type: type, row: row, col: 2, layer: layer, scale: 2);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await OriginalAssets.ensureLoaded();
    await frontCovers(piece('pumpkin', 'back', 1, 20),
        piece('pea', 'front', 2, 10), 'front row beats shell layer');
    await frontCovers(piece('gloom', 'back', 1, 10),
        piece('sunflower', 'front', 2, 10), 'front row beats gloom addon',
        hit: false);
    await frontCovers(piece('pot', 'back', 2, 0), piece('pea', 'front', 2, 10),
        'plant above pot');
    await frontCovers(piece('lily', 'back', 2, 0), piece('pea', 'front', 2, 10),
        'plant above lily');
    final shellStack = Formation(mapId: 'day', pieces: [
      piece('pot', 'pot', 2, 0),
      piece('pea', 'plant', 2, 10),
      piece('pumpkin', 'shell', 2, 20),
    ]);
    final shellGeometry = BoardGeometry(shellStack);
    final shellHits = shellGeometry.hitPieces(shellGeometry.cellCenter(2, 2));
    check(shellHits.first.id == 'shell',
        'same-cell shell hit precedes plant and pot');
    final forward = await pixels(shellStack.pieces);
    final reverse = await pixels(shellStack.pieces.reversed.toList());
    check(
        List.generate(forward.length, (i) => forward[i] == reverse[i])
            .every((same) => same),
        'pot/plant/split pumpkin compositing independent of insertion order');
    stdout.writeln(
        'PASS: row depth, gloom addon, pot/plant/lily/shell pixel compositing and visible hit order');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
