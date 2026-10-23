import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/original_catalog.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';

Map<String, dynamic> semanticDocument(Formation document) {
  final json = document.toJson();
  // Decoding allocates fresh editor object identities; source content is exact.
  for (final object in json['objects'] as List) {
    (object as Map).remove('id');
  }
  return json;
}

void main() {
  test(
      'built-ins contain all 363 full source formations with stable unique IDs',
      () {
    final all = LibraryPresets.all;
    expect(all, hasLength(363));
    expect(all.map((p) => p.id).toSet(), hasLength(363));
    for (var i = 0; i < all.length; i++) {
      expect(all[i].id, 'original-$i');
      expect(all[i].name, OriginalCatalog.formations[i].name);
      expect(OriginalCatalog.formations[i].partial, isFalse);
    }
    expect(identical(all, LibraryPresets.all), isTrue);
    expect(() => all.clear(), throwsUnsupportedError);
  });
  test(
      'every built-in document equals its exact decoded original and is cached',
      () {
    for (var i = 0; i < LibraryPresets.all.length; i++) {
      final preset = LibraryPresets.all[i];
      expect(semanticDocument(preset.document),
          semanticDocument(OriginalCatalog.formations[i].decode()),
          reason: preset.id);
      expect(identical(preset.document, preset.document), isTrue);
      expect(preset.mapId, preset.document.mapId);
      expect(BoardMap.byId(preset.mapId).id, preset.mapId);
    }
  });
  test(
      'source formations retain multiple map groups and exclude partial families',
      () {
    final groups = <String, int>{};
    for (final p in LibraryPresets.all) {
      groups.update(p.mapId, (count) => count + 1, ifAbsent: () => 1);
    }
    expect(groups.keys,
        containsAll(['pool', 'fog', 'day', 'night', 'roof', 'moonRoof']));
    expect(groups.values.reduce((a, b) => a + b), 363);
    expect(
        LibraryPresets.all.first.name, OriginalCatalog.formations.first.name);
    expect(LibraryPresets.all.last.name, OriginalCatalog.formations.last.name);
    expect(LibraryPresets.all.map((p) => p.id), isNot(contains('cob-0')));
    expect(LibraryPresets.all.map((p) => p.id), isNot(contains('gloom-0')));
  });
}
