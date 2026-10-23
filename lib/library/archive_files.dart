import 'dart:convert';
import 'dart:typed_data';
import '../domain/archive_bundle.dart';
import '../domain/formation.dart';
import '../platform/project_files.dart';
import '../storage/formation_repository.dart';

class ArchiveFiles {
  static Future<bool> exportCollection(List<ArchiveRecord> archives) async {
    final text = ArchiveBundle.encode(archives);
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return await ProjectFiles.save('存档库-$stamp.pvzlib.json',
            Uint8List.fromList(utf8.encode(text)), 'application/json') !=
        null;
  }

  /// Call only after [ArchiveBundle.recognizes]. Fully validates before writes.
  /// A failed storage operation reports how many items were already imported.
  static Future<ArchiveImportResult> importCollection(
      FormationRepository repository, String text) async {
    final entries = ArchiveBundle.decode(text);
    return importEntries(repository, entries);
  }

  static Future<ArchiveImportResult> importEntries(
      FormationRepository repository, List<ArchiveBundleEntry> entries) async {
    final fingerprints = (await repository.listArchives())
        .map((a) =>
            ArchiveBundle.importFingerprint(Formation.fromJson(a.document)))
        .toSet();
    var imported = 0, skipped = 0, renamed = 0;
    try {
      for (final entry in entries) {
        final fingerprint = ArchiveBundle.importFingerprint(entry.document);
        if (fingerprints.contains(fingerprint)) {
          skipped++;
          continue;
        }
        final name = await repository.uniqueDocumentName(entry.name);
        final archive = await repository.saveArchive(
            id: newId(),
            name: name,
            document: entry.document.toJson(),
            note: entry.note,
            tags: entry.tags,
            uniqueName: true);
        if (entry.favorite) {
          await repository.updateArchiveMetadata(archive.id, favorite: true);
        }
        imported++;
        if (archive.name != entry.name) renamed++;
        fingerprints.add(fingerprint);
      }
      return ArchiveImportResult(imported, skipped, renamed);
    } catch (e) {
      throw StateError('已导入 $imported/${entries.length} 个存档：$e');
    }
  }
}

class ArchiveImportResult {
  final int imported, skipped, renamed;
  const ArchiveImportResult(this.imported, this.skipped, this.renamed);
  @override
  String toString() => '导入 $imported 个，跳过 $skipped 个，重命名 $renamed 个';
}
