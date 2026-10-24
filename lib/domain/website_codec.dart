import 'dart:convert';

import 'formation.dart';

/// ArrayDesign interchange, retaining appearance, effects and positioned objects.
class WebsiteCodec {
  static const maxBytes = 8 * 1024 * 1024;
  static const mapIds = [
    'pool',
    'fog',
    'day',
    'night',
    'roof',
    'moonRoof',
    'day6',
    'night6',
    'roof6',
    'moonRoof6',
    'highland',
    'day3',
    'night3',
    'day1',
    'night1',
    'barren',
    'barrenNight',
    'greenhouse',
    'mushroomGarden',
    'aquarium',
    'allWater',
    'flood',
    'reversal',
    'fogShimmer',
    'mushroomGardenRestricted',
    'greenhouseRestricted',
  ];
  static const plantIds = [
    'pea',
    'sunflower',
    'cherry',
    'wallnut',
    'potato',
    'snow',
    'chomper',
    'repeater',
    'puff',
    'sunshroom',
    'fume',
    'gravebuster',
    'hypno',
    'scaredy',
    'ice',
    'doom',
    'lily',
    'squash',
    'threepea',
    'tangle',
    'jalapeno',
    'spikeweed',
    'torch',
    'tallnut',
    'seashroom',
    'plantern',
    'cactus',
    'blover',
    'splitpea',
    'starfruit',
    'pumpkin',
    'magnet',
    'cabbage',
    'pot',
    'kernel',
    'coffee',
    'garlic',
    'umbrella',
    'marigold',
    'melon',
    'gatling',
    'doubleSun',
    'gloom',
    'cattail',
    'winter',
    'goldmagnet',
    'spike',
    'cob',
  ];
  static const extraIds = <int, String>{
    0x30: 'ladder',
    0x31: 'rake',
    0x32: 'grave',
    0x33: 'Stripe',
    0x34: 'crater',
    0x35: 'ScaryPot',
    0x36: 'SnowFlakes',
    0x37: 'BungeeTarget',
    0x38: 'Ice',
    0x50: 'zombie',
    0x52: 'cone',
    0x53: 'pole',
    0x54: 'bucket',
    0x56: 'screen',
    0x57: 'football',
    0x58: 'dancer',
    0x62: 'pogo',
    0x63: 'yeti',
    0x65: 'ladderZombie',
    0x66: 'catapult',
    0x67: 'gargantuar',
    0x68: 'imp',
    0x51: 'flag',
    0x55: 'newspaper',
    0x59: 'backup',
    0x5B: 'snorkel',
    0x5E: 'dolphin',
    0x5F: 'jack',
    0x60: 'balloon',
    0x61: 'digger',
  };
  static String? typeForIndex(int index) =>
      index >= 0 && index < plantIds.length ? plantIds[index] : extraIds[index];
  static int indexForType(String type) => plantIds.contains(type)
      ? plantIds.indexOf(type)
      : extraIds.entries
          .firstWhere(
            (e) => e.value == type,
            orElse: () => const MapEntry(-1, ''),
          )
          .key;
  static String _kind(String type) {
    if (ObjectSpec.byId(type).category == '僵尸') return 'Zombies';
    return switch (type) {
      'lily' || 'pot' => 'Container',
      'pumpkin' => 'Shell',
      'coffee' => 'Addons',
      'ladder' => 'Ladder',
      'rake' => 'Rake',
      'grave' => 'Tombstones',
      'Stripe' ||
      'crater' ||
      'ScaryPot' ||
      'SnowFlakes' ||
      'BungeeTarget' ||
      'Ice' =>
        'Prop:$type',
      _ => 'Plant',
    };
  }

