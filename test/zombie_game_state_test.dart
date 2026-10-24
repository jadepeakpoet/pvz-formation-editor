import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/zombie_game_state.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';

void main() {
  test('feeding dolphin preset is eating; upright pool frame is swimming', () {
    final dolphin = LibraryPresets.all[59].document.pieces.singleWhere((p) => p.type == 'dolphin');
    final state = ZombieGameState.of(dolphin).toJson();
    expect(state['animation'], 'anim_eat');
    expect(state['eating'], isTrue);
    final swimming = ZombieGameState.of(dolphin.copy(frameCol: 4)).toJson();
    expect(swimming['animation'], 'anim_swim');
    expect(swimming['eating'], isFalse);
  });
  test('game transition animations read as their visible frames instead of defaults', () {
    for (final entry in <(int, String, int, int)>[
      (3, 'anim_jump', 0, 3), (5, 'anim_gasp', 0, 3),
      (11, 'anim_uptoeat', 0, 3), (15, 'anim_pop', 0, 3),
      (16, 'anim_pop', 0, 2), (21, 'anim_placeladder', 0, 3),
      (22, 'anim_shoot', 1, 1), (24, 'anim_thrown', 1, 1),
    ]) {
      final state = ZombieGameState.fromRuntime(entry.$1, {'phase': 1 + entry.$1,
        'hasHead': true, 'animation': entry.$2});
      expect((state.row, state.col), (entry.$3, entry.$4));
    }
  });
  test(
    'every supported zombie has a default and states derived from runtime',
    () {
      expect(ZombieGameState.profiles.length, 21);
      for (final entry in ZombieGameState.profiles.entries) {
        final type = WebsiteCodec.typeForIndex(entry.key + 0x50)!;
        expect(entry.value.any((s) => s.row == 0 && s.col == 0), isTrue);
        for (final state in entry.value) {
          final piece = Piece(
            id: 'state',
            type: type,
            row: 0,
            col: 0,
            layer: ObjectSpec.byId(type).layer,
            frameRow: state.row,
            frameCol: state.col,
          );
          expect(ZombieGameState.of(piece).toJson(), state.toJson());
          expect(
            ZombieGameState.fromRuntime(entry.key, state.toJson()).toJson(),
            state.toJson(),
            reason: '$type ${state.row},${state.col}',
          );
        }
      }
    },
  );
  test(
    'six-line imprisoned zombies use their selected property and water states',
    () {
      final pieces = LibraryPresets.all[81].document.pieces;
      Map<String, dynamic> state(String type) =>
          ZombieGameState.of(pieces.singleWhere((p) => p.type == type))
              .toJson();
      expect(state('jack')['phase'], 0);
      expect(state('jack')['hidden'], contains('Zombie_jackbox_box'));
      expect(state('balloon')['flyingHealth'], 0);
      expect(state('balloon')['altitude'], 0);
      expect(state('snorkel')['phase'], 61);
      expect(state('snorkel')['eating'], isTrue);
      expect(state('digger')['hasObject'], isFalse);
      expect(state('newspaper')['shieldType'], 0);
      expect(state('flag')['inPool'], isTrue);
    },
  );
  test('submerged and surfaced snorkel are read independently', () {
    final swim = ZombieGameState.fromRuntime(11, {
      'phase': 59,
      'eating': false,
      'inPool': true,
      'hasArm': true,
      'animation': 'anim_swim',
    });
    final eat = ZombieGameState.fromRuntime(11, {
      'phase': 61,
      'eating': true,
      'inPool': true,
      'hasArm': true,
      'animation': 'anim_eat',
    });
    expect((swim.row, swim.col), (1, 1));
    expect((eat.row, eat.col), (1, 2));
  });
  test('transition frames cannot silently become default live zombies', () {
    expect(
      () => ZombieGameState.of(
        Piece(
          id: 'pop',
          type: 'balloon',
          row: 0,
          col: 0,
          layer: 20,
          frameRow: 0,
          frameCol: 2,
        ),
      ),
      throwsFormatException,
    );
  });
}
