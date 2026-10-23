import 'formation.dart';

/// Logical object filters. These do not impose game planting restrictions.
class ObjectFilter {
  static const options = [
    '全部',
    '植物',
    '僵尸',
    '物品',
    '特效',
    '普通植物',
    '容器',
    '南瓜',
    '咖啡豆',
    '梯子',
    '墓碑',
    '钉耙',
    '物品及特效'
  ];
  static bool matches(Piece p, String filter) => switch (filter) {
        '全部' => true,
        '普通植物' => p.spec.category == '植物' &&
            !['lily', 'pot', 'pumpkin', 'coffee'].contains(p.type),
        '容器' => ['lily', 'pot'].contains(p.type),
        '南瓜' => p.type == 'pumpkin',
        '咖啡豆' => p.type == 'coffee',
        '梯子' => p.type == 'ladder',
        '墓碑' => p.type == 'grave',
        '钉耙' => p.type == 'rake',
        '物品及特效' => ['物品', '特效'].contains(p.spec.category),
        _ => p.spec.category == filter,
      };
}
