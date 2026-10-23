import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/original_catalog.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';

void main() {
  test(
      'all captured formations and partial patterns import without dropped records',
      () {
    for (final preset in [
      ...OriginalCatalog.formations,
      ...OriginalCatalog.cobLayouts,
      ...OriginalCatalog.gloomLayouts
    ]) {
      final f = preset.decode();
      expect(f.pieces.length,
          preset.source.split(',').length - (preset.partial ? 0 : 1),
          reason: preset.name);
      final restored = ProjectCodec.decode(ProjectCodec.encode(f));
      expect(restored.toJson(), f.toJson(), reason: preset.name);
    }
  });
  test('seed slots survive project save and reject unknown types', () {
    final f = Formation(seedSlots: ['pea', 'gloom']);
    expect(ProjectCodec.decode(ProjectCodec.encode(f)).seedSlots,
        ['pea', 'gloom']);
    final j = f.toJson();
    j['seedSlots'] = ['unknown'];
    expect(() => Formation.fromJson(j), throwsFormatException);
  });

  test('original map indices retain source ordering and project round trip',
      () {
    expect(OriginalCatalog.maps.length, 26);
    for (final record in OriginalCatalog.maps) {
      final map = BoardMap.byId(record['id'] as String);
      expect(map.originalIndex, record['index']);
      expect(WebsiteCodec.decode('${map.originalIndex}').mapId, map.id);
      expect(WebsiteCodec.encode(Formation(mapId: map.id)),
          '${map.originalIndex}');
      expect(
          ProjectCodec.decode(ProjectCodec.encode(Formation(mapId: map.id)))
              .mapId,
          map.id);
    }
    expect(BoardMap.byId('pool').waterRows, [2, 3]);
    expect(BoardMap.byId('day3').rows, 5);
    expect(BoardMap.byId('day3').activePlantRows, [1, 2, 3]);
    expect(BoardMap.byId('day1').rows, 5);
    expect(BoardMap.byId('day1').activePlantRows, [2]);
    expect(BoardMap.byId('roof6').geometryVerified, isFalse);
  });
  test('original partial cannon layout preserves water containers', () {
    final layout = OriginalCatalog.cobLayouts.first.decode();
    expect(layout.pieces.where((p) => p.type == 'cob').length, 2);
    expect(layout.pieces.where((p) => p.type == 'lily').length, 4);
    expect(layout.pieces.first.row, 2);
  });
  test('source manifest agrees with bundled original records', () {
    final file =
        jsonDecode(File('assets/original_catalog.json').readAsStringSync());
    expect(file, OriginalCatalog.data);
    expect(OriginalCatalog.templates.length, 97);
    expect(OriginalCatalog.formations.length, 363);
    expect(OriginalCatalog.gloomLayouts.length, 21);
    expect(OriginalCatalog.formations.first.source, startsWith('0,'));
  });
}
