import 'dart:convert';
import 'formation.dart';
import 'formation_exchange.dart';
import '../storage/formation_repository.dart';

/// Portable collection backup. IDs are intentionally omitted: importing a
/// collection creates independent documents without overwriting local work.
class ArchiveBundle {
  static const type = 'pvzstudio.archive-collection';
  static const maxBytes = 8 * 1024 * 1024;
  static const maxEntries = 10000;

  /// Importers may generate fresh editor object IDs for identical layouts.
  /// Those IDs are local identity, not formation content.
  static String importFingerprint(Formation document) {
    final data = document.toJson();
    data['objects'] = (data['objects'] as List).map((object) {
      final content = Map<String, dynamic>.from(object as Map);
      content.remove('id');
      return content;
    }).toList();
    return jsonEncode(data);
  }

  static bool recognizes(String text) {
    try {
      final value = jsonDecode(text);
      return value is Map && value['type'] == type;
    } catch (_) {
      return false;
    }
  }

  static String encode(List<ArchiveRecord> records) {
    if (records.isEmpty || records.length > maxEntries) {
      throw const FormatException('请选择需要导出的存档');
    }
    final text = const JsonEncoder.withIndent('  ').convert({
      'type': type,
      'version': 1,
      'archives': records.map((a) {
        final document = Formation.fromJson(a.document);
        String? toolkit;
        if (FormationExchange.exportIssues(document,
                format: FormationFormat.toolkit)
            .isEmpty) {
          toolkit = FormationExchange.encode(document);
        }
        return {
          'name': a.name,
          'note': a.note,
          'tags': a.tags,
          'favorite': a.favorite,
          'document': document.toJson(),
          if (toolkit != null) 'toolkit': toolkit,
        };
      }).toList(),
    });
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('批量存档文件超过 8 MiB，请分批导出');
    }
    return text;
  }

  /// Validate the entire collection before any caller persists its documents.
  static List<ArchiveBundleEntry> decode(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('批量存档文件超过 8 MiB');
    }
    final value = jsonDecode(text);
    if (value is! Map || value['type'] != type || value['version'] != 1) {
      throw const FormatException('不支持的批量存档格式或版本');
    }
    final entries = value['archives'];
    if (entries is! List || entries.isEmpty || entries.length > maxEntries) {
      throw const FormatException('批量存档数量无效');
    }
    return entries.map((entry) {
      if (entry is! Map ||
          entry['name'] is! String ||
          (entry['name'] as String).trim().isEmpty ||
          entry['note'] is! String ||
          entry['tags'] is! List ||
          (entry['tags'] as List).any((t) => t is! String) ||
          entry['favorite'] is! bool ||
          entry['document'] is! Map) {
        throw const FormatException('批量存档条目无效');
      }
      final document = Map<String, dynamic>.from(entry['document'] as Map);
      if (utf8.encode(jsonEncode(document)).length > ProjectCodec.maxBytes) {
        throw const FormatException('单个阵型超过 8 MiB');
      }
      return ArchiveBundleEntry(
          (entry['name'] as String).trim(),
          entry['note'] as String,
          List<String>.from(entry['tags'] as List),
          entry['favorite'] as bool,
          Formation.fromJson(document));
    }).toList();
  }
}

class ArchiveBundleEntry {
  final String name, note;
  final List<String> tags;
  final bool favorite;
  final Formation document;
  ArchiveBundleEntry(
      this.name, this.note, this.tags, this.favorite, this.document);
}
