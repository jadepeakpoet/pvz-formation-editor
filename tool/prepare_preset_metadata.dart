// Run with the Flutter engine to refresh lightweight preset metadata only.
import 'dart:io';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/library/thumbnail_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final metadata = <String, dynamic>{};
  final selected =
      Platform.environment['PVZ_THUMBNAIL_PRESETS']?.split(',').toSet();
  if (selected != null) {
    final existing = jsonDecode(
      await File('assets/original/preset_previews.json').readAsString(),
    ) as Map;
    metadata.addAll(Map<String, dynamic>.from(existing['presets'] as Map));
  }
  for (final preset in LibraryPresets.all) {
    if (selected != null && !selected.contains(preset.id)) continue;
    final doc = preset.document;
    final key = ThumbnailStore.key(doc);
    metadata[preset.id] = {
      'key': key,
      'map': doc.mapId,
      'cannons': doc.pieces.where((p) => p.type == 'cob').length,
      'objects': doc.pieces.length,
    };
  }
  await File('assets/original/preset_previews.json').writeAsString(
    jsonEncode({
      'version': 3,
      'width': 256,
      'height': 192,
      'presets': metadata,
    }),
  );
  stdout.writeln('Prepared ${metadata.length} preset metadata entries');
  exit(0);
}
