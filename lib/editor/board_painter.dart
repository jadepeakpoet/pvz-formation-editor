import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../domain/formation.dart';
import 'original_assets.dart';

/// Canvas framing is local. Roof column delta is based on the 2026-10-20 DOM probe.
class BoardGeometry {
  final Formation document;
  BoardGeometry(this.document);
  // A geometry belongs to one immutable document. Build once per geometry,
  // rather than scanning every object for each sprite and hit-test candidate.
  late final Set<(int, int)> _potCells = {
    for (final piece in document.pieces)
      if (piece.type == 'pot') (piece.row, piece.col),
  };
  Size get size => const Size(800, 600);
  double get cellWidth => 720 / document.map.columns;
  double get boardTop => document.map.roof
      ? (document.map.rows == 6 ? 10 : 70)
      : document.map.rows == 6
          ? 80
          : 72.5;
  double get cellHeight =>
      document.map.roof || document.map.rows == 6 ? 85 : 100;
  // Roof rises 20 pixels per column; highland has a 20 pixel step.
  double slope(double column) {
    if (document.mapId == 'highland') return column >= 4 ? -20 : 0;
    return document.map.roof && column < 5.5 ? (5.5 - column) * 20 : 0;
  }

  Offset cellCenter(int row, int col) => Offset(40 + (col + .5) * cellWidth,
      boardTop + (row + .5) * cellHeight + slope(col + .5));
  Path cellPath(int row, int col) => Path()
    ..moveTo(40 + col * cellWidth,
        boardTop + row * cellHeight + slope(col.toDouble()))
    ..lineTo(40 + (col + 1) * cellWidth,
        boardTop + row * cellHeight + slope(col + 1.0))
    ..lineTo(40 + (col + 1) * cellWidth,
        boardTop + (row + 1) * cellHeight + slope(col + 1.0))
    ..lineTo(40 + col * cellWidth,
        boardTop + (row + 1) * cellHeight + slope(col.toDouble()))
    ..close();
  Offset pieceCenter(Piece p) {
    final name = OriginalAssets.names[p.type] ?? p.type;
    final sprite = OriginalAssets.sprites[name];
    final kind = OriginalAssets.kinds[name];
    final onPot = (kind == 'Plant' || kind == 'Shell') &&
        _potCells.contains((p.row, p.col));
    final lift = onPot ? const Offset(0, -5) : Offset.zero;
    // The source stores unlifted canvas Y in its protocol. A pot adjusts Plant
    // and Shell CSS top by -5; props (including ladders) keep their own top.
    if (sprite != null && p.websitePixelX != null && p.websitePixelY != null) {
      return Offset(p.websitePixelX!,
              p.websitePixelY! + (sprite['py'] as num).toDouble() - 37.5) +
          lift;
    }
    return (sprite != null
            ? cellCenter(p.row, p.col)
            : (cellCenter(p.row, p.col) +
                    cellCenter(p.row, p.col + p.spec.width - 1)) /
                2) +
        lift;
  }

  Rect pieceBounds(Piece p) {
    final data = OriginalAssets.sprites[OriginalAssets.names[p.type] ?? p.type];
    if (data != null) {
      Rect? bounds;
      for (final part in data['images'] as List) {
        if ((part['path'] as String).endsWith('/shadow.png')) continue;
        final x = ((part['x'] as num) - (data['px'] as num)).toDouble();
        final y = ((part['y'] as num) - (data['py'] as num)).toDouble() + 37.5;
        final w = (part['w'] as num).toDouble(),
            h = (part['h'] as num).toDouble();
        final rect = Rect.fromLTRB(
            (p.flipped ? -x - w : x) * p.scale,
            (p.flippedVertical ? -y - h : y) * p.scale,
            (p.flipped ? -x : x + w) * p.scale,
            (p.flippedVertical ? -y : y + h) * p.scale);
        bounds = bounds == null ? rect : bounds.expandToInclude(rect);
      }
      if (bounds != null) return bounds.shift(pieceCenter(p));
    }
    return Rect.fromCenter(
        center: pieceCenter(p) +
            Offset(
                0,
                p.layer <= 0
                    ? cellHeight * .25 * p.scale * (p.flippedVertical ? -1 : 1)
                    : 0),
        width: cellWidth * .72 * p.spec.width * p.scale,
        height: cellHeight * (p.layer <= 0 ? .24 : .68) * p.scale);
  }

