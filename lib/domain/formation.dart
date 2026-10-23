import 'dart:convert';
import 'dart:math';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random.secure().nextInt(0x7fffffff).toRadixString(36)}';

class BoardMap {
  final String id, name;
  final int rows, columns;
  final bool roof;

  /// False where the original coordinate system needs further visual verification.
  final bool geometryVerified;
  final int? originalIndex;
  final String? background;
  final List<int> waterRows;

  /// Zero-based logical plant rows on partially sodded original maps.
  final List<int>? activePlantRows;
  const BoardMap(this.id, this.name, this.rows, this.columns,
      {this.roof = false,
      this.waterRows = const [],
      this.activePlantRows,
      this.geometryVerified = true,
      this.originalIndex,
      this.background});
  static const all = [
    BoardMap('pool', '白天泳池', 6, 9,
        originalIndex: 0, background: 'background3.png', waterRows: [2, 3]),
    BoardMap('fog', '夜晚泳池', 6, 9,
        originalIndex: 1, background: 'background4.png', waterRows: [2, 3]),
    BoardMap('day', '白天草地', 5, 9,
        originalIndex: 2, background: 'background1.jpg'),
    BoardMap('night', '夜晚草地', 5, 9,
        originalIndex: 3, background: 'background2.jpg'),
    BoardMap('roof', '白天屋顶', 5, 9,
        originalIndex: 4, background: 'background5.jpg', roof: true),
    BoardMap('moonRoof', '夜晚屋顶', 5, 9,
        originalIndex: 5, background: 'background6boss.jpg', roof: true),
    BoardMap('day6', '白天六行草地', 6, 9,
        originalIndex: 6, background: 'D6E.jpg', geometryVerified: false),
    BoardMap('night6', '夜晚六行草地', 6, 9,
        originalIndex: 7, background: 'N6E.jpg', geometryVerified: false),
    BoardMap('roof6', '白天六行屋顶', 6, 9,
        originalIndex: 8,
        background: 'R6E.jpg',
        roof: true,
        geometryVerified: false),
    BoardMap('moonRoof6', '夜晚六行屋顶', 6, 9,
        originalIndex: 9,
        background: 'M6E.jpg',
        roof: true,
        geometryVerified: false),
    BoardMap('highland', '高地', 6, 9,
        originalIndex: 10, background: 'highland.gif', geometryVerified: false),
    BoardMap('day3', '三行草地', 5, 9,
        originalIndex: 11,
        background: 'background1unsodded2.jpg',
        geometryVerified: false,
        activePlantRows: [1, 2, 3]),
    BoardMap('night3', '三行草地(夜晚)', 5, 9,
        originalIndex: 12,
        background: 'N3E.jpg',
        geometryVerified: false,
        activePlantRows: [1, 2, 3]),
    BoardMap('day1', '单行草地', 5, 9,
        originalIndex: 13,
        background: 'background1unsodded_1.jpg',
        geometryVerified: false,
        activePlantRows: [2]),
    BoardMap('night1', '单行草地(夜晚)', 5, 9,
        originalIndex: 14,
        background: 'N1E.jpg',
        geometryVerified: false,
        activePlantRows: [2]),
    BoardMap('barren', '荒芜草地', 5, 9,
        originalIndex: 15,
        background: 'background1unsodded.jpg',
        geometryVerified: false),
    BoardMap('barrenNight', '荒芜草地(夜晚)', 5, 9,
        originalIndex: 16, background: 'N0E.jpg', geometryVerified: false),
    BoardMap('greenhouse', '温室花园', 5, 9,
        originalIndex: 17,
        background: 'Background_Greenhouse.jpg',
        geometryVerified: false),
    BoardMap('mushroomGarden', '蘑菇园', 5, 9,
        originalIndex: 18,
        background: 'Background_MushroomGarden.jpg',
        geometryVerified: false),
    BoardMap('aquarium', '水族馆', 5, 9,
        originalIndex: 19,
        background: 'aquarium1.jpg',
        geometryVerified: false),
    BoardMap('allWater', '全水路', 6, 9,
        originalIndex: 20,
        background: 'background7.jpg',
        geometryVerified: false),
    BoardMap('flood', '洪水', 6, 9,
        originalIndex: 21,
        background: 'background8.jpg',
        geometryVerified: false),
    BoardMap('reversal', '水路反转', 6, 9,
        originalIndex: 22,
        background: 'background9.jpg',
        geometryVerified: false),
    BoardMap('fogShimmer', '订制夜晚泳池(波光)', 6, 9,
        originalIndex: 23,
        background: 'background10.png',
        waterRows: [2, 3],
        geometryVerified: false),
    BoardMap('mushroomGardenRestricted', '订制蘑菇园(背景蘑菇处不能种植)', 5, 9,
        originalIndex: 24,
        background: 'Background_MushroomGarden.jpg',
        geometryVerified: false),
    BoardMap('greenhouseRestricted', '订制温室花园(中间列不能种植)', 5, 9,
        originalIndex: 25,
        background: 'Background_Greenhouse.jpg',
        geometryVerified: false),
    BoardMap('custom', '自由棋盘', 8, 12),
  ];
  static BoardMap byId(String id) => all.firstWhere((m) => m.id == id,
      orElse: () => throw FormatException('未知地图：$id'));
}

