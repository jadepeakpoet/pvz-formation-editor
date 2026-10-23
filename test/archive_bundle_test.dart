import 'dart:convert';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/archive_bundle.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

ArchiveRecord record(String id, String name, Formation document) =>
    ArchiveRecord(
        id: id,
        name: name,
        document: document.toJson(),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        favorite: true,
        tags: ['中文', '标签'],
        note: '备注\n第二行');

void main() {
  test('import identity ignores regenerated object IDs but preserves content',
      () {
    Formation plant(String id, {int sun = 9990}) => Formation(
        sunValue: sun,
        pieces: [Piece(id: id, type: 'pea', row: 0, col: 0, layer: 10)]);
    expect(ArchiveBundle.importFingerprint(plant('first')),
        ArchiveBundle.importFingerprint(plant('regenerated')));
    expect(ArchiveBundle.importFingerprint(plant('first')),
        isNot(ArchiveBundle.importFingerprint(plant('first', sun: 1234))));
  });
  test('single, subset and entire collection preserve names and full projects',
      () {
    final records = [
      record('one', '我的阵型', Formation()),
      record('two', '我的阵型（2）', Formation().copy(sunValue: 1234)),
      record('three', '引号"与\n换行', Formation().copy(mapId: 'day')),
    ];
    for (final selection in [
      records.take(1).toList(),
      records.sublist(1),
      records
    ]) {
      final text = ArchiveBundle.encode(selection);
      expect(ArchiveBundle.recognizes(text), isTrue);
      final decoded = ArchiveBundle.decode(text);
      expect(decoded.length, selection.length);
      for (var i = 0; i < decoded.length; i++) {
        expect(decoded[i].name, selection[i].name);
        expect(decoded[i].document.fingerprint,
            Formation.fromJson(selection[i].document).fingerprint);
        expect(decoded[i].tags, selection[i].tags);
        expect(decoded[i].note, selection[i].note);
        expect(decoded[i].favorite, isTrue);
      }
    }
  });
  test('toolkit included when representable, identity omitted', () {
    final encoded = jsonDecode(
        ArchiveBundle.encode([record('local-id', '阵', Formation())]));
    final row = encoded['archives'][0];
    expect(row.containsKey('id'), isFalse);
    expect(FormationExchange.decode(row['toolkit']).pieces, isEmpty);
  });
  test('recognition distinguishes ordinary single project and invalid JSON',
      () {
    expect(ArchiveBundle.recognizes(ProjectCodec.encode(Formation())), isFalse);
    expect(ArchiveBundle.recognizes('not json'), isFalse);
    expect(ArchiveBundle.recognizes('[]'), isFalse);
  });
  test('validates entire collection and rejects malformed later entry', () {
    final data =
        jsonDecode(ArchiveBundle.encode([record('a', '阵', Formation())]));
    data['archives'].add({'name': '坏条目'});
    expect(() => ArchiveBundle.decode(jsonEncode(data)), throwsFormatException);
    data['archives'].removeLast();
    data['version'] = 99;
    expect(() => ArchiveBundle.decode(jsonEncode(data)), throwsFormatException);
  });
  test('empty and oversized collections rejected', () {
    expect(() => ArchiveBundle.encode([]), throwsFormatException);
    expect(
        () => ArchiveBundle.decode(jsonEncode(
            {'type': ArchiveBundle.type, 'version': 1, 'archives': []})),
        throwsFormatException);
    expect(() => ArchiveBundle.decode(' ' * (ArchiveBundle.maxBytes + 1)),
        throwsFormatException);
  });
}
