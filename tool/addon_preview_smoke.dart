// Pixel comparison: the cursor composite must match the placed sprite composite.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';

Future<ui.Image> render(void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(800, 600);
  picture.dispose();
  return image;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await OriginalAssets.ensureLoaded();
    for (final map in ['day', 'roof', 'roof6']) {
      for (final type in ['pumpkin', 'gloom']) {
        for (final flipped in [false, true]) {
          final empty = Formation(mapId: map, display: const {});
          final piece = Piece(id: 'preview', type: type, row: 1, col: 1,
              layer: ObjectSpec.byId(type).layer, flipped: flipped);
          final geometry = BoardGeometry(empty);
          final position = geometry.pieceCenter(piece);
          final placed = await render((canvas) => BoardPainter(
              document: empty.copy(pieces: [piece]), background: false,
              helpers: false).paint(canvas, geometry.size));
          final expected = await render((canvas) {
            canvas.drawPath(geometry.cellPath(piece.row, piece.col),
                Paint()..color = Colors.white.withOpacity(.18));
            canvas.drawImage(placed, Offset.zero,
                Paint()..color = Colors.white.withOpacity(.65));
          });
          final actual = await render((canvas) => BoardPainter(
              document: empty, background: false, plantingPreview: piece,
              plantingPosition: position).paint(canvas, geometry.size));
          final expectedBytes = (await expected.toByteData())!.buffer.asUint8List();
          final actualBytes = (await actual.toByteData())!.buffer.asUint8List();
          var different = 0;
          for (var i = 0; i < expectedBytes.length; i++) {
            if ((expectedBytes[i] - actualBytes[i]).abs() > 2) different++;
          }
          if (different > 0) {
            throw StateError('$map/$type/flipped=$flipped: $different pixel channels differ');
          }
          for (final image in [placed, expected, actual]) {
            image.dispose();
          }
        }
      }
    }
    stdout.writeln('PASS addon cursor previews match placed composite: pumpkin/gloom, day/roof/roof6, flipped');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
