import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/original_terrain.dart';

void main() {
  // Independent compact golden matrices transcribed from primary ARRAY_TERRAIN
  // with the source's one-based padding row/columns removed. Each digit here
  // expands across a whole row; restricted gardens have explicit cell goldens.
  const rows = {
    'pool': '112211',
    'fog': '112211',
    'day': '11111',
    'night': '11111',
    'roof': '11111',
    'moonRoof': '11111',
    'day6': '111111',
    'night6': '111111',
    'roof6': '111111',
    'moonRoof6': '111111',
    'highland': '111111',
    'day3': '01110',
    'night3': '01110',
    'day1': '00100',
    'night1': '00100',
    'barren': '00000',
    'barrenNight': '00000',
    'greenhouse': '11111',
    'mushroomGarden': '11111',
    'aquarium': '11221',
    'allWater': '222222',
    'flood': '222221',
    'reversal': '221122',
    'fogShimmer': '112211',
  };
  for (final entry in rows.entries) {
    test('source full terrain matrix ${entry.key}', () {
      final map = BoardMap.byId(entry.key);
      expect(map.rows, entry.value.length);
      for (var r = 0; r < map.rows; r++) {
        for (var c = 0; c < map.columns; c++) {
          expect(OriginalTerrain.at(map, r, c), int.parse(entry.value[r]),
              reason: '${entry.key} $r,$c');
        }
      }
    });
  }
  test('restricted mushroom garden exact 45-cell primary matrix', () {
    const golden = [
      [0, 0, 0, 0, 0, 0, 0, 0, 0],
      [0, 0, 0, 1, 1, 1, 0, 0, 0],
      [0, 0, 0, 1, 1, 1, 1, 1, 0],
      [1, 1, 1, 1, 1, 1, 1, 1, 0],
      [1, 1, 1, 1, 1, 1, 1, 0, 0],
    ];
    final map = BoardMap.byId('mushroomGardenRestricted');
    for (var r = 0; r < 5; r++) {
      for (var c = 0; c < 9; c++) {
        expect(OriginalTerrain.at(map, r, c), golden[r][c], reason: '$r,$c');
      }
    }
  });
  test('restricted greenhouse blocks source column five only', () {
    final map = BoardMap.byId('greenhouseRestricted');
    for (var r = 0; r < 5; r++) {
      for (var c = 0; c < 9; c++) {
        expect(OriginalTerrain.at(map, r, c), c == 4 ? 0 : 1, reason: '$r,$c');
      }
    }
  });
  test('only the 26 original maps are available and all have terrain data', () {
    final covered = {
      ...rows.keys,
      'mushroomGardenRestricted',
      'greenhouseRestricted'
    };
    expect(BoardMap.all, hasLength(26));
    expect(BoardMap.all.every((map) => map.originalIndex != null), isTrue);
    expect(covered, BoardMap.all.map((map) => map.id).toSet());
    expect(() => BoardMap.byId('custom'), throwsFormatException);
  });
  test('unknown map terrain is not treated as plantable land', () {
    const map = BoardMap('unknown-map', 'Unknown map', 2, 2);
    for (var row = 0; row < map.rows; row++) {
      for (var col = 0; col < map.columns; col++) {
        expect(OriginalTerrain.at(map, row, col), 0);
      }
    }
  });
  test('negative, out-of-bounds and source-padding cells return bare', () {
    for (final map in BoardMap.all) {
      for (final cell in [
        (-1, 0),
        (0, -1),
        (map.rows, 0),
        (0, map.columns),
        (999999, 999999)
      ]) {
        expect(OriginalTerrain.at(map, cell.$1, cell.$2), 0,
            reason: '${map.id} $cell');
      }
    }
  });
  test('helper never changes existing row metadata or document semantics', () {
    final map = BoardMap.byId('allWater');
    final oldRows = [...map.waterRows],
        doc = Formation(mapId: map.id),
        before = Formation(mapId: map.id).toJson();
    expect(OriginalTerrain.at(map, 0, 0), 2);
    expect(map.waterRows, oldRows);
    expect(doc.toJson(), before);
  });
}
