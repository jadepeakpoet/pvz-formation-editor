import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/domain/toolkit_codec.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/domain/plant_game_state.dart';

void main() {
  test('game-read code preserves stable states and retains compact ordinary layouts', () {
    final plain = Formation(pieces: [
      Piece(id: 'pea', type: 'pea', row: 0, col: 0, layer: 10),
    ]);
    expect(FormationExchange.detectFormat(FormationExchange.encodeGameRead(plain)),
        FormationFormat.toolkit);
    for (final p in [
      Piece(id: 'cob', type: 'cob', row: 0, col: 0, layer: 10, frameCol: 2),
      Piece(id: 'nut', type: 'wallnut', row: 0, col: 0, layer: 10, frameCol: 3),
      Piece(id: 'mine', type: 'potato', row: 0, col: 0, layer: 10, frameCol: 1),
      Piece(id: 'sun', type: 'sunshroom', row: 0, col: 0, layer: 10, frameRow: 1, frameCol: 2),
    ]) {
      final code = FormationExchange.encodeGameRead(Formation(pieces: [p]));
      expect(FormationExchange.detectFormat(code), FormationFormat.website);
      final restored = FormationExchange.decode(code).pieces.single;
      expect(PlantGameState.of(restored), PlantGameState.of(p), reason: p.type);
      expect(restored.asleep, p.asleep, reason: p.type);
    }
  });
  test('auto import preserves JSON and legacy PVZF1 including BOM', () {
    final source = Formation(mapId: 'roof', sunValue: 1234, seedSlots: ['pea']);
    for (final value in [
      ProjectCodec.encode(source),
      ProjectCodec.appString(source)
    ]) {
      expect(FormationExchange.decode('\uFEFF  $value \n').toJson(),
          source.toJson());
      expect(FormationExchange.detectFormat(value), FormationFormat.project);
    }
  });
  test('website auto import includes valid empty map strings', () {
    for (final source in [Formation(), Formation(mapId: 'roof')]) {
      final value = WebsiteCodec.encode(source);
      expect(FormationExchange.detectFormat(value), FormationFormat.website);
      expect(FormationExchange.decode(value).mapId, source.mapId);
    }
    expect(FormationExchange.decode('0,0 1 1 0 0 0').pieces.single.type, 'pea');
  });
  test('default encode is Toolkit and detected Toolkit imports', () {
    final source = Formation();
    final encoded = FormationExchange.encode(source);
    expect(encoded, ToolkitCodec.encode(source));
    expect(FormationExchange.decode(encoded).mapId, source.mapId);
    expect(FormationExchange.detectFormat(encoded), FormationFormat.toolkit);
  });
  test('format selection keeps project lossless and exports placement only',
      () {
    final source = Formation(sunValue: 22, seedSlots: ['pea']);
    expect(
        FormationExchange.exportIssues(source, format: FormationFormat.project),
        isEmpty);
    expect(
        FormationExchange.exportIssues(source, format: FormationFormat.website),
        isEmpty);
    expect(FormationExchange.exportIssues(source), isEmpty);
    for (final format in [FormationFormat.website, FormationFormat.toolkit]) {
      final restored = FormationExchange.decode(
          FormationExchange.encode(source, format: format));
      expect(restored.sunValue, 9990);
      expect(restored.seedSlots, isEmpty);
    }
    expect(
        FormationExchange.decode(FormationExchange.encode(source,
                format: FormationFormat.project))
            .toJson(),
        source.toJson());
    expect(FormationFormat.toolkit.fileExtension, 'txt');
    expect(FormationFormat.website.fileExtension, 'txt');
    expect(FormationFormat.project.fileExtension, 'pvzf.json');
  });
  test('game session metadata and preset pose do not block placement export',
      () {
    final source = Formation(
        sunValue: 50,
        seedSlots: ['pea'],
        imitaterSeedSlots: {0},
        fogColumns: 3,
        display: {'坐标': true});
    final before = source.toJson();
    expect(FormationExchange.exportIssues(source), isEmpty);
    expect(FormationExchange.decode(FormationExchange.encode(source)).sunValue,
        9990);
    expect(source.toJson(), before);
    final preset = LibraryPresets.all.first.document;
    final original = preset.toJson();
    final normalized = FormationExchange.layoutDocument(preset);
    expect(
        normalized.pieces.every((p) =>
            p.frameRow == (Piece.mushroomTypes.contains(p.type) && !p.asleep ? 1 : 0) &&
            p.frameCol == 0 && p.websiteFields == null),
        isTrue);
    expect(normalized.pieces.map((p) => p.asleep),
        preset.pieces.map((p) => p.asleep));
    expect(FormationExchange.exportIssues(preset), isEmpty);
    expect(
        FormationExchange.decode(FormationExchange.encode(preset))
            .pieces
            .length,
        preset.pieces.length);
    expect(preset.toJson(), original);
    expect(
        identical(
            FormationExchange.layoutDocument(preset,
                format: FormationFormat.project),
            preset),
        isTrue);
  });
  test('normalization keeps genuine unsupported attributes and website visuals',
      () {
    final source = WebsiteCodec.decode('0,0 1 1 2 3 0 1 0');
    final website = FormationExchange.layoutDocument(source,
        format: FormationFormat.website);
    expect(website.pieces.single.toJson(), source.pieces.single.toJson());
    final zombie = Piece(
        id: 'z',
        type: 'zombie',
        row: 0,
        col: 0,
        layer: ObjectSpec.byId('zombie').layer);
    expect(FormationExchange.exportIssues(Formation(pieces: [zombie])),
        isNotEmpty);
    final asleep = Piece(
        id: 's',
        type: 'puff',
        row: 0,
        col: 0,
        layer: ObjectSpec.byId('puff').layer,
        asleep: true);
    final sleeping = Formation(mapId: 'day', pieces: [asleep]);
    expect(FormationExchange.exportIssues(sleeping), isEmpty);
    expect(
        FormationExchange.decode(FormationExchange.encode(sleeping))
            .pieces
            .single
            .asleep,
        isTrue);
    expect(
        FormationExchange.exportIssues(sleeping,
            format: FormationFormat.website),
        isEmpty);
    expect(
        FormationExchange.decode(FormationExchange.encode(sleeping,
            format: FormationFormat.website)).pieces.single.asleep,
        isTrue);
    final awake = sleeping.copy(pieces: [asleep.copy(frameRow: 1)]);
    expect(FormationExchange.decode(FormationExchange.encode(awake,
        format: FormationFormat.website)).pieces.single.asleep, isFalse);
    for (final changed in [
      asleep.copy(scale: 2),
      asleep.copy(opacity: .5),
      asleep.copy(flipped: true),
      asleep.copy(layer: 99),
      asleep.copy(effects: {'冰冻'})
    ]) {
      expect(FormationExchange.exportIssues(sleeping.copy(pieces: [changed])),
          isNotEmpty);
    }
    expect(FormationFormat.toolkit.description, contains('不保存'));
    expect(FormationFormat.project.description, contains('完整'));
  });
  test('empty and oversized input rejected', () {
    expect(() => FormationExchange.decode(' \uFEFF '), throwsFormatException);
    expect(() => FormationExchange.decode('x' * (ProjectCodec.maxBytes + 1)),
        throwsFormatException);
  });
}
