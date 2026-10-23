// Real-engine regression for the original site's freely positioned prop anchors.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/domain/original_catalog.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await OriginalAssets.ensureLoaded();
    final document = WebsiteCodec.decode('0,30 2 1 0 0 0 1 0 160 160');
    final piece = document.pieces.single;
    final geometry = BoardGeometry(document);
    final center = geometry.pieceCenter(piece);
    final bounds = geometry.pieceBounds(piece);
    if ((center.dx - 160).abs() > .001 ||
        (bounds.left - 145).abs() > .001 ||
        (bounds.top - 160).abs() > .001) {
      throw StateError(
          'Expected original Ladder canvas left 145, top 160, anchor x160. Actual center $center bounds $bounds');
    }
    final roof = OriginalCatalog.formations[333].decode();
    final roofGeometry = BoardGeometry(roof);
    for (final expected in [
      ('winter', 0, 5, 9.0),
      ('gloom', 0, 3, 38.0),
      ('pot', 0, 5, 95.0),
      ('ladder', 0, 3, 105.0)
    ]) {
      final p = roof.pieces.firstWhere((p) =>
          p.type == expected.$1 &&
          p.row == expected.$2 &&
          p.col == expected.$3);
      final data =
          OriginalAssets.sprites[OriginalAssets.names[p.type] ?? p.type];
      final top = roofGeometry.pieceCenter(p).dy + 37.5 - (data['py'] as num);
      if ((top - expected.$4).abs() > .001) {
        throw StateError(
            'Source roof ${p.type} expected CSS top ${expected.$4}, actual $top');
      }
    }
    final png = await exportPng(document);
    if (png.isEmpty) throw StateError('Positioned ladder PNG is empty');
    final pokerCodec = await ui
        .instantiateImageCodec(await exportPng(document, pokerWidth: true));
    final poker = (await pokerCodec.getNextFrame()).image;
    if (poker.width != 917 || poker.height != 600) {
      throw StateError('Poker export must be 917×600');
    }
    poker.dispose();
    pokerCodec.dispose();
    stdout.writeln(
        'PASS positioned Ladder, four source roof anchors, 917x600 poker export');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