  /// Match the rendered frame, anchor, scale and flips; transparent pixels
  /// and ground shadows never steal a shovel hit from another row.
  bool spriteContains(Piece piece, Offset point) {
    if (piece.opacity <= 0) return false;
    final data =
        OriginalAssets.sprites[OriginalAssets.names[piece.type] ?? piece.type];
    if (data == null) return pieceBounds(piece).contains(point);
    final delta = point - pieceCenter(piece);
    final local = Offset(
        delta.dx / (piece.flipped ? -piece.scale : piece.scale),
        delta.dy / (piece.flippedVertical ? -piece.scale : piece.scale) - 37.5);
    for (final part in data['images'] as List) {
      final path = part['path'] as String;
      if (path.endsWith('/shadow.png')) continue;
      final x = (part['x'] as num) - (data['px'] as num);
      final y = (part['y'] as num) - (data['py'] as num);
      final w = (part['w'] as num).toDouble();
      final h = (part['h'] as num).toDouble();
      if (!Rect.fromLTWH(x.toDouble(), y.toDouble(), w, h).contains(local)) {
        continue;
      }
      final rw = (part['rw'] as num).toDouble();
      final rh = (part['rh'] as num).toDouble();
      final sx = ((piece.frameCol % (part['cols'] as num).toInt()) * rw +
              (local.dx - x) * rw / w)
          .floor();
      final sy = ((piece.frameRow % (part['rows'] as num).toInt()) * rh +
              (local.dy - y) * rh / h)
          .floor();
      if (OriginalAssets.opaqueAt(path, sx, sy)) return true;
    }
    return false;
  }

  List<Piece> hitPieces(Offset point) {
    final indexed = document.pieces
        .asMap()
        .entries
        .where((e) => pieceBounds(e.value).contains(point))
        .toList()
      ..sort((a, b) {
        final row = b.value.row.compareTo(a.value.row);
        if (row != 0) return row;
        final layer = b.value.layer.compareTo(a.value.layer);
        if (layer != 0) return layer;
        final column = a.value.col.compareTo(b.value.col);
        return column == 0 ? b.key.compareTo(a.key) : column;
      });
    return indexed.map((e) => e.value).toList();
  }

  (int, int)? hit(Offset p) {
    for (var r = 0; r < document.map.rows; r++) {
      for (var c = 0; c < document.map.columns; c++) {
        if (cellPath(r, c).contains(p)) return (r, c);
      }
    }
    return null;
  }
}

/// One frame of the original six-frame planting dirt/water sprite sheet.
/// Lifecycle and frame timing are supplied by the editor; static exports omit it.
class GrowthEffect {
  static const frameCount = 6;
  final int row, col, frame;
  final bool? water;
  const GrowthEffect(
      {required this.row, required this.col, required this.frame, this.water})
      : assert(frame >= 0 && frame < frameCount);
}

class FogTile {
  final int row, column, maskFrame, textureFrame;
  final double opacity;
  const FogTile(this.row, this.column, this.maskFrame, this.textureFrame, this.opacity);
  Rect get rect => Rect.fromLTWH(-12 + column * 80.0, 20 + row * 85.0, 210, 190);
}

/// Source MakeFog/GatherFog geometry is independent of the lawn's row count.
/// Stable frame choices keep fog from reshuffling during hover or selection.
class FogGeometry {
  final Formation document;
  const FogGeometry(this.document);

