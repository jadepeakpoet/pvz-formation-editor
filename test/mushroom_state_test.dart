import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/toolkit_codec.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/domain/formation_formatter.dart';

Piece plant(String type, {int? frameRow, bool? asleep}) => Piece(
    id: type,
    type: type,
    row: 0,
    col: 0,
    layer: ObjectSpec.byId(type).layer,
    frameRow: frameRow,
    asleep: asleep);

void main() {
  test('card defaults wake fume, gloom and magnet; other mushrooms sleep',
      () {
    for (final type in Piece.mushroomTypes) {
      final p = plant(type, frameRow: Piece.defaultPlantFrame(type).$1);
      final awake = {'fume', 'gloom', 'magnet'}.contains(type);
      expect(p.frameRow, awake ? 1 : 0, reason: type);
      expect(p.asleep, !awake, reason: type);
      final decoded =
          ToolkitCodec.decode(ToolkitCodec.encode(Formation(pieces: [p])));
      expect(decoded.pieces.single.asleep, p.asleep, reason: type);
      expect(decoded.pieces.single.frameRow, p.frameRow, reason: type);
    }
  });
  test('defaults belong to card selection; export uses the selected frame', () {
    for (final type in ['fume', 'gloom', 'magnet']) {
      // Raw/imported row zero remains asleep even for default-awake cards.
      final p = plant(type, frameRow: 0, asleep: false);
      expect(p.asleep, true);
      expect(ToolkitCodec.decode(ToolkitCodec.encode(Formation(pieces: [p])))
          .pieces.single.asleep, true);
      expect(plant(type, frameRow: 1, asleep: true).asleep, false);
    }
  });
  test('appearance selection and explicit sleep flag agree in both directions',
      () {
    for (final type in Piece.mushroomTypes) {
      final sleeping = plant(type, asleep: true);
      expect(sleeping.frameRow, 0);
      final awake = sleeping.copy(frameRow: 1);
      expect(awake.asleep, false);
      expect(awake.copy(col: 2).asleep, false);
      expect(awake.copy(asleep: true).frameRow, 0);
      expect(sleeping.copy(asleep: false).frameRow, 1);
      expect(awake.copy(frameRow: 0).asleep, true);
      expect(Piece.fromJson(awake.toJson()).asleep, false);
      expect(Piece.fromJson(sleeping.toJson()).asleep, true);
    }
  });
  test('website frames and legacy project frames retain ice/doom sleep states',
      () {
    for (final type in ['ice', 'doom', 'fume', 'gloom']) {
      for (final row in [0, 1]) {
        final p = plant(type, frameRow: row);
        final f = Formation(pieces: [p]);
        final decoded =
            WebsiteCodec.decode(WebsiteCodec.encode(f)).pieces.single;
        expect(decoded.asleep, row == 0);
        expect(decoded.frameRow, row);
        final legacy = p.toJson()..remove('asleep');
        expect(Piece.fromJson(legacy).asleep, row == 0);
        final formatted = FormationFormatter.format(f);
        final toolkit = ToolkitCodec.decode(ToolkitCodec.encode(formatted));
        expect(toolkit.pieces.single.asleep, row == 0);
      }
    }
  });
  test('night-time Toolkit import renders awake instead of a sleeping sprite',
      () {
    final awake = plant('ice', asleep: false);
    final f = Formation(mapId: 'night', pieces: [awake]);
    final decoded = ToolkitCodec.decode(ToolkitCodec.encode(f));
    expect(decoded.pieces.single.asleep, false);
    expect(decoded.pieces.single.frameRow, 1);
  });
}
