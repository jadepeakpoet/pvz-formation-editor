import 'formation.dart';
import 'zombie_layout.dart';

/// Stable game appearances represented by the ArrayDesign sprite sheets.
/// Walking variants can differ in pose while sharing the same game state.
class ZombieGameState {
  final int row, col;
  final String animation;
  final int phase;
  final bool eating, pool, arm;
  final bool? object;
  final int? shield, flying;
  final double? altitude;
  final List<String> hidden;
  const ZombieGameState(
    this.row,
    this.col,
    this.animation,
    this.phase, {
    this.eating = false,
    this.pool = false,
    this.arm = true,
    this.object,
    this.shield,
    this.flying,
    this.altitude,
    this.hidden = const [],
  });

  static const _plain = [
    ZombieGameState(0, 0, 'anim_walk', 0),
    ZombieGameState(0, 1, 'anim_walk2', 0),
    ZombieGameState(0, 2, 'anim_eat', 0, eating: true),
    ZombieGameState(1, 1, 'anim_swim', 0, pool: true, altitude: 0),
    ZombieGameState(1, 2, 'anim_eat', 0, eating: true, pool: true, altitude: 0),
  ];
  static const _poleHidden = [
    'Zombie_polevaulter_innerarm',
    'Zombie_polevaulter_innerhand',
    'Zombie_polevaulter_pole',
  ];
  static const _boxHidden = [
    'Zombie_jackbox_box',
    'Zombie_jackbox_handle',
    'Zombie_jackbox_clown',
  ];
  static const _axeHidden = ['Zombie_digger_pickaxe', 'Zombie_digger_dirt'];
  static const _pogoHidden = ['Zombie_pogo_stick'];
  static const _impHidden = [
    'Zombie_imp',
    'Zombie_gargantuar_rope',
    'Zombie_gargantuar_whiterope',
  ];
  static final Map<int, List<ZombieGameState>> profiles = {
    for (final type in [0, 1, 2, 4, 6]) type: _plain,
    3: const [
      ZombieGameState(0, 0, 'anim_run', 11, object: true),
      ZombieGameState(0, 1, 'anim_run', 11, object: true),
      ZombieGameState(
        1,
        1,
        'anim_walk',
        13,
        object: false,
        hidden: _poleHidden,
      ),
      ZombieGameState(
        1,
        2,
        'anim_walk',
        13,
        object: false,
        hidden: _poleHidden,
      ),
      ZombieGameState(
        1,
        3,
        'anim_eat',
        13,
        object: false,
        eating: true,
        hidden: _poleHidden,
      ),
      ZombieGameState(
        1,
        4,
        'anim_eat',
        13,
        object: false,
        eating: true,
        hidden: _poleHidden,
      ),
    ],
    5: const [
      ZombieGameState(0, 0, 'anim_walk', 29),
      ZombieGameState(0, 1, 'anim_walk', 29),
      ZombieGameState(0, 2, 'anim_eat', 29, eating: true),
      ZombieGameState(1, 1, 'anim_walk_nopaper', 31, shield: 0),
      ZombieGameState(1, 2, 'anim_eat_nopaper', 31, shield: 0, eating: true),
      ZombieGameState(1, 3, 'anim_walk_nopaper', 31, shield: 0, arm: false),
    ],
    7: const [
      ZombieGameState(0, 0, 'anim_walk', 0),
      ZombieGameState(0, 1, 'anim_walk', 0),
      ZombieGameState(0, 2, 'anim_eat', 0, eating: true),
      ZombieGameState(1, 1, 'anim_walk', 0, arm: false),
      ZombieGameState(1, 2, 'anim_eat', 0, arm: false, eating: true),
    ],
    8: const [
      ZombieGameState(0, 0, 'anim_moonwalk', 40),
      ZombieGameState(0, 1, 'anim_moonwalk', 40),
      ZombieGameState(0, 2, 'anim_eat', 44, eating: true),
      ZombieGameState(0, 3, 'anim_walk', 44),
      ZombieGameState(1, 1, 'anim_moonwalk', 40, arm: false),
      ZombieGameState(1, 2, 'anim_walk', 44, arm: false),
      ZombieGameState(1, 3, 'anim_eat', 44, arm: false, eating: true),
    ],
    9: const [
      ZombieGameState(0, 0, 'anim_walk', 44),
      ZombieGameState(0, 1, 'anim_walk', 44),
      ZombieGameState(0, 2, 'anim_eat', 44, eating: true),
      ZombieGameState(1, 1, 'anim_walk', 44, arm: false),
      ZombieGameState(1, 2, 'anim_eat', 44, arm: false, eating: true),
    ],
    11: const [
      ZombieGameState(0, 0, 'anim_walk', 57),
      ZombieGameState(0, 1, 'anim_walk', 57),
      ZombieGameState(1, 1, 'anim_swim', 59, pool: true, altitude: 0),
      ZombieGameState(
        1,
        2,
        'anim_eat',
        61,
        pool: true,
        altitude: 0,
        eating: true,
      ),
      ZombieGameState(
        1,
        3,
        'anim_eat',
        61,
        pool: true,
        altitude: 0,
        eating: true,
        arm: false,
      ),
    ],
    14: const [
      ZombieGameState(0, 0, 'anim_walkdolphin', 51, object: true),
      ZombieGameState(0, 1, 'anim_walk', 56, object: false),
      ZombieGameState(
        1,
        1,
        'anim_ride',
        53,
        object: true,
        pool: true,
        altitude: 0,
      ),
      ZombieGameState(
        1,
        2,
        'anim_eat',
        55,
        object: false,
        pool: true,
        altitude: 0,
        eating: true,
      ),
      ZombieGameState(
        1,
        4,
        'anim_swim',
        55,
        object: false,
        pool: true,
        altitude: 0,
      ),
    ],
    15: const [
      ZombieGameState(0, 0, 'anim_idle', 15),
      ZombieGameState(0, 1, 'anim_walk', 15),
      ZombieGameState(0, 2, 'anim_walk', 15),
      ZombieGameState(1, 1, 'anim_walk', 0, object: false, hidden: _boxHidden),
      ZombieGameState(
        1,
        2,
        'anim_eat',
        0,
        object: false,
        hidden: _boxHidden,
        eating: true,
      ),
    ],
    16: const [
      ZombieGameState(0, 0, 'anim_idle', 73, flying: 20, altitude: 25),
      ZombieGameState(0, 1, 'anim_swing', 73, flying: 20, altitude: 25),
      ZombieGameState(1, 1, 'anim_walk', 75, flying: 0, altitude: 0),
      ZombieGameState(
        1,
        2,
        'anim_eat',
        75,
        flying: 0,
        altitude: 0,
        eating: true,
      ),
    ],
    17: const [
      ZombieGameState(0, 0, 'anim_walk', 37, object: true),
      ZombieGameState(0, 1, 'anim_walk', 37, object: true),
      ZombieGameState(0, 2, 'anim_eat', 37, object: true, eating: true),
      ZombieGameState(0, 3, 'anim_dig', 32, object: true, altitude: -120),
      ZombieGameState(1, 1, 'anim_walk', 38, object: false, hidden: _axeHidden),
      ZombieGameState(
        1,
        2,
        'anim_eat',
        38,
        object: false,
        hidden: _axeHidden,
        eating: true,
      ),
      ZombieGameState(1, 4, 'anim_walk', 37, object: true),
    ],
    18: const [
      ZombieGameState(0, 0, 'anim_pogo', 20, object: true),
      ZombieGameState(0, 1, 'anim_pogo', 20, object: true),
      ZombieGameState(
        0,
        2,
        'anim_eat',
        0,
        object: false,
        hidden: _pogoHidden,
        eating: true,
        altitude: 0,
      ),
      ZombieGameState(
        1,
        1,
        'anim_walk',
        0,
        object: false,
        hidden: _pogoHidden,
        altitude: 0,
      ),
      ZombieGameState(
        1,
        2,
        'anim_eat',
        0,
        object: false,
        hidden: _pogoHidden,
        eating: true,
        altitude: 0,
      ),
    ],
    19: const [
      ZombieGameState(0, 0, 'anim_walk', 0, object: true),
      ZombieGameState(0, 1, 'anim_walk', 0, object: false),
      ZombieGameState(1, 1, 'anim_eat', 0, object: true, eating: true),
    ],
    21: const [
      ZombieGameState(0, 0, 'anim_ladderwalk', 76),
      ZombieGameState(0, 1, 'anim_ladderwalk', 76),
      ZombieGameState(0, 2, 'anim_laddereat', 76, eating: true),
      ZombieGameState(1, 1, 'anim_walk', 0, shield: 0),
      ZombieGameState(1, 2, 'anim_eat', 0, shield: 0, eating: true),
      ZombieGameState(1, 3, 'anim_ladderwalk', 76, arm: false),
    ],
    22: const [
      ZombieGameState(0, 0, 'anim_walk', 0),
      ZombieGameState(0, 1, 'anim_walk', 0),
      ZombieGameState(1, 0, 'anim_idle', 67),
    ],
    23: const [
      ZombieGameState(0, 0, 'anim_walk', 0, object: true),
      ZombieGameState(0, 1, 'anim_walk', 0, object: true),
      ZombieGameState(1, 1, 'anim_walk', 0, object: false, hidden: _impHidden),
    ],
    24: const [
      ZombieGameState(0, 0, 'anim_walk', 0),
      ZombieGameState(0, 1, 'anim_walk', 0),
      ZombieGameState(0, 2, 'anim_eat', 0, eating: true),
    ],
  };