  static List<String> exportIssues(Formation formation) {
    final issues = <String>[];
    if (formation.fogColumns != 0) issues.add('原站阵型字符串不能表达自定义雾列数');
    if (formation.seedSlots.isNotEmpty) issues.add('原站阵型字符串不能表达自定义卡槽');
    if (!mapIds.contains(formation.mapId)) issues.add('此地图没有原站地图编号');
    if (formation.pieces.length > 5000) issues.add('对象数量超过 5000');
    if (formation.sunValue != 9990) issues.add('已验证原站字符串不能表达自定义阳光数值');
    final defaults = Formation().display;
    if (formation.display.length != defaults.length ||
        defaults.entries.any((e) => formation.display[e.key] != e.value)) {
      issues.add('原站已验证字符串不能表达当前显示设置，请恢复默认显示设置');
    }
    final occupied = <String>{};
    for (final p in formation.pieces) {
      final label = '${p.type}（${p.row + 1},${p.col + 1}）';
      if (indexForType(p.type) < 0) {
        issues.add('$label：尚未验证此对象类型');
        continue;
      }
      final spec = ObjectSpec.byId(p.type);
      if (!formation.fits(p, formation.map)) issues.add('$label：对象越界');
      if (p.asleep && !Piece.mushroomTypes.contains(p.type)) {
        issues.add('$label：此对象不支持睡眠状态');
      }
      if (p.appearance != '默认') issues.add('$label：非默认外表尚未验证');
      if (p.scale != 1) issues.add('$label：缩放字段尚未验证');
      if (![.5, 1].contains(p.opacity)) issues.add('$label：此透明度的原站字段尚未验证');
      if (p.flippedVertical) issues.add('$label：垂直翻转字段尚未验证');
      if (p.layer != spec.layer) issues.add('$label：自定义图层不能表示');
      if (p.effects.any((e) => !Piece.allowedEffects.contains(e))) {
        issues.add('$label：此效果没有原站对应位');
      }
      final slot = '${p.row}:${p.col}:${_kind(p.type)}';
      if (spec.category != '僵尸' && !occupied.add(slot)) {
        issues.add('$label：同格同类别 ${_kind(p.type)} 重叠无法保留');
      }
    }
    return issues;
  }

  static String encode(Formation formation) {
    final issues = exportIssues(formation);
    if (issues.isNotEmpty) throw FormatException(issues.join('\n'));
    final out = StringBuffer('${mapIds.indexOf(formation.mapId)}');
    for (final p in formation.pieces) {
      final hex = indexForType(p.type).toRadixString(16).toUpperCase();
      final raw = p.websiteFields;
      final originalPositionMatches = raw != null &&
          raw.length >= 6 &&
          num.tryParse(raw[1]) == p.row + 1 &&
          num.tryParse(raw[2]) == p.col + 1;
      final fields =
          originalPositionMatches ? raw.skip(6).toList() : <String>['1'];
      if (fields.isEmpty) fields.add('1');
      // Current Save format uses [opacity, side, ...position]. Legacy preset
      // records omit opacity and start their suffix with a zero placeholder.
      if (fields.first == '0' &&
          (p.effects.contains('半透明') || p.opacity == .5)) {
        fields.insert(0, '0.5');
      }
      final currentFormat = num.tryParse(fields.first) != null &&
          num.parse(fields.first) > 0 &&
          num.parse(fields.first) <= 1;
      if (currentFormat) {
        fields[0] = (p.effects.contains('半透明') ? .5 : p.opacity)
            .toString()
            .replaceFirst(RegExp(r'\.0$'), '');
      }
      if (currentFormat) {
        if (fields.length > 1) {
          fields[1] = p.flipped ? '1' : '0';
        } else if (p.flipped) {
          fields.add('1');
        }
        if (!p.flipped && fields.length == 2) fields.removeLast();
      } else if (p.flipped) {
        fields[0] = '1';
        fields.insert(1, '1');
      }
      if (p.spec.category == '僵尸') {
        // Current ArrayDesign expects opacity, side, then an explicit X.
        // Without X its zombie loader uses the current mouse position.
        final x = p.websitePixelX ?? (40 + (p.col + .5) * 80);
        fields
          ..clear()
          ..addAll([
            (p.effects.contains('半透明') ? .5 : p.opacity).toString(),
            p.flipped ? '1' : '0',
            x.toString(),
            if (p.websitePixelY != null) p.websitePixelY.toString(),
          ]);
      }

      final rawEffects = Piece.decodeWebsiteEffects(p.websiteEffects);
      final grayEffects = p.effects.difference({'半透明'});
      final effect = rawEffects.length == grayEffects.length &&
              rawEffects.containsAll(grayEffects)
          ? p.websiteEffects
          : Piece.encodeWebsiteEffects(p.effects);
      out.write(
        ',$hex ${p.row + 1} ${p.col + 1} ${p.frameRow} ${p.frameCol} $effect ${fields.join(' ')} ',
      );
    }
    final result = out.toString();
    if (utf8.encode(result).length > maxBytes) {
      throw const FormatException('原站字符串超过 8 MiB');
    }
    return result;
  }

