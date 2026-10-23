import 'formation.dart';
import 'formation_exchange.dart';
import 'toolkit_codec.dart';
import 'website_codec.dart';

/// Explicit, lossy conversion for export. Callers keep the source in undo history.
class FormationFormatter {
  static const _sleepers = {8, 9, 10, 12, 13, 14, 15, 24, 31, 42};

  static Formation format(Formation source,
      {FormationFormat format = FormationFormat.toolkit}) {
    if (format == FormationFormat.project) return source;
    final toolkit = format == FormationFormat.toolkit;
    final mapId = toolkit
        ? _originalMap(source.mapId)
        : WebsiteCodec.mapIds.contains(source.mapId)
            ? source.mapId
            : _originalMap(source.mapId);
    final map = BoardMap.byId(mapId);
    final scene = ToolkitCodec.maps.indexOf(mapId);
    final kept = <Piece>[];
    for (final original in source.pieces) {
      final index = WebsiteCodec.plantIds.indexOf(original.type);
      if (toolkit
          ? index < 0 && !{'grave', 'ladder', 'rake'}.contains(original.type)
          : WebsiteCodec.indexForType(original.type) < 0) {
        continue;
      }
      // Reject invalid candidates before they can evict a valid older object.
      if (!source.fits(original, map)) continue;
      if (toolkit &&
          original.type == 'rake' &&
          (original.col != 7 ||
              ({2, 3}.contains(scene) && {2, 3}.contains(original.row)))) {
        continue;
      }
      final effects = toolkit
          ? <String>{if (index >= 0 && original.effects.contains('模仿者')) '模仿者'}
          : original.effects.where(Piece.allowedEffects.contains).toSet();
      final candidate = Piece(
        id: original.id,
        type: original.type,
        row: original.row,
        col: original.col,
        layer: original.spec.layer,
        asleep: toolkit &&
            original.asleep &&
            _sleepers.contains(index) &&
            {0, 2, 4}.contains(scene),
        effects: effects,
        websiteEffects: Piece.encodeWebsiteEffects(effects),
        opacity: toolkit
            ? 1
            : original.opacity == .5
                ? .5
                : 1,
        flipped: !toolkit && original.flipped,
        frameRow: toolkit ? 0 : original.frameRow,
        frameCol: toolkit ? 0 : original.frameCol,
      );
      kept.removeWhere((p) => _conflicts(p, candidate, toolkit));
      kept.add(candidate);
    }
    return Formation(mapId: mapId, pieces: kept);
  }

  static String _originalMap(String id) {
    if (ToolkitCodec.maps.contains(id)) return id;
    if (id == 'fogShimmer') return 'fog';
    if (id == 'moonRoof6') return 'moonRoof';
    if (id == 'roof6') return 'roof';
    if (id.startsWith('night') ||
        id == 'barrenNight' ||
        id.startsWith('mushroomGarden')) return 'night';
    if ({'aquarium', 'allWater', 'flood', 'reversal'}.contains(id)) {
      return 'pool';
    }
    return 'day';
  }

  static String _slot(Piece p, bool toolkit) {
    if ({'lily', 'pot'}.contains(p.type) || toolkit && p.type == 'grave') {
      return 'base';
    }
    if ({'pumpkin', 'coffee', 'ladder', 'rake', 'grave'}.contains(p.type)) {
      return p.type;
    }
    if (!toolkit) {
      if (p.spec.category == '僵尸') return 'zombie';
      if ({'Stripe', 'crater', 'ScaryPot', 'SnowFlakes', 'BungeeTarget', 'Ice'}
          .contains(p.type)) {
        return p.type;
      }
    }
    return 'main';
  }

  static bool _conflicts(Piece older, Piece newer, bool toolkit) {
    if (toolkit && older.type == 'rake' && newer.type == 'rake') return true;
    if (older.row != newer.row ||
        older.col >= newer.col + newer.spec.width ||
        newer.col >= older.col + older.spec.width) return false;
    final a = _slot(older, toolkit), b = _slot(newer, toolkit);
    if (a == b) return true;
    // Cannons occupy both cells; a pumpkin cannot coexist with either half.
    return (older.type == 'cob' && b == 'pumpkin') ||
        (newer.type == 'cob' && a == 'pumpkin');
  }
}