class ObjectSpec {
  final String id, name, category;
  final int layer, width;
  final int color;
  const ObjectSpec(this.id, this.name, this.category, this.layer, this.color,
      {this.width = 1});
  static const all = [
    ObjectSpec('lily', '睡莲', '植物', 0, 0xff63ab58),
    ObjectSpec('pot', '花盆', '植物', 0, 0xffbf7952),
    ObjectSpec('pea', '豌豆射手', '植物', 10, 0xff76bf53),
    ObjectSpec('sunflower', '向日葵', '植物', 10, 0xffefbb43),
    ObjectSpec('doubleSun', '双子向日葵', '植物', 10, 0xffe7a839),
    ObjectSpec('repeater', '双发射手', '植物', 10, 0xff4d9d54),
    ObjectSpec('gatling', '机枪射手', '植物', 10, 0xff458447),
    ObjectSpec('snow', '寒冰射手', '植物', 10, 0xff80c9df),
    ObjectSpec('wallnut', '坚果墙', '植物', 10, 0xffb98c50),
    ObjectSpec('tallnut', '高坚果', '植物', 10, 0xff9f713f),
    ObjectSpec('pumpkin', '南瓜头', '植物', 20, 0xffdf8a39),
    ObjectSpec('coffee', '咖啡豆', '植物', 30, 0xff8e6545),
    ObjectSpec('cob', '玉米加农炮', '植物', 10, 0xffd7bc55, width: 2),
    ObjectSpec('gloom', '忧郁菇', '植物', 10, 0xff9672b8),
    ObjectSpec('fume', '大喷菇', '植物', 10, 0xffa97cc4),
    ObjectSpec('ice', '寒冰菇', '植物', 10, 0xffb1d9e6),
    ObjectSpec('doom', '毁灭菇', '植物', 10, 0xff74598b),
    ObjectSpec('cattail', '香蒲', '植物', 10, 0xffd39d63),
    ObjectSpec('umbrella', '叶子保护伞', '植物', 10, 0xff75b568),
    ObjectSpec('spike', '地刺王', '植物', 10, 0xff8e9694),
    ObjectSpec('garlic', '大蒜', '植物', 10, 0xffe5dfc8),
    ObjectSpec('melon', '西瓜投手', '植物', 10, 0xff64a86d),
    ObjectSpec('winter', '冰瓜', '植物', 10, 0xff78bcc6),
    ObjectSpec('cherry', '樱桃炸弹', '植物', 10, 0xff83af69),
    ObjectSpec('potato', '土豆雷', '植物', 10, 0xff83af69),
    ObjectSpec('chomper', '大嘴花', '植物', 10, 0xff83af69),
    ObjectSpec('puff', '小喷菇', '植物', 10, 0xff83af69),
    ObjectSpec('sunshroom', '阳光菇', '植物', 10, 0xff83af69),
    ObjectSpec('gravebuster', '墓碑吞噬者', '植物', 10, 0xff83af69),
    ObjectSpec('hypno', '魅惑菇', '植物', 10, 0xff83af69),
    ObjectSpec('scaredy', '胆小菇', '植物', 10, 0xff83af69),
    ObjectSpec('squash', '窝瓜', '植物', 10, 0xff83af69),
    ObjectSpec('threepea', '三线射手', '植物', 10, 0xff83af69),
    ObjectSpec('tangle', '缠绕海草', '植物', 10, 0xff83af69),
    ObjectSpec('jalapeno', '火爆辣椒', '植物', 10, 0xff83af69),
    ObjectSpec('spikeweed', '地刺', '植物', 10, 0xff83af69),
    ObjectSpec('torch', '火炬树桩', '植物', 10, 0xff83af69),
    ObjectSpec('seashroom', '海蘑菇', '植物', 10, 0xff83af69),
    ObjectSpec('plantern', '路灯花', '植物', 10, 0xff83af69),
    ObjectSpec('cactus', '仙人掌', '植物', 10, 0xff83af69),
    ObjectSpec('blover', '三叶草', '植物', 10, 0xff83af69),
    ObjectSpec('splitpea', '裂荚射手', '植物', 10, 0xff83af69),
    ObjectSpec('starfruit', '杨桃', '植物', 10, 0xff83af69),
    ObjectSpec('magnet', '磁力菇', '植物', 10, 0xff83af69),
    ObjectSpec('cabbage', '卷心菜投手', '植物', 10, 0xff83af69),
    ObjectSpec('kernel', '玉米投手', '植物', 10, 0xff83af69),
    ObjectSpec('goldmagnet', '吸金磁', '植物', 10, 0xff83af69),
    ObjectSpec('marigold', '金盏花', '植物', 10, 0xff83af69),
    ObjectSpec('zombie', '普通僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('cone', '路障僵尸', '僵尸', 40, 0xffbd965a),
    ObjectSpec('bucket', '铁桶僵尸', '僵尸', 40, 0xff87969d),
    ObjectSpec('gargantuar', '巨人僵尸', '僵尸', 40, 0xff748169),
    ObjectSpec('flag', '旗帜僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('pole', '撑杆僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('newspaper', '读报僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('screen', '铁门僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('football', '橄榄球僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('dancer', '舞王僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('backup', '伴舞僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('ducky', '鸭子救生圈僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('snorkel', '潜水僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('zomboni', '冰车僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('bobsled', '雪橇僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('dolphin', '海豚骑士僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('jack', '玩偶匣僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('balloon', '气球僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('digger', '矿工僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('pogo', '跳跳僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('yeti', '雪人僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('bungee', '蹦极僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('ladderZombie', '扶梯僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('catapult', '投石车僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('imp', '小鬼僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('boss', '僵王标记', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('rake', '钉耙', '物品', 5, 0xffbda47a),
    ObjectSpec('grave', '墓碑', '物品', 5, 0xff8b9292),
    ObjectSpec('ladder', '梯子', '物品', 25, 0xffc5aa7e),
    ObjectSpec('crater', '弹坑', '物品', -1, 0xff766d5d),
    ObjectSpec('FumeCloud', '喷菇烟雾', '特效', 50, 0xff8f9c7b),
    ObjectSpec('LanternShine', '路灯光晕', '特效', 50, 0xff8f9c7b),
    ObjectSpec('Pumpkin_back', '南瓜后半', '特效', 50, 0xff8f9c7b),
    ObjectSpec('Umbrellaleaf_BIG', '撑开保护伞', '特效', 50, 0xff8f9c7b),
    ObjectSpec('GloomPuff', '忧郁菇烟雾', '特效', 50, 0xff8f9c7b),
    ObjectSpec('Spotlight', '舞台灯光', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('Spotlight2', '舞台灯光二', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('BungiZombie_hand', '蹦极僵尸手', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('Redeyed_Gargantuar', '红眼巨人僵尸', '僵尸', 40, 0xff8f9c7b),
    ObjectSpec('Imitater', '模仿者', '特效', 50, 0xff8f9c7b),
    ObjectSpec('ScaryPot', '花瓶', '物品', 5, 0xff8f9c7b),
    ObjectSpec('ScaryPot_back', '花瓶后半', '物品', 5, 0xff8f9c7b),
    ObjectSpec('Lawnmower', '草地小推车', '物品', 5, 0xff8f9c7b),
    ObjectSpec('Poolcleaner', '泳池清理车', '物品', 5, 0xff8f9c7b),
    ObjectSpec('Roofcleaner', '屋顶清理车', '物品', 5, 0xff8f9c7b),
    ObjectSpec('Brain', '脑子', '物品', 5, 0xff8f9c7b),
    ObjectSpec('Stripe', '条纹', '物品', 5, 0xff8f9c7b),
    ObjectSpec('SnowFlakes', '雪花', '物品', 5, 0xff8f9c7b),
    ObjectSpec('BungeeTarget', '蹦极目标', '物品', 5, 0xff8f9c7b),
    ObjectSpec('Ice', '冰道', '物品', 5, 0xff8f9c7b),
    ObjectSpec('Ice1', '冰道边缘', '特效', 50, 0xff8f9c7b),
    ObjectSpec('sun', '阳光', '特效', 50, 0xffffd664),
    ObjectSpec('iceTrail', '冰道', '特效', -2, 0xffb3dfeb),
    ObjectSpec('explosion', '爆炸标记', '特效', 50, 0xffef9057),
  ];
  static ObjectSpec byId(String id) => all.firstWhere((s) => s.id == id,
      orElse: () => throw FormatException('未知对象：$id'));
}

class Piece {
  final String id, type;
  final int row, col, layer;
  final int frameRow, frameCol;
  final String websiteEffects;
  final List<String>? websiteFields;
  final double scale, opacity;
  final bool flipped, flippedVertical;
  final bool asleep;
  final Set<String> effects;
  final String appearance;
  Piece(
      {required this.id,
      required this.type,
      required this.row,
      required this.col,
      required this.layer,
      this.scale = 1,
      double? opacity,
      this.frameRow = 0,
      this.frameCol = 0,
      this.websiteEffects = '0',
      List<String>? websiteFields,
      this.asleep = false,
      this.flipped = false,
      this.flippedVertical = false,
      Set<String> effects = const {},
      this.appearance = '默认'})
      : opacity = opacity ?? (effects.contains('半透明') ? .5 : 1),
        websiteFields =
            websiteFields == null ? null : List.unmodifiable(websiteFields),
        effects = Set.unmodifiable(normalizeEffects(effects));

  /// Raw site placement coordinates, preserved for original positioned props.
  double? get websitePixelX =>
      websiteFields != null && websiteFields!.length >= 9
          ? double.tryParse(websiteFields![websiteFields!.length - 2])
          : null;
  double? get websitePixelY =>
      websiteFields != null && websiteFields!.length >= 9
          ? double.tryParse(websiteFields!.last)
          : null;
  ObjectSpec get spec => ObjectSpec.byId(type);
  Piece copy(
          {int? row,
          int? col,
          int? layer,
          double? scale,
          double? opacity,
          int? frameRow,
          int? frameCol,
          String? websiteEffects,
          List<String>? websiteFields,
          bool? asleep,
          bool? flipped,
          bool? flippedVertical,
          Set<String>? effects,
          String? appearance}) =>
      Piece(
          id: id,
          type: type,
          row: row ?? this.row,
          col: col ?? this.col,
          layer: layer ?? this.layer,
          scale: scale ?? this.scale,
          opacity: opacity ??
              (effects == null
                  ? this.opacity
                  : effects.contains('半透明')
                      ? .5
                      : this.effects.contains('半透明')
                          ? 1
                          : this.opacity),
          frameRow: frameRow ?? this.frameRow,
          frameCol: frameCol ?? this.frameCol,
          websiteEffects: websiteEffects ??
              (effects == null
                  ? this.websiteEffects
                  : encodeWebsiteEffects(effects)),
          websiteFields: websiteFields ??
              ((row != null && row != this.row) ||
                      (col != null && col != this.col)
                  ? null
                  : this.websiteFields),
          asleep: asleep ?? this.asleep,
          flipped: flipped ?? this.flipped,
          flippedVertical: flippedVertical ?? this.flippedVertical,
          effects: effects ??
              (websiteEffects == null
                  ? this.effects
                  : decodeWebsiteEffects(websiteEffects)),
          appearance: appearance ?? this.appearance);
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'row': row,
        'col': col,
        'layer': layer,
        'width': spec.width,
        'height': 1,
        'scale': scale,
        'opacity': opacity,
        'frameRow': frameRow,
        'frameCol': frameCol,
        'websiteEffects': websiteEffects,
        if (websiteFields != null) 'websiteFields': websiteFields,
        if (asleep) 'asleep': true,
        'flipped': flipped,
        'flippedVertical': flippedVertical,
        'effects': effects.toList()..sort(),
        'appearance': appearance
      };
  static const websiteEffectNames = [
    '模仿者',
    '冰冻',
    '魅惑',
    '高亮',
    '阴影',
    '灰烬',
    '半透明'
  ];
  static const allowedEffects = [...websiteEffectNames, '我是僵尸'];

  /// Source gray is a four-character color mask with named filter suffixes;
  /// the special one-character `1` is imitater, not the first mask bit.
  static bool validWebsiteEffects(String value) =>
      RegExp(r'^(?:[01]{1,7}|[01]{4}(?:imitater|dropshadow|black))$')
          .hasMatch(value);
  static Set<String> decodeWebsiteEffects(String value) {
    if (value == '1') return {'模仿者'};
    return {
      if (value.length >= 4 && value[0] == '1') '魅惑',
      if (value.length >= 4 && value[2] == '1') '冰冻',
      if (value.length >= 4 && value[3] == '1') '高亮',
      if (value.contains('imitater')) '模仿者',
      if (value.contains('dropshadow')) '阴影',
      if (value.contains('black')) '灰烬',
    };
  }

  /// Source imitater/dropshadow/black share one slot; the last selected wins.
  /// Canonicalize before persistence so JSON sorting cannot change that winner.
  static Set<String> normalizeEffects(Set<String> effects) {
    const filters = {'模仿者', '阴影', '我是僵尸', '灰烬'};
    final selected = effects.where(filters.contains).toList();
    return {
      ...effects.where((e) => !filters.contains(e)),
      if (selected.isNotEmpty) selected.last == '我是僵尸' ? '阴影' : selected.last,
    };
  }

  static String encodeWebsiteEffects(Set<String> effects) {
    effects = normalizeEffects(effects);
    final shadow = effects.contains('阴影');
    final black = effects.contains('灰烬');
    final mask =
        '${effects.contains('魅惑') ? 1 : 0}0${effects.contains('冰冻') ? 1 : 0}${effects.contains('高亮') ? 1 : 0}';
    final filter = black
        ? 'black'
        : shadow
            ? 'dropshadow'
            : effects.contains('模仿者')
                ? 'imitater'
                : '';
    if (mask == '0000' && filter == 'imitater') return '1';
    if (mask == '0000' && filter.isEmpty) return '0';
    return '$mask$filter';
  }

  factory Piece.fromJson(Map<String, dynamic> j) {
    final spec = ObjectSpec.byId(j['type'] as String);
    final scale = (j['scale'] as num).toDouble();
    final opacity = (j['opacity'] as num?)?.toDouble() ??
        ((j['effects'] as List).contains('半透明') ? .5 : 1.0);
    final effects = (j['effects'] as List).cast<String>().toSet();
    final row = j['row'] as int, col = j['col'] as int;
    final layer = j['layer'] as int;
    if ((j['asleep'] != null && j['asleep'] is! bool) ||
        !opacity.isFinite ||
        opacity < 0 ||
        opacity > 1 ||
        scale < .25 ||
        scale > 3 ||
        !scale.isFinite ||
        row < 0 ||
        col < 0 ||
        row > 99 ||
        col > 99 ||
        layer.abs() > 1000 ||
        effects.any((e) => !allowedEffects.contains(e)) ||
        j['width'] != spec.width ||
        j['height'] != 1 ||
        !['默认', '轮廓'].contains(j['appearance'])) {
      throw const FormatException('对象属性或占格无效');
    }
    final frameRow = (j['frameRow'] ?? 0) as int;
    final frameCol = (j['frameCol'] ?? 0) as int;
    final websiteEffects = (j['websiteEffects'] ?? '0') as String;
    final websiteFields = (j['websiteFields'] as List?)?.cast<String>();
    if (frameRow < 0 ||
        frameRow > 32 ||
        frameCol < 0 ||
        frameCol > 32 ||
        !validWebsiteEffects(websiteEffects) ||
        (websiteFields != null &&
            (websiteFields.length < 6 ||
                websiteFields.length > 11 ||
                !RegExp(r'^[0-9a-fA-F]{1,2}$').hasMatch(websiteFields.first) ||
                websiteFields
                    .asMap()
                    .entries
                    .where((e) => e.key != 0 && e.key != 5)
                    .any((e) =>
                        !RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(e.value))))) {
      throw const FormatException('原站外表或保留字段无效');
    }
    final id = j['id'] as String;
    if (id.isEmpty || id.length > 128) throw const FormatException('对象 ID 无效');
    return Piece(
        id: id,
        type: spec.id,
        row: row,
        col: col,
        layer: layer,
        scale: scale,
        opacity: opacity,
        frameRow: frameRow,
        frameCol: frameCol,
        websiteEffects: websiteEffects,
        websiteFields: websiteFields,
        asleep: j['asleep'] == true,
        flipped: j['flipped'] as bool,
        flippedVertical: (j['flippedVertical'] ?? false) as bool,
        effects: effects,
        appearance: j['appearance'] as String);
  }
}

class Formation {
  final String mapId;
  final int sunValue;
  final int fogColumns;
  final List<String> seedSlots;

  /// Slot indices whose cards use the source imitater appearance.
  final Set<int> imitaterSeedSlots;
  final List<Piece> pieces;
  final Map<String, bool> display;
  Formation(
      {this.mapId = 'pool',
      this.sunValue = 9990,
      this.fogColumns = 0,
      List<String> seedSlots = const [],
      Set<int> imitaterSeedSlots = const {},
      List<Piece> pieces = const [],
      Map<String, bool> display = const {
        '坐标': false,
        '阳光': true,
        '卡槽': true,
        '小推车': true,
        '脑子': false,
        '迷雾': false,
        '继续标识': false,
        '泥土': true
      }})
      : seedSlots = List.unmodifiable(seedSlots),
        imitaterSeedSlots =
            _validateImitaterSlots(imitaterSeedSlots, seedSlots.length),
        pieces = List.unmodifiable(pieces),
        display = Map.unmodifiable(display);
  static Set<int> _validateImitaterSlots(Set<int> indices, int slotCount) {
    if (indices.length > 1 || indices.any((i) => i < 0 || i >= slotCount)) {
      throw const FormatException('模仿者卡槽索引无效或超过一个');
    }
    return Set<int>.unmodifiable(indices);
  }

  BoardMap get map => BoardMap.byId(mapId);
  Formation copy(
          {String? mapId,
          int? sunValue,
          int? fogColumns,
          List<String>? seedSlots,
          Set<int>? imitaterSeedSlots,
          List<Piece>? pieces,
          Map<String, bool>? display}) =>
      Formation(
          mapId: mapId ?? this.mapId,
          sunValue: sunValue ?? this.sunValue,
          fogColumns: fogColumns ?? this.fogColumns,
          seedSlots: seedSlots ?? this.seedSlots,
          imitaterSeedSlots: imitaterSeedSlots ?? this.imitaterSeedSlots,
          pieces: pieces ?? this.pieces,
          display: display ?? this.display);
  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'map': mapId,
        'sunValue': sunValue,
        'fogColumns': fogColumns,
        'seedSlots': seedSlots,
        if (imitaterSeedSlots.isNotEmpty)
          'imitaterSeedSlots': imitaterSeedSlots.toList()..sort(),
        'board': {'rows': map.rows, 'columns': map.columns},
        'objects': pieces.map((e) => e.toJson()).toList(),
        'display': display
      };
  String get fingerprint => jsonEncode(toJson());
  bool fits(Piece p, BoardMap m) =>
      p.row >= 0 &&
      p.row < m.rows &&
      p.col >= 0 &&
      p.col + p.spec.width <= m.columns;
  factory Formation.fromJson(Map<String, dynamic> j) {
    if (j['schemaVersion'] != 1) throw const FormatException('不支持的文档版本');
    final sunValue = (j['sunValue'] ?? 9990) as int;
    final fogColumns = (j['fogColumns'] ?? 0) as int;
    if (fogColumns < 0 || fogColumns > 10) {
      throw const FormatException('雾列数应在0到10之间');
    }
    if (sunValue < 0 || sunValue > 99999999) {
      throw const FormatException('阳光数值越界');
    }
    final seedSlots = ((j['seedSlots'] ?? const []) as List).cast<String>();
    if (seedSlots.length > 10) throw const FormatException('卡槽不能超过10个');
    for (final type in seedSlots) {
      ObjectSpec.byId(type);
    }
    final rawImitater = j['imitaterSeedSlots'] ?? const <int>[];
    if (rawImitater is! List ||
        rawImitater.any((i) => i is! int) ||
        rawImitater.length > 1) {
      throw const FormatException('模仿者卡槽必须是至多一个整数索引');
    }
    final imitaterSeedSlots = _validateImitaterSlots(
        rawImitater.cast<int>().toSet(), seedSlots.length);
    final map = BoardMap.byId(j['map'] as String);
    if (j['board']['rows'] != map.rows ||
        j['board']['columns'] != map.columns) {
      throw const FormatException('棋盘参数不一致');
    }
    final objects = j['objects'] as List;
    if (objects.length > 5000) throw const FormatException('对象超过 5000 个');
    final pieces = objects
        .map((e) => Piece.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    if (pieces.map((p) => p.id).toSet().length != pieces.length) {
      throw const FormatException('对象 ID 重复');
    }
    final display = Map<String, bool>.from(j['display']);
    if (display.keys.any((k) =>
        !['坐标', '阳光', '卡槽', '小推车', '脑子', '迷雾', '继续标识', '泥土'].contains(k))) {
      throw const FormatException('未知显示设置');
    }
    final result = Formation(
        mapId: map.id,
        sunValue: sunValue,
        fogColumns: fogColumns,
        seedSlots: seedSlots,
        imitaterSeedSlots: imitaterSeedSlots,
        pieces: pieces,
        display: display);
    if (pieces.any((p) => !result.fits(p, map))) {
      throw const FormatException('对象越界');
    }
    return result;
  }
}

class ProjectCodec {
  static const maxBytes = 8 * 1024 * 1024;
  static String encode(Formation f) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'pvz-formation-project',
        'version': 1,
        'resources': {'kind': 'builtin-vector', 'catalogVersion': 1},
        'document': f.toJson()
      });
  static Formation decode(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('项目超过 8 MiB');
    }
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (j['format'] != 'pvz-formation-project' ||
          j['version'] != 1 ||
          j['resources']['kind'] != 'builtin-vector' ||
          j['resources']['catalogVersion'] != 1) {
        throw const FormatException('项目格式或资源清单不受支持');
      }
      return Formation.fromJson(Map<String, dynamic>.from(j['document']));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('项目字段缺失或类型不正确');
    }
  }

  static String appString(Formation f) =>
      'PVZF1:${base64Url.encode(utf8.encode(encode(f)))}';
  static Formation fromAppString(String s) {
    if (!s.startsWith('PVZF1:')) {
      throw const FormatException('此入口只接受 PVZF1；原站字符串请使用专用入口');
    }
    if (s.length > maxBytes * 2) throw const FormatException('字符串过大');
    return decode(utf8.decode(base64Url.decode(s.substring(6))));
  }
}