  static Formation decode(String source) {
    if (utf8.encode(source).length > maxBytes) {
      throw const FormatException('原站字符串超过 8 MiB');
    }
    final records = source.trim().split(',');
    if (records.length > 5001) throw const FormatException('原站对象超过 5000 条');
    final mapToken = records.first.trim();
    if (!RegExp(r'^\d{1,2}$').hasMatch(mapToken) ||
        int.parse(mapToken) >= mapIds.length) {
      throw const FormatException('原站地图编号应在0–25之间');
    }
    final map = BoardMap.byId(mapIds[int.parse(mapToken)]);
    final pieces = <Piece>[];
    final occupied = <String>{};
    for (var index = 1; index < records.length; index++) {
      final tokens = records[index].trim().split(RegExp(r'\s+'));
      if (tokens.length < 6 || tokens.length > 11) {
        throw FormatException('第 $index 条：字段数量必须在6到11之间');
      }
      if (!RegExp(r'^[0-9a-fA-F]{1,2}$').hasMatch(tokens[0])) {
        throw FormatException('第 $index 条：植物 ID 不是已验证的十六进制数');
      }
      final typeIndex = int.parse(tokens[0], radix: 16);
      if (typeForIndex(typeIndex) == null) {
        throw FormatException('第 $index 条：未知植物 ID ${tokens[0]}');
      }
      if (tokens
          .asMap()
          .entries
          .where((e) => e.key != 0 && e.key != 5)
          .any((e) => !RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(e.value))) {
        throw FormatException('第 $index 条：字段必须为数值');
      }
      final numbers = tokens.skip(1).map((t) => num.tryParse(t) ?? 0).toList();
      if (numbers.take(4).any((n) => n != n.toInt()) ||
          numbers[2] < 0 ||
          numbers[3] < 0 ||
          numbers[2] > 32 ||
          numbers[3] > 32) {
        throw FormatException('第 $index 条：坐标和外表帧必须为有效整数');
      }
      if (!Piece.validWebsiteEffects(tokens[5])) {
        throw FormatException('第 $index 条：效果必须为至多七位二进制字符串');
      }
      if (tokens.length >= 7 && (numbers[5] < 0 || numbers[5] > 1)) {
        throw FormatException('第 $index 条：第七字段仅验证默认值 1');
      }
      final spec = ObjectSpec.byId(typeForIndex(typeIndex)!);
      final legacyZombieX = spec.category == '僵尸' &&
          tokens.length == 8 &&
          !{'0', '1', '2', '3'}.contains(tokens[7]);
      final currentFormat = tokens.length >= 7 &&
          numbers[5] > 0 &&
          numbers[5] <= 1 &&
          !legacyZombieX;
      if (currentFormat &&
          tokens.length >= 8 &&
          tokens[7] != '0' &&
          tokens[7] != '1') {
        throw FormatException('第 $index 条：翻转字段仅验证0或1');
      }
      final row = numbers[0].toInt() - 1, col = numbers[1].toInt() - 1;
      if (row < 0 ||
          row >= map.rows ||
          col < 0 ||
          col + spec.width > map.columns) {
        throw FormatException('第 $index 条：坐标或占格越界');
      }
      if (spec.category != '僵尸' &&
          !occupied.add('$row:$col:${_kind(spec.id)}')) {
        throw FormatException('第 $index 条：同格同类别重叠，无法无损导入');
      }
      pieces.add(
        Piece(
          id: newId(),
          type: spec.id,
          row: row,
          col: col,
          layer: spec.layer,
          flipped: currentFormat && tokens.length >= 8 && tokens[7] == '1' ||
              !currentFormat &&
                  spec.category == '僵尸' &&
                  tokens.length >= 8 &&
                  tokens[6] == '1',
          frameRow: numbers[2].toInt(),
          frameCol: numbers[3].toInt(),
          websiteEffects: tokens[5],
          websiteFields: List.unmodifiable(tokens),
          opacity: currentFormat ? numbers[5].toDouble() : 1,
          effects: {
            ...Piece.decodeWebsiteEffects(tokens[5]),
            if (currentFormat && numbers[5] == .5) '半透明',
          },
        ),
      );
    }
    return Formation(mapId: map.id, pieces: pieces);
  }
}
