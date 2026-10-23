import 'dart:math';
import 'formation.dart';
import 'original_terrain.dart';

/// Toolbox operations are returned as one document so the editor can undo them.
class OriginalActions {
  static const labels = ['花盆', '荷叶', '智能搭梯', '搭梯', '碾花盆', '炸荷叶', '破南瓜'];

  static Formation apply(Formation base, String action, {Random? random}) {
    final frameRandom = random ?? Random();
    final out = List<Piece>.of(base.pieces);
    if (action == '花盆' || action == '荷叶') {
      final type = action == '花盆' ? 'pot' : 'lily';
      final spec = ObjectSpec.byId(type);
      // The original fills supports underneath planted objects, never empty cells.
      final occupied = <(int, int)>{
        for (final plant in base.pieces.where((p) =>
            p.spec.category == '植物' &&
            (p.spec.layer == 10 || p.type == 'pumpkin')))
          for (var offset = 0; offset < (plant.type == 'cob' ? 2 : 1); offset++)
            if (plant.col + offset < base.map.columns)
              (plant.row, plant.col + offset),
      };
      for (final cell in occupied) {
        final water = base.map.waterRows.contains(cell.$1);
        if ((type == 'lily') != water) continue;
        final index = out.indexWhere(
            (p) => p.type == type && p.row == cell.$1 && p.col == cell.$2);
        final support = index < 0
            ? Piece(
                id: newId(),
                type: type,
                row: cell.$1,
                col: cell.$2,
                layer: spec.layer)
            : out[index];
        final updated = support.copy(
            frameRow: type == 'pot' ? 1 : 0,
            frameCol: frameRandom.nextInt(type == 'pot' ? 2 : 3));
        if (index < 0) {
          out.add(updated);
        } else {
          out[index] = updated;
        }
      }
    } else if (action == '智能搭梯') {
      final targets = {
        for (final shell in base.pieces)
          if (shell.type == 'pumpkin' &&
              shell.effects.contains('模仿者') &&
              OriginalTerrain.at(base.map, shell.row, shell.col) == 1)
            (shell.row, shell.col),
      };
      final covered = <(int, int)>{};
      out.removeWhere((piece) =>
          piece.type == 'ladder' &&
          (!targets.contains((piece.row, piece.col)) ||
              !covered.add((piece.row, piece.col))));
      for (final cell in targets.difference(covered)) {
        out.add(Piece(
            id: newId(),
            type: 'ladder',
            row: cell.$1,
            col: cell.$2,
            layer: ObjectSpec.byId('ladder').layer));
      }
    } else if (action == '搭梯') {
      for (final plant in base.pieces
          .where((p) => p.type == 'wallnut' || p.type == 'tallnut')) {
        if (!base.pieces.any((p) =>
            p.type == 'pumpkin' && p.row == plant.row && p.col == plant.col)) {
          continue;
        }
        if (out.any((p) =>
            p.type == 'ladder' && p.row == plant.row && p.col == plant.col)) {
          continue;
        }
        out.add(Piece(
            id: newId(),
            type: 'ladder',
            row: plant.row,
            col: plant.col,
            layer: ObjectSpec.byId('ladder').layer));
      }
    } else if (action == '碾花盆' || action == '炸荷叶') {
      // Browser probes confirm these preserve supports and their saved frames.
    } else if (action == '破南瓜') {
      for (var i = 0; i < out.length; i++) {
        if (out[i].type == 'pumpkin') out[i] = out[i].copy(frameRow: 2);
      }
    } else {
      throw ArgumentError.value(action, 'action', '未知快捷操作');
    }
    if (out.length > 5000) throw const FormatException('对象超过5000个');
    return base.copy(pieces: out);
  }

  static Formation imitate(Formation base, String scope) => base.copy(
          pieces: base.pieces.map((p) {
        final matches = switch (scope) {
          '南瓜' => p.type == 'pumpkin',
          '荷叶' => p.type == 'lily',
          '花盆' => p.type == 'pot',
          '非紫卡植物' => p.spec.category == '植物' &&
              !const {
                'gatling',
                'doubleSun',
                'gloom',
                'cattail',
                'winter',
                'goldmagnet',
                'spike',
                'cob'
              }.contains(p.type),
          '全部植物' => p.spec.category == '植物',
          _ => false,
        };
        return matches ? p.copy(effects: {...p.effects, '模仿者'}) : p;
      }).toList());
}

/// Presets observed on the original pool map. Other maps use their declared
/// land/water rows; their original-site selections are not yet verified.
class OriginalSelection {
  static Set<(int, int)> cells(BoardMap map, String label) {
    final water = label == '水路' || label.startsWith('水路');
    final column = switch (label) {
      '后置炮' => 3,
      '前置炮' => 4,
      '超前置炮' => 6,
      '底线炮' => 0,
      _ => null,
    };
    if (!const ['全部', '陆路', '水路', '后置炮', '前置炮', '超前置炮', '底线炮', '水路前场', '水路56列']
        .contains(label)) {
      throw ArgumentError.value(label, 'label', '未知选择预设');
    }
    return {
      for (var row = 0; row < map.rows; row++)
        if (label == '全部' || map.waterRows.contains(row) == water)
          for (var col = 0; col < map.columns; col++)
            if ((column == null || col == column) &&
                (label != '水路前场' || (col >= 6 && col <= 8)) &&
                (label != '水路56列' || (col >= 4 && col <= 5)))
              (row, col),
    };
  }
}

/// Local examples, not copies of unverified website formations.
class LocalLayouts {
  static const stamps = <String, List<(String, int, int)>>{
    '双炮单元': [
      ('cob', 0, 0),
      ('cob', 1, 0),
      ('pumpkin', 0, 0),
      ('pumpkin', 1, 0)
    ],
    '水路保护单元': [
      ('lily', 0, 0),
      ('gloom', 0, 0),
      ('pumpkin', 0, 0),
      ('lily', 1, 0),
      ('cattail', 1, 0)
    ],
    '向日葵双列': [
      ('sunflower', 0, 0),
      ('sunflower', 0, 1),
      ('sunflower', 1, 0),
      ('sunflower', 1, 1)
    ],
  };
  static Formation apply(Formation base, String name, int row, int col) {
    final pattern = stamps[name];
    if (pattern == null) throw ArgumentError('未知局部布局');
    final additions = pattern
        .map((e) => Piece(
            id: newId(),
            type: e.$1,
            row: row + e.$2,
            col: col + e.$3,
            layer: ObjectSpec.byId(e.$1).layer))
        .toList();
    if (additions.any((p) => !base.fits(p, base.map))) {
      throw const FormatException('布局越界，请选择更靠左上的格子');
    }
    if (base.pieces.length + additions.length > 5000) {
      throw const FormatException('对象超过 5000 个');
    }
    return base.copy(pieces: [...base.pieces, ...additions]);
  }
}