  static ZombieGameState of(Piece piece) {
    final type = ZombieLayout.gameType(piece.type);
    for (final state in profiles[type] ?? const <ZombieGameState>[]) {
      if (state.row == piece.frameRow && state.col == piece.frameCol)
        return state;
    }
    throw FormatException('${piece.spec.name}所选外观是过渡动作或死亡帧，请选择行走、啃食或其他稳定外观后应用');
  }

  Map<String, dynamic> toJson() => {
    'animation': animation,
    'phase': phase,
    'eating': eating,
    'inPool': pool,
    'hasArm': arm,
    if (object != null) 'hasObject': object,
    if (shield != null) 'shieldType': shield,
    if (flying != null) 'flyingHealth': flying,
    if (altitude != null) 'altitude': altitude,
    'hidden': hidden,
  };

  static ZombieGameState fromRuntime(int type, Map<String, dynamic> raw) {
    final states = profiles[type];
    if (states == null) throw const FormatException('僵尸种类尚未适配');
    if (type != 22 && (raw['hasHead'] == false || raw['phase'] == 1)) {
      return const ZombieGameState(1, 0, 'anim_death', 1);
    }
    const transitionFrames = <int, Map<String, (int, int)>>{
      3: {'anim_jump': (0, 3)},
      5: {'anim_gasp': (0, 3)},
      11: {'anim_jumpinpool': (0, 2), 'anim_uptoeat': (0, 3)},
      14: {'anim_jumpinpool': (0, 3), 'anim_dolphinjump': (0, 4)},
      15: {'anim_pop': (0, 3)},
      16: {'anim_pop': (0, 2)},
      17: {'anim_drill': (0, 4), 'anim_landing': (0, 4), 'anim_dizzy': (0, 4)},
      21: {'anim_placeladder': (0, 3)},
      22: {'anim_shoot': (1, 1)},
      24: {'anim_thrown': (1, 1), 'anim_land': (1, 2)},
    };
    final transition = transitionFrames[type]?[raw['animation']];
    if (transition != null) {
      return ZombieGameState(transition.$1, transition.$2,
          raw['animation'] as String, raw['phase'] as int);
    }
    if (type == 23 && {'anim_smash', 'anim_throw'}.contains(raw['animation'])) {
      final throwing = raw['animation'] == 'anim_throw';
      return ZombieGameState(throwing ? 0 : raw['hasObject'] == false ? 1 : 0,
          throwing ? 4 : 2, raw['animation'] as String, raw['phase'] as int);
    }
    ZombieGameState? best;
    var bestScore = -10000;
    for (final state in states) {
      var score = 0;
      final expected = state.toJson();
      for (final key in [
        'phase',
        'eating',
        'inPool',
        'hasArm',
        'hasObject',
        'shieldType',
        'flyingHealth',
      ]) {
        if (!expected.containsKey(key) || !raw.containsKey(key)) continue;
        score += expected[key] == raw[key] ? 20 : -40;
      }
      if (raw['animation'] == state.animation) score += 50;
      if (score > bestScore) {
        best = state;
        bestScore = score;
      }
    }
    return best!;
  }
}
