// Run with the Flutter engine, then run tool/compress_builtin_thumbnails.py.
import 'dart:io';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/library/thumbnail_store.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = Directory('build/builtin-thumbnails');
  await dir.create(recursive: true);
  final metadata = <String, dynamic>{};
  for (final preset in LibraryPresets.all) {
    final doc = preset.document;
    final key = ThumbnailStore.key(doc);
    final bytes = await exportPng(doc.copy(display: const {}), multiplier: .32);
    await File('${dir.path}/$key.png').writeAsBytes(bytes);
    metadata[preset.id] = {
      'key': key,
      'map': doc.mapId,
      'cannons': doc.pieces.where((p) => p.type == 'cob').length,
      'objects': doc.pieces.length
    };
  }
  await File('${dir.path}/index.json').writeAsString(jsonEncode({
    'version': 3,
    'width': 256,
    'height': 192,
    'keys': metadata.values.map((v) => v['key']).toSet().toList(),
    'presets': metadata
  }));
  stdout.writeln('Prepared ${metadata.length} built-in previews');
  exit(0);
}
