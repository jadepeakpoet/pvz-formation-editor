import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/plant_game_state.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';

Piece plant(String type, int row, int col) => Piece(
    id: type,
    type: type,
    row: 0,
    col: 0,
    layer: ObjectSpec.byId(type).layer,
    frameRow: row,
    frameCol: col);
void main() {
  test('cob brightness shares ready state; empty cannon differs', () {
    expect(PlantGameState.of(plant('cob', 0, 0)), 0);
    expect(PlantGameState.of(plant('cob', 0, 1)), 0);
    expect(PlantGameState.of(plant('cob', 0, 2)), 1);
  });
  test('stable appearances select growth, height and damage without defaults',
      () {
    for (final values in [
      ('potato', 0, 0, 0),
      ('potato', 0, 1, 1),
      ('potato', 0, 2, 1),
      ('sunshroom', 1, 0, 0),
      ('sunshroom', 1, 2, 1),
      ('cactus', 0, 0, 0),
      ('cactus', 2, 0, 1),
      ('wallnut', 0, 0, 0),
      ('wallnut', 0, 2, 1),
      ('wallnut', 0, 3, 2),
      ('tallnut', 0, 2, 2),
      ('spike', 0, 1, 1),
      ('garlic', 0, 2, 2)
    ]) {
      final p = plant(values.$1, values.$2, values.$3);
      expect(PlantGameState.of(p), values.$4);
      expect(PlantGameState.of(Piece.fromJson(p.toJson())), values.$4);
    }
  });
  test('all plant appearances survive project copies and website round trips',
      () {
    for (final type in WebsiteCodec.plantIds) {
      final p = plant(type, 1, 1);
      final saved = Piece.fromJson(p.copy(col: 1).toJson());
      expect((saved.frameRow, saved.frameCol), (1, 1), reason: type);
      final document = Formation(pieces: [saved]);
      final loaded =
          WebsiteCodec.decode(WebsiteCodec.encode(document)).pieces.single;
      expect((loaded.frameRow, loaded.frameCol), (1, 1), reason: type);
    }
  });
}
