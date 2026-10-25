import 'dart:convert';
import 'package:flutter/services.dart';
import '../domain/formation.dart';
import '../domain/original_catalog.dart';

/// A built-in source formation. Browsing never creates a user database record.
class LibraryPreset {
  final String id, name;
  final OriginalPreset _source;
  LibraryPreset._(this._source)
      : id = 'original-${_source.index}',
        name = _source.name;

  LibraryPreset.layout(OriginalPreset source, String group)
      : _source = source,
        _mapId = layoutMapId(source),
        id = '$group-${source.index}',
        name = source.name;
  String? _mapId;

  /// Partial sources have no map header; their family names define the scene.
  static String layoutMapId(OriginalPreset source) {
    if (source.name.startsWith('泳池-')) return 'pool';
    if (source.name.startsWith('草地-')) return 'day';
    if (source.name.startsWith('屋顶-')) return 'roof';
    throw FormatException('Unknown layout scene: ${source.name}');
  }

  // Browsing uses lightweight bundled metadata. Full documents are needed only
  // for editing/detail/apply, and the recent-document cache has a fixed bound.
  static final _documents = <LibraryPreset, Formation>{};
  static int get cachedDocumentCount => _documents.length;
  static void clearDocumentCache() => _documents.clear();
  Formation get document {
    final cached = _documents.remove(this);
    final value = cached ?? _source.decode(mapId: _mapId ?? 'pool');
    _documents[this] = value;
    while (_documents.length > 24) {
      _documents.remove(_documents.keys.first);
    }
    return value;
  }

  Map<String, dynamic>? get _preview => LibraryPresets.previewMetadata[id];
  String? get thumbnailKey => _preview?['key'] as String?;
  int get cannonCount =>
      _preview?['cannons'] as int? ??
      document.pieces.where((p) => p.type == 'cob').length;
  int get objectCount => _preview?['objects'] as int? ?? document.pieces.length;
  String get mapId => _mapId ?? (_preview?['map'] as String?) ?? document.mapId;
  int get sourceIndex => _source.index;
}

class LibraryPresets {
  static final previewMetadata = <String, Map<String, dynamic>>{};
  static Future<void>? _previewLoading;
  static Future<void> ensurePreviewIndex() => _previewLoading ??= (() async {
        final data = jsonDecode(await rootBundle
            .loadString('assets/original/preset_previews.json')) as Map;
        previewMetadata.addAll((data['presets'] as Map).map((key, value) =>
            MapEntry(key as String, Map<String, dynamic>.from(value as Map))));
      })();
  static final List<LibraryPreset> all = List.unmodifiable(
      OriginalCatalog.formations.map((preset) => LibraryPreset._(preset)));
}
