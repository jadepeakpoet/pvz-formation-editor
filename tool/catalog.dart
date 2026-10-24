// Regenerate the distributable resource manifest: dart run tool/catalog.dart.
import 'dart:convert';
import 'dart:io';
import 'package:pvz_formation_editor/domain/formation.dart';

void main(List<String> args) {
  final manifest = {
    'catalogVersion': 1,
    'source': 'Canvas fallback object catalog',
    'objects': ObjectSpec.all
        .map((s) => {
              'id': s.id,
              'name': s.name,
              'category': s.category,
              'image': null,
              'frames': ['默认', '轮廓'],
              'color': s.color,
              'anchor': [0.5, 0.5],
              'offsetCells': [0, s.layer <= 0 ? 0.25 : 0],
              'displaySizeCells': [0.72 * s.width, s.layer <= 0 ? 0.24 : 0.68],
              'occupancy': [s.width, 1],
              'layer': s.layer,
              'effects': Piece.allowedEffects
            })
        .toList()
  };
  final expected = '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
  final file = File('assets/catalog.json');
  if (args.contains('--check')) {
    if (!file.existsSync() ||
        file.readAsStringSync().replaceAll('\r\n', '\n') != expected) {
      throw StateError('资源清单过期，请运行 dart run tool/catalog.dart');
    }
  } else {
    file.writeAsStringSync(expected);
  }
}
