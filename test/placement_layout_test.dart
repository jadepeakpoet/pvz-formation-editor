import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/domain/placement_layout.dart';
import 'package:pvz_formation_editor/domain/plant_game_state.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';

void main() {
  test('all 363 presets export a Toolkit layout without editing the source', () {
    for (final preset in LibraryPresets.all) {
      final before = preset.document.fingerprint;
      final layout = PlacementLayout.prepare(preset.document);
      final restored = FormationExchange.decode(
          FormationExchange.encode(preset.document));
      expect(restored.pieces.length, layout.document.pieces.length,
          reason: preset.id);
      expect(preset.document.fingerprint, before);
    }
  });
  for (final (index, skipped, styled) in [(59, 1, 1), (81, 6, 0), (303, 2, 0)]) {
    test('preset $index reports omitted objects and keeps the complete project', () {
      final original = LibraryPresets.all[index].document;
      final layout = PlacementLayout.prepare(original);
      expect(layout.skippedObjects, skipped);
      expect(layout.simplifiedAppearances, styled);
      expect(layout.notice, isNotEmpty);
      expect(layout.document.pieces.length, original.pieces.length - skipped);
      expect(FormationExchange.decode(FormationExchange.encode(original,
          format: FormationFormat.project)).fingerprint, original.fingerprint);
      expect(FormationExchange.decode(FormationExchange.encode(original,
          format: FormationFormat.website)).pieces.length, original.pieces.length);
    });
  }
  test('styling normalization preserves final mushroom and stable plant states', () {
    final pieces = [
      Piece(id: 'sleep', type: 'fume', row: 0, col: 0, layer: 10,
          frameRow: 0, effects: {'高亮', '模仿者'}),
      Piece(id: 'awake', type: 'magnet', row: 0, col: 1, layer: 10,
          frameRow: 1, scale: 2),
      Piece(id: 'cob', type: 'cob', row: 1, col: 0, layer: 10,
          frameCol: 2, opacity: .5),
      Piece(id: 'nut', type: 'wallnut', row: 2, col: 0, layer: 10,
          frameCol: 3, flipped: true),
    ];
    final layout = PlacementLayout.prepare(Formation(pieces: pieces));
    for (var i = 0; i < pieces.length; i++) {
      expect(layout.document.pieces[i].asleep, pieces[i].asleep);
      expect(PlantGameState.of(layout.document.pieces[i]),
          PlantGameState.of(pieces[i]));
    }
    expect(layout.document.pieces.first.effects, {'模仿者'});
    expect(layout.simplifiedAppearances, 4);
  });
  test('ordinary layouts retain identity and unknown objects remain errors', () {
    final original = Formation();
    expect(identical(PlacementLayout.prepare(original).document, original), isTrue);
    final unknown = Formation(pieces: [
      Piece(id: 'unknown', type: 'future-custom-plant', row: 0, col: 0, layer: 10),
    ]);
    expect(PlacementLayout.prepare(unknown).skippedObjects, 0);
    expect(() => FormationExchange.exportIssues(unknown), throwsFormatException);
  });
}
