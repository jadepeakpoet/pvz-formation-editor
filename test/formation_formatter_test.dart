import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/domain/formation_formatter.dart';
import 'package:pvz_formation_editor/domain/toolkit_codec.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';

Piece p(String id, String type, {int col = 0, int row = 0}) => Piece(
    id: id, type: type, row: row, col: col, layer: ObjectSpec.byId(type).layer);
void main() {
  test('later main wins across cannon footprint; independent slots survive',
      () {
    final result = FormationFormatter.format(Formation(pieces: [
      p('base', 'lily'),
      p('shell', 'pumpkin', col: 1),
      p('old', 'pea', col: 1),
      p('cannon', 'cob'),
      p('coffee', 'coffee'),
      p('ladder', 'ladder'),
      p('new', 'sunflower', col: 1),
    ]));
    expect(result.pieces.map((e) => e.id), ['base', 'coffee', 'ladder', 'new']);
    expect(ToolkitCodec.exportIssues(result), isEmpty);
    expect(ToolkitCodec.decode(ToolkitCodec.encode(result)).pieces.length, 4);
  });
  test('later shell clears cannon, invalid later cannon does not evict', () {
    final result = FormationFormatter.format(Formation(pieces: [
      p('cannon', 'cob'),
      p('shell', 'pumpkin', col: 1),
      p('valid', 'pea', col: 8),
      p('invalid', 'cob', col: 8),
    ]));
    expect(result.pieces.map((e) => e.id), ['shell', 'valid']);
  });
  test('normalizes scene metadata and unsupported visual properties', () {
    final result = FormationFormatter.format(
        Formation(mapId: 'moonRoof6', sunValue: 1, fogColumns: 3, seedSlots: [
      'pea'
    ], imitaterSeedSlots: {
      0
    }, pieces: [
      Piece(
          id: 'plant',
          type: 'puff',
          row: 0,
          col: 0,
          layer: 90,
          scale: 2,
          opacity: .3,
          frameCol: 2,
          frameRow: 3,
          asleep: true,
          flipped: true,
          flippedVertical: true,
          effects: {'冰冻', '模仿者'},
          appearance: '轮廓',
          websiteFields: ['0', '1', '1', '0', '0', '0', '1', '0', '23', '42']),
      p('unsupported', 'explosion'),
      p('outside', 'pea', row: 5)
    ]));
    expect(result.mapId, 'moonRoof');
    expect(result.seedSlots, isEmpty);
    expect(result.imitaterSeedSlots, isEmpty);
    expect(result.sunValue, 9990);
    expect(result.fogColumns, 0);
    expect(result.pieces.single.id, 'plant');
    expect(result.pieces.single.asleep, isFalse);
    expect(result.pieces.single.websiteFields, isNull);
    expect(result.pieces.single.effects, {'模仿者'});
    expect(ToolkitCodec.exportIssues(result), isEmpty);
    expect(ToolkitCodec.decode(ToolkitCodec.encode(result)).pieces.length, 1);
    expect(FormationFormatter.format(result).fingerprint, result.fingerprint);
  });
  test('all supported types produce decodable toolkit with later base winner',
      () {
    for (final type in WebsiteCodec.plantIds) {
      final result =
          FormationFormatter.format(Formation(pieces: [p(type, type)]));
      expect(ToolkitCodec.exportIssues(result), isEmpty, reason: type);
      expect(
          ToolkitCodec.decode(ToolkitCodec.encode(result)).pieces.single.type,
          type);
    }
    final result = FormationFormatter.format(Formation(
        pieces: [p('lily', 'lily'), p('pot', 'pot'), p('grave', 'grave')]));
    expect(result.pieces.single.type, 'grave');
  });
  test('website conversion and project passthrough', () {
    final source = Formation(
        mapId: 'day6',
        pieces: [p('a', 'pea'), p('b', 'sunflower'), p('fx', 'explosion')]);
    final result =
        FormationFormatter.format(source, format: FormationFormat.website);
    expect(WebsiteCodec.exportIssues(result), isEmpty);
    expect(WebsiteCodec.decode(WebsiteCodec.encode(result)).pieces.single.type,
        'sunflower');
    expect(FormationFormatter.format(source, format: FormationFormat.project),
        same(source));
  });
  test('all website kinds sharing a cell normalize to exportable slots', () {
    final types = [...WebsiteCodec.plantIds, ...WebsiteCodec.extraIds.values];
    final source = Formation(pieces: [
      for (var i = 0; i < types.length; i++) p('first-$i', types[i]),
      for (var i = 0; i < types.length; i++) p('last-$i', types[i]),
    ]);
    final result =
        FormationFormatter.format(source, format: FormationFormat.website);
    expect(WebsiteCodec.exportIssues(result), isEmpty);
    expect(result.pieces.every((p) => p.id.startsWith('last-')), isTrue);
    expect(WebsiteCodec.decode(WebsiteCodec.encode(result)).pieces.length,
        result.pieces.length);
  });
}
