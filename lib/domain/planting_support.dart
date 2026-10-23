import 'formation.dart';
import 'original_terrain.dart';

/// Placement conflicts and supports belong to the same undoable command.
class PlantingSupport {
  static const potModes = ['roof', 'land', 'ground', 'off'];
  static const aquaticTypes = {'cattail', 'tangle', 'seashroom'};
  static bool isBase(Piece piece) =>
      piece.type == 'lily' || piece.type == 'pot';

  static void removeConflicts(List<Piece> pieces, Piece replacement) {
    pieces.removeWhere((old) {
      if (old.id == replacement.id ||
          old.row != replacement.row ||
          old.col >= replacement.col + replacement.spec.width ||
          replacement.col >= old.col + old.spec.width) return false;
      if (old.type == 'cob' && !isBase(replacement)) return true;
      if (replacement.spec.category != '植物') {
        return old.spec.category == replacement.spec.category &&
            old.layer == replacement.layer;
      }
      if (replacement.type == 'cob' && old.type == 'ladder') return true;
      if (old.spec.category != '植物') return false;
      // Bases and pumpkin shells have separate slots. Cannons cannot be wrapped.
      if (isBase(replacement)) return isBase(old);
      if (isBase(old)) return false;
      // Coffee occupies its own flying slot above the plant and shell.
      if (replacement.type == 'coffee') return old.type == 'coffee';
      if (old.type == 'coffee') return replacement.type == 'cob';
      if (replacement.type == 'pumpkin') {
        return old.type == 'pumpkin' || old.type == 'cob';
      }
      if (replacement.type != 'cob' && old.type == 'pumpkin') return false;
      return true;
    });
  }

  static void removeIncompatibleBases(
      List<Piece> pieces, Piece plant, BoardMap map) {
    if (!aquaticTypes.contains(plant.type)) return;
    pieces.removeWhere((p) =>
        p.type == 'lily' &&
        p.row == plant.row &&
        p.col >= plant.col &&
        p.col < plant.col + plant.spec.width &&
        OriginalTerrain.at(map, p.row, p.col) == 2);
  }

  static void addMissing(List<Piece> pieces, Piece plant, BoardMap map,
      {bool autoLily = true, String potMode = 'roof'}) {
    if (plant.spec.category != '植物' ||
        plant.spec.layer == 0 ||
        plant.type == 'coffee') return;
    removeIncompatibleBases(pieces, plant, map);
    for (var offset = 0; offset < plant.spec.width; offset++) {
      final col = plant.col + offset;
      if (col >= map.columns) continue;
      final terrain = OriginalTerrain.at(map, plant.row, col);
      final aquatic = aquaticTypes.contains(plant.type) ||
          pieces.any((p) =>
              aquaticTypes.contains(p.type) &&
              p.row == plant.row &&
              p.col == col);
      final type = terrain == 2 && autoLily && !aquatic
          ? 'lily'
          : terrain == 1 &&
                  (potMode == 'land' ||
                      potMode == 'roof' && map.roof ||
                      potMode == 'ground' && !map.roof)
              ? 'pot'
              : null;
      if (type == null ||
          pieces.any((p) =>
              p.row == plant.row &&
              p.col == col &&
              (p.type == 'lily' || p.type == 'pot'))) continue;
      pieces.add(Piece(
          id: newId(),
          type: type,
          row: plant.row,
          col: col,
          layer: ObjectSpec.byId(type).layer,
          effects: plant.effects.contains('模仿者') ? {'模仿者'} : {},
          frameRow: type == 'pot' ? 1 : 0));
    }
  }
}
