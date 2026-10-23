import 'dart:ui';
import 'dart:async';
import 'original_assets.dart';
import '../domain/formation.dart';
import '../domain/object_filter.dart';
import 'board_painter.dart';

/// Both hover feedback and removal use this result, including shell attachments.
class ShovelTargets {
  static Set<String> at(Formation doc, Offset point, String filter) {
    if (filter == '智能') {
      unawaited(OriginalAssets.ensureHitMasks(doc.pieces.map((p) => p.type)));
    }
    final geometry = BoardGeometry(doc);
    final cell = geometry.hit(point);
    if (cell == null && filter != '智能') return {};
    final stack = doc.pieces
        .where((p) =>
            cell != null &&
            p.row == cell.$1 &&
            p.col <= cell.$2 &&
            cell.$2 < p.col + p.spec.width)
        .toList()
      ..sort((a, b) {
        final layer = b.layer.compareTo(a.layer);
        return layer != 0
            ? layer
            : doc.pieces.indexOf(b).compareTo(doc.pieces.indexOf(a));
      });
    Set<String> ids;
    if (filter == '智能') {
      final hits = geometry.hitPieces(point);
      Piece? target;
      for (final p in hits) {
        if (p.type == 'pumpkin') {
          final bounds = geometry.pieceBounds(p);
          final x = (point.dx - bounds.center.dx) / (bounds.width * .33);
          final y = (point.dy - (bounds.top + bounds.height * .12)) /
              (bounds.height * .50);
          // The opening is a semantic slot: small transparent holes within the
          // inner plant must not redirect a click to the shell in front of it.
          if (x * x + y * y < 1) {
            final inner = hits.where((q) =>
                q.row == p.row &&
                q.col <= p.col &&
                p.col < q.col + q.spec.width &&
                q.spec.category == '植物' &&
                !{'pumpkin', 'lily', 'pot', 'coffee'}.contains(q.type));
            if (inner.isNotEmpty) {
              target = inner.first;
              break;
            }
          }
        }
        if (!geometry.spriteContains(p, point)) continue;
        target = p;
        break;
      }
      ids = target == null ? {} : {target.id};
    } else {
      ids = stack
          .where((p) => ObjectFilter.matches(p, filter))
          .map((p) => p.id)
          .toSet();
    }
    // A ladder attached to a removed pumpkin disappears with that shell.
    final shells =
        doc.pieces.where((p) => p.type == 'pumpkin' && ids.contains(p.id));
    for (final shell in shells) {
      ids.addAll(doc.pieces
          .where((p) =>
              p.type == 'ladder' && p.row == shell.row && p.col == shell.col)
          .map((p) => p.id));
    }
    return ids;
  }
}
