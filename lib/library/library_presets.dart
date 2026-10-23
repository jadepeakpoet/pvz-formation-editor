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

  /// Decode on first use, retaining the immutable formation for later previews.
  /// Invalid source data is allowed to fail visibly rather than being substituted.
  late final Formation document = _source.decode(mapId: _mapId ?? 'pool');
  String get mapId => document.mapId;
  int get sourceIndex => _source.index;
}

class LibraryPresets {
  static final List<LibraryPreset> all = List.unmodifiable(
      OriginalCatalog.formations.map((preset) => LibraryPreset._(preset)));
}
