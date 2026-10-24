import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/domain/placement_layout.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/domain/zombie_layout.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';

void main() {
  test('swimming dolphin atlas anchor converts to actor position and back', () {
    for (final frame in [2, 4]) {
      final piece = Piece(id: 'swim', type: 'dolphin', row: 2, col: 3,
          layer: 40, frameRow: 1, frameCol: frame,
          websiteFields: ZombieLayout.positionFields('dolphin', 2, 3, 287,
              frameRow: 1, frameCol: frame));
      expect(ZombieLayout.gameX(piece), 97);
      expect(ZombieLayout.editorX('dolphin', 1, frame, 97), 287);
      final read = GameFormationSnapshot.fromJson({
        'pid': 1, 'version': '1051', 'map': 'pool', 'sunValue': 50,
        'includeZombies': true,
        'pieces': [{'zombieType': 14, 'row': 2, 'col': 0, 'x': 97,
          'animation': frame == 2 ? 'anim_eat' : 'anim_swim', 'phase': 55,
          'inPool': true, 'eating': frame == 2, 'hasHead': true, 'hasArm': true,
          'hasObject': false}],
      });
      expect(read.formation.pieces.single.websitePixelX, 287);
      expect(read.formation.pieces.single.col, 3);
      expect(read.formation.pieces.single.frameCol, frame);
    }
    expect(ZombieLayout.appearanceOffset('dolphin', 0, 0), 0);
    expect(ZombieLayout.appearanceOffset('jack', 1, 2), 0);
  });
  test('dolphin preset retains eating and pumpkin chew highlight for game apply', () {
    final source = LibraryPresets.all[59].document;
    final full = PlacementLayout.prepare(source, includeZombies: true).document;
    final pumpkin = full.pieces.singleWhere((p) => p.type == 'pumpkin' && p.row == 2 && p.col == 0);
    expect(pumpkin.effects, contains('高亮'));
    expect(PlacementLayout.prepare(source).document.pieces
        .singleWhere((p) => p.id == pumpkin.id).effects, isNot(contains('高亮')));
  });
  test(
    'legacy dolphin X is preserved and exported in the current position slot',
    () {
      final document = LibraryPresets.all[59].document;
      final dolphin = document.pieces.singleWhere((p) => p.type == 'dolphin');
      expect(dolphin.websitePixelX, 287);
      expect(dolphin.websitePixelY, isNull);
      final code = WebsiteCodec.encode(document);
      final fields = code
          .split(',')
          .singleWhere((s) => s.startsWith('5E '))
          .trim()
          .split(RegExp(r'\s+'));
      expect(fields[6], '1.0');
      expect(fields[7], '0');
      expect(double.parse(fields[8]), 287);
      expect(
        WebsiteCodec.decode(code)
            .pieces
            .singleWhere((p) => p.type == 'dolphin')
            .websitePixelX,
        287,
      );
    },
  );
  test(
    'legacy, current, reversed and fractional zombie positions round trip',
    () {
      for (final record in [
        '5E 3 4 1 2 0 0 287',
        '5E 3 4 1 2 0 1 287',
        '5E 3 4 1 2 0 1 0 287.25',
        '5E 3 4 1 2 0 0.5 1 287.25 170',
      ]) {
        final source = WebsiteCodec.decode('0,$record');
        final piece = source.pieces.single;
        final restored =
            WebsiteCodec.decode(WebsiteCodec.encode(source)).pieces.single;
        expect(restored.websitePixelX, piece.websitePixelX);
        expect(restored.websitePixelY, piece.websitePixelY);
        expect(restored.flipped, piece.flipped);
        expect(restored.opacity, piece.opacity);
      }
    },
  );
  test(
    'multiple zombies can share a cell with independent pixel positions',
    () {
      final source = WebsiteCodec.decode(
        '0,50 1 1 0 0 0 1 0 80,52 1 1 0 0 0 1 0 95',
      );
      final copy = WebsiteCodec.decode(WebsiteCodec.encode(source));
      expect(copy.pieces.map((p) => p.websitePixelX), [80, 95]);
      expect(
        FormationExchange.decode(FormationExchange.encode(source)).pieces,
        isEmpty,
      );
    },
  );
  test(
    'game extraction retains zombie positions while Toolkit stays compatible',
    () {
      final source = LibraryPresets.all[59].document;
      final toolkit = PlacementLayout.prepare(source);
      final complete = PlacementLayout.prepare(source, includeZombies: true);
      expect(toolkit.skippedObjects, 1);
      expect(complete.skippedObjects, 0);
      expect(complete.document.pieces.length, source.pieces.length);
      expect(
        complete.document.pieces
            .singleWhere((p) => p.type == 'dolphin')
            .websitePixelX,
        287,
      );
      expect(
        FormationExchange.detectFormat(
          FormationExchange.encodeGameRead(source),
        ),
        FormationFormat.website,
      );
    },
  );
  test(
    'opt-in game snapshots retain zombie IDs and positions; old snapshots work',
    () {
      Map<Object?, Object?> base(List<Map<String, dynamic>> pieces) => {
            'pid': 1,
            'version': '1051',
            'map': 'pool',
            'sunValue': 50,
            'pieces': pieces,
          };
      final old = GameFormationSnapshot.fromJson(
        base([
          {'type': 0, 'row': 0, 'col': 0},
        ]),
      );
      expect(old.includesZombies, isFalse);
      expect(old.toJson().containsKey('includeZombies'), isFalse);
      final full = GameFormationSnapshot.fromJson({
        ...base([
          {
            'zombieType': 14,
            'row': 2,
            'col': 3,
            'x': 287.25,
            'frameRow': 1,
            'frameCol': 2,
          },
        ]),
        'includeZombies': true,
      });
      expect(full.includesZombies, isTrue);
      expect(full.formation.pieces.single.type, 'dolphin');
      expect(full.formation.pieces.single.websitePixelX, 287.25);
      expect(ZombieLayout.gameType('pea'), isNull);
      expect(ZombieLayout.gameType('dolphin'), 14);
    },
  );
}
