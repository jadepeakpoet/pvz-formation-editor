import 'formation.dart';

/// Source ArrayDesign terrain for planting feedback and automatic supports.
/// 0 = bare/blocked; 1 = land; 2 = water. Coordinates are zero-based.
/// Derived from public main.js ARRAY_TERRAIN and the HTML lMap option values:
/// http://jspvz.com/ArrayDesign/main.js and http://jspvz.com/ArrayDesign/.
/// Does not reject placement or change BoardMap metadata.
class OriginalTerrain {
  static const _land = '111111111';
  static const _water = '222222222';
  static const _bare = '000000000';
  static const _fiveLand = [_land, _land, _land, _land, _land];
  static const _sixLand = [_land, _land, _land, _land, _land, _land];
  static const _pool = [_land, _land, _water, _water, _land, _land];
  static const _three = [_bare, _land, _land, _land, _bare];
  static const _one = [_bare, _bare, _land, _bare, _bare];
  static const _empty = [_bare, _bare, _bare, _bare, _bare];
  static const _source = <String, List<String>>{
    'pool': _pool,
    'fog': _pool,
    'day': _fiveLand,
    'night': _fiveLand,
    'roof': _fiveLand,
    'moonRoof': _fiveLand,
    'day6': _sixLand,
    'night6': _sixLand,
    'roof6': _sixLand,
    'moonRoof6': _sixLand,
    'highland': _sixLand,
    'day3': _three,
    'night3': _three,
    'day1': _one,
    'night1': _one,
    'barren': _empty,
    'barrenNight': _empty,
    'greenhouse': _fiveLand,
    'mushroomGarden': _fiveLand,
    'aquarium': [_land, _land, _water, _water, _land],
    'allWater': [_water, _water, _water, _water, _water, _water],
    'flood': [_water, _water, _water, _water, _water, _land],
    'reversal': [_water, _water, _land, _land, _water, _water],
    'fogShimmer': _pool,
    'mushroomGardenRestricted': [
      '000000000',
      '000111000',
      '000111110',
      '111111110',
      '111111100',
    ],
    'greenhouseRestricted': [
      '111101111',
      '111101111',
      '111101111',
      '111101111',
      '111101111',
    ],
  };

  static int at(BoardMap map, int row, int col) {
    if (row < 0 || row >= map.rows || col < 0 || col >= map.columns) return 0;
    final matrix = _source[map.id];
    // App-only custom boards have no source terrain restrictions.
    if (matrix == null) return 1;
    if (row >= matrix.length || col >= matrix[row].length) return 0;
    return matrix[row].codeUnitAt(col) - 48;
  }
}