  Set<(int, int)> get cleared {
    final result = <(int, int)>{};
    final firstColumn = 9 - document.fogColumns;
    for (final piece in document.pieces) {
      final rowRadius = piece.type == 'torch' ? 1 : piece.type == 'plantern' ? 2 : 0;
      if (rowRadius == 0) continue;
      final colRadius = piece.type == 'torch' ? 1 : 3;
      final minRow = piece.row - rowRadius, maxRow = piece.row + rowRadius;
      final minCol = piece.col - colRadius, maxCol = piece.col + colRadius;
      final firstRow = math.max(0, minRow), lastRow = math.min(9, maxRow);
      for (var row = firstRow; row <= lastRow; row++) {
        final corner = row == firstRow && minRow >= 0 || row == lastRow && maxRow < 10;
        final first = math.max(math.max(0, minCol + (corner ? 1 : 0)), firstColumn);
        final last = math.min(9, maxCol - (corner ? 1 : 0));
        for (var col = first; col <= last; col++) {
          result.add((row, col));
          if (col == 8) result.add((row, 9));
        }
      }
    }
    return result;
  }

  List<FogTile> get tiles {
    if (document.fogColumns <= 0) return const [];
    final first = 9 - document.fogColumns.clamp(0, 10);
    final hidden = cleared;
    return [
      for (var col = first; col <= 9; col++)
        for (var row = 0; row <= 6; row++)
          if (!hidden.contains((row, col)))
            FogTile(row, col, (row * 31 + col * 17) & 7,
                (row * 13 + col * 7 + 3) & 7, col == first ? .78 * .78 : 1),
    ];
  }
}

class BoardPainter extends CustomPainter {
  // Ten-card bank: original GetShovelButtonRect uses 456 + 153.
  static const sunValueBounds = Rect.fromLTWH(18, 59, 66, 24);
  static const shovelBankBounds = Rect.fromLTWH(609, 0, 70, 72);
  static Rect seedSlotBounds(int index) {
    if (index < 0 || index >= 10) throw RangeError.range(index, 0, 9, 'index');
    return Rect.fromLTWH(89 + index * 51, 8, 50, 70);
  }

