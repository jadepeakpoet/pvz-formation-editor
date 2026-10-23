import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';

void main() {
  test('SEED-SOURCE gray pea and normal pea occupy distinct persistent slots',
      () {
    // Source: Peashooter_i -> iTenCard_0 then Peashooter -> TenCard_0.
    final evidence = jsonDecode(
            File('test/fixtures/parity/seed-imitater.json').readAsStringSync())
        as Map<String, dynamic>;
    final f = Formation(
        seedSlots: (evidence['expectedSeedSlots'] as List).cast<String>(),
        imitaterSeedSlots: (evidence['expectedImitaterSeedSlots'] as List)
            .cast<int>()
            .toSet());
    final restored = ProjectCodec.decode(ProjectCodec.encode(f));
    expect(restored.seedSlots, ['pea', 'pea']);
    expect(restored.imitaterSeedSlots, {0});
    expect(restored.toJson(), f.toJson());
  });
  test('SEED-IMMUTABLE constructor defensively copies flags and slots', () {
    final slots = ['pea', 'sunflower'];
    final flags = {1};
    final f = Formation(seedSlots: slots, imitaterSeedSlots: flags);
    slots.clear();
    flags.clear();
    expect(f.seedSlots, ['pea', 'sunflower']);
    expect(f.imitaterSeedSlots, {1});
    expect(() => f.imitaterSeedSlots.add(0), throwsUnsupportedError);
  });
  test(
      'SEED-LEGACY empty flags omit JSON key and keep legacy fingerprint exact',
      () {
    final f = Formation(seedSlots: ['pea', 'pea']);
    final legacy = f.toJson();
    expect(legacy.containsKey('imitaterSeedSlots'), isFalse);
    final before = jsonEncode(legacy);
    final restored = Formation.fromJson(legacy);
    expect(restored.imitaterSeedSlots, isEmpty);
    expect(restored.fingerprint, before);
    expect(restored.seedSlots,
        ['pea', 'pea']); // Historical normal duplicates stay readable.
    expect(f.copy(imitaterSeedSlots: {}).fingerprint, before);
  });
  test(
      'SEED-COPY preserves flags unless explicitly replaced, and validates shortened slots',
      () {
    final f =
        Formation(seedSlots: ['pea', 'sunflower'], imitaterSeedSlots: {1});
    expect(f.copy(sunValue: 50).imitaterSeedSlots, {1});
    expect(f.copy(imitaterSeedSlots: {0}).imitaterSeedSlots, {0});
    expect(() => f.copy(seedSlots: ['pea']), throwsFormatException);
    final removed = f.copy(seedSlots: ['sunflower'], imitaterSeedSlots: {0});
    expect(removed.imitaterSeedSlots, {0});
    expect(f.copy(seedSlots: [], imitaterSeedSlots: {}).seedSlots, isEmpty);
  });
  test(
      'SEED-RELEASE removing gray flag permits a new gray card without mutating snapshot',
      () {
    final original =
        Formation(seedSlots: ['pea', 'pea'], imitaterSeedSlots: {0});
    final removed = original.copy(seedSlots: ['pea'], imitaterSeedSlots: {});
    final next =
        removed.copy(seedSlots: ['pea', 'gloom'], imitaterSeedSlots: {1});
    expect(original.imitaterSeedSlots, {0});
    expect(removed.imitaterSeedSlots, isEmpty);
    expect(next.imitaterSeedSlots, {1});
  });
  for (final flags in [
    {-1},
    {0},
    {1},
    {0, 1}
  ]) {
    test('SEED-BOUNDARY constructor rejects $flags on empty/one-slot models',
        () {
      final slots = flags.length > 1 ? ['pea', 'sunflower'] : <String>[];
      expect(() => Formation(seedSlots: slots, imitaterSeedSlots: flags),
          throwsFormatException);
    });
  }
  for (final raw in [
    true,
    '0',
    0,
    [0.0],
    ['0'],
    [true],
    [-1],
    [2],
    [0, 1],
    [0, 0]
  ]) {
    test('SEED-JSON rejects malformed flags ${jsonEncode(raw)}', () {
      final j = Formation(seedSlots: ['pea', 'sunflower']).toJson()
        ..['imitaterSeedSlots'] = raw;
      expect(() => Formation.fromJson(j), throwsFormatException);
    });
  }
  test('SEED-LAST accepts final valid index and explicit empty legacy key', () {
    final f =
        Formation(seedSlots: List.filled(10, 'pea'), imitaterSeedSlots: {9});
    expect(Formation.fromJson(f.toJson()).imitaterSeedSlots, {9});
    final j = Formation(seedSlots: ['pea']).toJson()
      ..['imitaterSeedSlots'] = <int>[];
    expect(Formation.fromJson(j).toJson().containsKey('imitaterSeedSlots'),
        isFalse);
  });
}