  final Formation document;
  final Piece? plantingPreview;
  final List<Piece> plantingSupportPreviews;
  final Offset? plantingPosition;
  final bool shovelPreview;
  final Set<String> shovelTargetIds;
  final List<GrowthEffect> growthEffects;
  final Set<(int, int)> selectedCells;
  final String? selectedId, stateHoverId;
  final bool background, helpers, paintSunValue;
  BoardPainter(
      {required this.document,
      this.plantingPreview,
      this.plantingSupportPreviews = const [],
      this.plantingPosition,
      this.shovelPreview = false,
      this.shovelTargetIds = const {},
      this.growthEffects = const [],
      this.selectedCells = const {},
      this.selectedId,
      this.stateHoverId,
      this.background = true,
      this.paintSunValue = true,
      this.helpers = true})
      : super(repaint: OriginalAssets.revision);
  void label(Canvas canvas, String text, Offset center, double fontSize,
      {Color color = Colors.white}) {
    final painter = TextPainter(
        text: TextSpan(
            text: text,
            style: TextStyle(
                color: color, fontSize: fontSize, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: 240);
    painter.paint(
        canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = BoardGeometry(document);
    canvas.save();
    canvas.scale(size.width / g.size.width, size.height / g.size.height);
    canvas.clipRect(Offset.zero & g.size);
    final night = document.mapId == 'night' ||
        document.mapId == 'fog' ||
        document.mapId == 'moonRoof';
    if (background) {
      canvas.drawRect(
          Offset.zero & g.size,
          Paint()
            ..color =
                night ? const Color(0xff182b35) : const Color(0xffd5dfb2));
    }
    final layers = OriginalAssets.maps[document.map.name] as List?;
    final hasMap = layers != null;
    if (background && layers != null) {
      for (final layer in layers) {
        final image = OriginalAssets.image(layer['path'] as String);
        if (image != null) {
          canvas.drawImage(
              image,
              Offset((layer['x'] as num).toDouble(),
                  (layer['y'] as num).toDouble()),
              Paint());
        }
      }
    }
    for (var r = 0; r < document.map.rows; r++) {
      for (var c = 0; c < document.map.columns; c++) {
        final path = g.cellPath(r, c);
        if (background && !hasMap) {
          final water = document.map.waterRows.contains(r);
          final color = document.map.roof
              ? const Color(0xffa56c50)
              : water
                  ? const Color(0xff428fa6)
                  : const Color(0xff6e9f51);
          canvas.drawPath(
              path,
              Paint()
                ..color = Color.lerp(color, night ? Colors.black : Colors.white,
                    (r + c).isEven ? .06 : .14)!);
        }
        if (helpers) {
          if (document.display['坐标'] == true) {
            canvas.drawPath(
                path,
                Paint()
                  ..color = Colors.white.withOpacity(.18)
                  ..style = PaintingStyle.stroke);
          }
          if (selectedCells.contains((r, c))) {
            canvas.drawPath(path,
                Paint()..color = const Color(0xff4f9a68).withOpacity(.22));
          }
          if (document.display['坐标'] == true) {
            label(
                canvas,
                '${r + 1},${c + 1}',
                g.cellCenter(r, c) +
                    Offset(-g.cellWidth * .32, -g.cellHeight * .35),
                12,
                color: Colors.white70);
          }
        }
      }
    }
    if (document.display['卡槽'] == true &&
        OriginalAssets.image('image/Seed.png') != null) {
      final seed = OriginalAssets.image('image/Seed.png')!;
      canvas.drawImage(seed, const Offset(11, 0), Paint());
      for (var i = 0; i < document.seedSlots.length && i < 10; i++) {
        final path = OriginalAssets.cardPath(document.seedSlots[i],
                imitater: document.imitaterSeedSlots.contains(i))
            .replaceFirst('assets/original/', '');
        final mimic = document.imitaterSeedSlots.contains(i);
        final grayCard = OriginalAssets.image(path);
        final card = grayCard ??
            (mimic
                ? OriginalAssets.image(
                    OriginalAssets.cardPath(document.seedSlots[i])
                        .replaceFirst('assets/original/', ''))
                : null);
        final paint = Paint();
        if (mimic && grayCard == null) {
          paint.colorFilter = const ColorFilter.matrix([
            .2126,
            .7152,
            .0722,
            0,
            0,
            .2126,
            .7152,
            .0722,
            0,
            0,
            .2126,
            .7152,
            .0722,
            0,
            0,
            0,
            0,
            0,
            1,
            0
          ]);
        }
        if (card != null) {
          canvas.drawImageRect(
              card,
              Rect.fromLTWH(
                  0, 0, card.width.toDouble(), card.height.toDouble()),
              seedSlotBounds(i),
              paint);
        }
      }
    } else if (document.display['卡槽'] == true) {
      for (var i = 0; i < 8; i++) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(280 + i * 75, 25, 64, 80),
                const Radius.circular(8)),
            Paint()..color = const Color(0xff967553));
        label(canvas, '${i + 1}', Offset(312 + i * 75, 64), 20);
      }
    }
    if (paintSunValue && document.display['阳光'] == true) {
      final sunlight = TextPainter(
          text: TextSpan(
              text: '${document.sunValue}',
              style: const TextStyle(
                  fontFamily: 'Continuum Bold',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.black)),
          textDirection: TextDirection.ltr)
        ..layout();
      sunlight.paint(canvas, const Offset(30, 62));
    }
    final menu = OriginalAssets.image('image/Button.png');
    if (menu != null &&
        (document.display['阳光'] == true || document.display['卡槽'] == true)) {
      canvas.drawImage(menu, const Offset(683, -9), Paint());
    }
    for (var r = 0; r < document.map.rows; r++) {
      if (document.display['脑子'] == true) {
        final brain = OriginalAssets.image('image/brain.png');
        if (brain != null) {
          final pos = Offset(0, g.cellCenter(r, 0).dy - 2.5);
          canvas.drawImage(brain, pos, Paint());
        }
      }
    }
    // Rows define scene depth: a front row covers every sprite in a back row.
    // Layer remains local to each row, preserving pot/plant/shell/addon stacking
    // and user layer adjustments without letting a back-row shell or effect
    // cover the plants in front of it.
    final visualPieces = <Piece>[];
    if (document.display['小推车'] == true) {
      for (var row = 0; row < document.map.rows; row++) {
        final type = document.map.roof
            ? 'Roofcleaner'
            : document.map.waterRows.contains(row)
                ? 'Poolcleaner'
                : 'Lawnmower';
        final data = OriginalAssets.sprites[type];
        if (data == null) continue;
        // Source lawn equipment uses pc=0, one roof slope step left of plants.
        final ground =
            g.cellCenter(row, 0).dy + 37.5 + (document.map.roof ? 20 : 0);
        visualPieces.add(Piece(
            id: 'decoration:mower:$row',
            type: type,
            row: row,
            col: 0,
            layer: 45,
            websiteFields: [
              '0',
              '${row + 1}',
              '0',
              '0',
              '0',
              '0',
              '1',
              '0',
              '15',
              '${ground - (data['py'] as num)}'
            ]));
      }
    }
    for (final original in document.pieces) {
      var piece = helpers && shovelTargetIds.contains(original.id)
          ? original.copy(effects: {...original.effects, '高亮'})
          : original;
      if (helpers && stateHoverId == original.id) {
        piece = piece.copy(opacity: piece.opacity * .55);
      }
      final name = OriginalAssets.names[piece.type] ?? piece.type;
      if (name == 'Pumpkin') {
        visualPieces
            .add(_addon(piece, 'Pumpkin_back', piece.layer - 11, frameRow: 0));
      } else if (name == 'ScaryPot') {
        visualPieces
            .add(_addon(piece, 'ScaryPot_back', piece.layer - 1, frameRow: 0));
      }
      visualPieces.add(piece);
      if (name == 'Gloomshroom') {
        visualPieces.add(_addon(piece, 'GloomPuff', piece.layer + 40,
            noDiscoloration: true));
      }
    }
    final entries = visualPieces.asMap().entries.toList()
      ..sort((a, b) {
        final row = a.value.row.compareTo(b.value.row);
        if (row != 0) return row;
        final layer = a.value.layer.compareTo(b.value.layer);
        if (layer != 0) return layer;
        final column = b.value.col.compareTo(a.value.col);
        return column == 0 ? a.key.compareTo(b.key) : column;
      });
    for (final entry in entries) {
      final p = entry.value;
      final center = g.pieceCenter(p);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(p.flipped ? -p.scale : p.scale,
          p.flippedVertical ? -p.scale : p.scale);
      if (_sprite(canvas, p)) {
        canvas.restore();
        continue;
      }
      var color = Color(p.spec.color);
      if (p.effects.contains('模仿者')) {
        color = Color.lerp(color, Colors.grey, .8)!;
      }
      if (p.effects.contains('冰冻')) {
        color = Color.lerp(color, Colors.lightBlueAccent, .65)!;
      }
      if (p.effects.contains('魅惑')) {
        color = Color.lerp(color, Colors.purpleAccent, .65)!;
      }
      if (p.effects.contains('灰烬')) color = const Color(0xff494846);
      if (p.opacity < 1) color = color.withOpacity(p.opacity);
      final w = g.cellWidth * .72 * p.spec.width;
      final h = g.cellHeight * (p.layer <= 0 ? .24 : .68);
      final rect = Rect.fromCenter(
          center: Offset(0, p.layer <= 0 ? g.cellHeight * .25 : 0),
          width: w,
          height: h);
      if (p.effects.contains('高亮')) {
        canvas.drawOval(
            rect.inflate(8), Paint()..color = Colors.yellow.withOpacity(.7));
      }
      final shape = RRect.fromRectAndRadius(
          rect, Radius.circular(p.spec.category == '僵尸' ? 8 : 24));
      if (p.effects.contains('我是僵尸')) {
        canvas.drawRRect(
            shape.shift(const Offset(6, 8)), Paint()..color = Colors.black38);
      }
      canvas.drawRRect(
          shape,
          Paint()
            ..color = color
            ..style =
                p.appearance == '轮廓' ? PaintingStyle.stroke : PaintingStyle.fill
            ..strokeWidth = 4);
      canvas.drawRRect(
          shape,
          Paint()
            ..color = Colors.black38
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      // A visible asymmetric mark makes horizontal flips meaningful.
      canvas.drawCircle(Offset(rect.right - 10, rect.center.dy - 7), 4,
          Paint()..color = Colors.white);
      canvas.restore();
      label(
          canvas,
          p.spec.name,
          center + Offset(0, p.layer <= 0 ? g.cellHeight * .25 : 0),
          g.cellWidth < 85 ? 11 : 14,
          color: const Color(0xff182619));
    }
    if (document.display['泥土'] == true && growthEffects.isNotEmpty) {
      final sheet = OriginalAssets.image('image/GrowPlant.png');
      if (sheet != null) {
        for (final effect in growthEffects) {
          if (effect.row < 0 ||
              effect.row >= document.map.rows ||
              effect.col < 0 ||
              effect.col >= document.map.columns) continue;
          final water =
              effect.water ?? document.map.waterRows.contains(effect.row);
          final origin =
              g.cellCenter(effect.row, effect.col) + const Offset(-30, 17.5);
          canvas.drawImageRect(
              sheet,
              Rect.fromLTWH(effect.frame * 61.0, water ? 34 : 0, 61, 34),
              origin & const Size(61, 34),
              Paint()..filterQuality = FilterQuality.none);
        }
      }
    }
    if (document.display['迷雾'] == true && document.fogColumns > 0) {
      _fog(canvas);
    }
    if (document.display['继续标识'] == true) {
      final banner = OriginalAssets.image('image/ClickToContinue.png');
      if (banner != null) {
        canvas.drawRect(const Rect.fromLTWH(40, 518, 760, 53),
            Paint()..color = const Color(0x66000000));
        canvas.drawImage(banner, const Offset(285, 525), Paint());
      }
    }
    if (helpers && plantingPreview != null && plantingPosition != null) {
      final p = plantingPreview!;
      canvas.drawPath(g.cellPath(p.row, p.col),
          Paint()..color = Colors.white.withOpacity(.18));
      canvas.saveLayer(
          Offset.zero & g.size, Paint()..color = Colors.white.withOpacity(.65));
      for (final support in plantingSupportPreviews) {
        final center = g.pieceCenter(support);
        canvas.save();
        canvas.translate(center.dx, center.dy);
        _sprite(canvas, support);
        canvas.restore();
      }
      canvas.translate(plantingPosition!.dx, plantingPosition!.dy);
      canvas.scale(p.flipped ? -p.scale : p.scale,
          p.flippedVertical ? -p.scale : p.scale);
      final name = OriginalAssets.names[p.type] ?? p.type;
      if (name == 'Pumpkin') {
        _sprite(canvas, _addon(p, 'Pumpkin_back', p.layer - 11, frameRow: 0));
      }
      _sprite(canvas, p);
      if (name == 'Gloomshroom') {
        _sprite(canvas,
            _addon(p, 'GloomPuff', p.layer + 40, noDiscoloration: true));
      }
      canvas.restore();
    }
    if (helpers && shovelPreview && plantingPosition != null) {
      final shovel = OriginalAssets.image('image/Shovel.png');
      if (shovel != null) {
        // Keep the blade tip near the pointer, with the handle above/right.
        // This is transient tool feedback; helper-free exports omit it.
        const side = 64.0;
        final position = plantingPosition!;
        final left = (position.dx - 12).clamp(0.0, g.size.width - side);
        final top = (position.dy - 55).clamp(0.0, g.size.height - side);
        canvas.drawImageRect(
            shovel,
            Rect.fromLTWH(
                0, 0, shovel.width.toDouble(), shovel.height.toDouble()),
            Rect.fromLTWH(left, top, side, side),
            Paint()..filterQuality = FilterQuality.medium);
      }
    }
    canvas.restore();
  }

  // These secondary canvases are created automatically by the original site.
  void _fog(Canvas canvas) {
    final texture = OriginalAssets.image('image/fog.jpg');
    final mask = OriginalAssets.image('image/fog_.jpg');
    if (texture == null || mask == null) return;
    // The source stores the cloud silhouette in the mask's red channel, not
    // JPEG alpha. Drawing the mask as ordinary artwork leaves a black sheet.
    final maskPaint = Paint()
      ..blendMode = BlendMode.dstIn
      ..colorFilter = const ColorFilter.matrix([
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        1, 0, 0, 0, 0,
      ]);
    for (final tile in FogGeometry(document).tiles) {
      final rect = tile.rect;
      canvas.saveLayer(rect, Paint()..color = Colors.white.withOpacity(tile.opacity));
      canvas.drawImageRect(texture,
          Rect.fromLTWH(tile.textureFrame * 210.0, 0, 210, 190), rect, Paint());
      canvas.drawImageRect(mask,
          Rect.fromLTWH(tile.maskFrame * 210.0, 0, 210, 190), rect, maskPaint);
      canvas.restore();
    }
  }

  // Pumpkin/ScaryPot backs track columns only; GloomPuff tracks both axes.
  Piece _addon(Piece master, String type, int layer,
          {int? frameRow, bool noDiscoloration = false}) =>
      Piece(
          id: '${master.id}:$type',
          type: type,
          row: master.row,
          col: master.col,
          layer: layer,
          scale: master.scale,
          opacity: master.opacity,
          flipped: master.flipped,
          flippedVertical: master.flippedVertical,
          frameRow: frameRow ?? master.frameRow,
          frameCol: master.frameCol,
          websiteFields: master.websiteFields,
          effects: noDiscoloration
              ? master.effects.difference({'模仿者', '灰烬', '冰冻', '魅惑'})
              : master.effects);

  bool _sprite(Canvas canvas, Piece p) {
    final data = OriginalAssets.sprites[OriginalAssets.names[p.type] ?? p.type];
    if (data == null) return false;
    final parts = data['images'] as List;
    if (!parts
        .any((part) => OriginalAssets.image(part['path'] as String) != null)) {
      return false;
    }
    // Sprite anchors are local to each part. Preview addons share a canvas,
    // so translating one part must not offset the next one.
    canvas.save();
    // The DOM anchors describe the ground position, below the cell centre.
    canvas.translate(0, 37.5);
    final translucent = p.opacity < 1;
    final dropShadow = p.effects.contains('阴影') || p.effects.contains('我是僵尸');
    final tinted = p.effects.contains('灰烬') ||
        p.effects.contains('冰冻') ||
        p.effects.contains('魅惑') ||
        p.effects.contains('高亮') ||
        dropShadow;
    if (translucent || tinted) {
      final effectPaint = Paint();
      if (translucent) {
        effectPaint.color = Color.fromRGBO(255, 255, 255, p.opacity);
      }
      if (p.effects.contains('灰烬')) {
        effectPaint.colorFilter =
            const ColorFilter.mode(Colors.black, BlendMode.srcIn);
      } else {
        var red = 1.0, green = 1.0, blue = 1.0;
        if (p.effects.contains('冰冻')) {
          red *= .5;
          green *= .5;
          blue *= 2;
        }
        if (p.effects.contains('魅惑')) {
          green *= .5;
          blue *= 1.5;
        }
        if (p.effects.contains('高亮')) {
          red *= 1.5;
          green *= 1.5;
          blue *= 1.5;
        }
        if (dropShadow) {
          red *= .95;
          green *= .75;
          blue *= .6;
        }
        effectPaint.colorFilter = ColorFilter.matrix(<double>[
          red,
          0,
          0,
          0,
          0,
          0,
          green,
          0,
          0,
          0,
          0,
          0,
          blue,
          0,
          0,
          0,
          0,
          0,
          1,
          0,
        ]);
      }
      canvas.saveLayer(null, effectPaint);
    }
    for (final part in parts) {
      final path = part['path'] as String;
      final image = p.effects.contains('模仿者')
          ? OriginalAssets.grayImage(
                  OriginalAssets.names[p.type] ?? p.type, path) ??
              OriginalAssets.image(path)
          : OriginalAssets.image(path);
      if (image == null) continue;
      final shadow = path.endsWith('/shadow.png');
      final rw =
          shadow ? image.width.toDouble() : (part['rw'] as num).toDouble();
      final rh =
          shadow ? image.height.toDouble() : (part['rh'] as num).toDouble();
      final w =
          shadow && part['w'] == 100 ? 86.0 : (part['w'] as num).toDouble();
      final h =
          shadow && part['h'] == 100 ? 36.0 : (part['h'] as num).toDouble();
      final source = Rect.fromLTWH(
          shadow ? 0 : (p.frameCol % (part['cols'] as num).toInt()) * rw,
          shadow ? 0 : (p.frameRow % (part['rows'] as num).toInt()) * rh,
          rw,
          rh);
      final target = Rect.fromLTWH(
          (part['x'] as num).toDouble() - (data['px'] as num),
          (part['y'] as num).toDouble() - (data['py'] as num),
          w,
          h);
      if (!shadow && dropShadow && !p.effects.contains('灰烬')) {
        const offsets = [Offset(-3, -1), Offset(3, 1), Offset(4, 2)];
        const colors = [
          Color(0xffa18e73),
          Color(0xffb08d75),
          Color(0xff805b3b)
        ];
        // CSS applies its three drop-shadow filters in sequence, so each later
        // shadow also includes the earlier shadows' alpha silhouettes.
        for (var mask = 7; mask > 0; mask--) {
          var offset = Offset.zero, count = 0, last = 0;
          for (var i = 0; i < 3; i++) {
            if (mask & (1 << i) != 0) {
              offset += offsets[i];
              count++;
              last = i;
            }
          }
          canvas.drawImageRect(
              image,
              source,
              target.shift(offset),
              Paint()
                ..colorFilter = ColorFilter.mode(colors[last], BlendMode.srcIn)
                ..maskFilter = MaskFilter.blur(
                    BlurStyle.normal, math.sqrt(count.toDouble())));
        }
      }
      canvas.drawImageRect(
          image, source, target, Paint()..filterQuality = FilterQuality.medium);
    }
    if (translucent || tinted) canvas.restore();
    canvas.restore();
    return true;
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}

Future<Uint8List> exportPng(Formation document,
        {double multiplier = 1,
        bool background = true,
        bool pokerWidth = false}) =>
    OriginalAssets.images.retainDuring(() =>
        OriginalAssets.retainImitationDuring(() => _exportPng(document,
            multiplier: multiplier,
            background: background,
            pokerWidth: pokerWidth)));

Future<Uint8List> _exportPng(Formation document,
    {double multiplier = 1,
    bool background = true,
    bool pokerWidth = false}) async {
  if (!multiplier.isFinite || multiplier < .25 || multiplier > 4) {
    throw ArgumentError.value(multiplier, 'multiplier', '输出倍率必须在 0.25～4 之间');
  }
  await OriginalAssets.ensureBoardImages(document.map.name, document.seedSlots);
  await OriginalAssets.ensureTypes([
    ...document.pieces.map((piece) => piece.type),
    if (document.display['小推车'] == true) ...['Lawnmower', 'Poolcleaner', 'Roofcleaner'],
  ]);
  await OriginalAssets.ensureImitationImages(document.pieces
      .where((piece) => piece.effects.contains('模仿者'))
      .map((piece) => piece.type));
  final size = BoardGeometry(document).size;
  final recorder = ui.PictureRecorder();
  final widthScale = pokerWidth ? 917 / 800 : 1.0;
  final canvas = Canvas(recorder)..scale(multiplier * widthScale, multiplier);
  BoardPainter(document: document, background: background, helpers: false)
      .paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
      (size.width * widthScale * multiplier).round(),
      (size.height * multiplier).round());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('PNG 编码失败');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}
