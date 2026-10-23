import 'dart:convert';
import 'package:test/test.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/object_filter.dart';

Formation sample() => Formation(mapId: 'pool', sunValue: 12345, pieces: [
      Piece(id: 'base', type: 'lily', row: 2, col: 3, layer: 0),
      Piece(
          id: 'cannon',
          type: 'cob',
          row: 2,
          col: 3,
          layer: 10,
          scale: 1.4,
          flipped: true,
          flippedVertical: true,
          effects: Piece.allowedEffects.toSet(),
          appearance: '轮廓'),
      Piece(id: 'shell', type: 'pumpkin', row: 2, col: 3, layer: 20),
    ], display: const {
      '阳光': false,
      '迷雾': true
    });

void main() {
  test('removed free board is rejected when loading project data', () {
    final legacy = sample().toJson()
      ..['map'] = 'custom'
      ..['rows'] = 8
      ..['columns'] = 12;
    final project =
        jsonDecode(ProjectCodec.encode(sample())) as Map<String, dynamic>;
    project['document'] = legacy;
    final unsupportedMap = throwsA(isA<FormatException>()
        .having((error) => error.message, 'message', contains('custom')));
    expect(() => Formation.fromJson(legacy), unsupportedMap);
    expect(() => ProjectCodec.decode(jsonEncode(project)), unsupportedMap);
  });
  test('complete project preserves multilayer cross-cell data and effects', () {
    final original = sample();
    final restored = ProjectCodec.decode(ProjectCodec.encode(original));
    expect(restored.toJson(), original.toJson());
    expect(restored.pieces[1].spec.width, 2);
    expect(restored.pieces.map((p) => p.layer), [0, 10, 20]);
    expect(restored.pieces[1].effects, {'冰冻', '魅惑', '高亮', '阴影', '半透明'});
    expect(restored.pieces[1].opacity, .5);
  });
  test('fine removal filters preserve unrelated stack layers', () {
    final stack = [
      'lily',
      'pot',
      'pea',
      'pumpkin',
      'coffee',
      'ladder',
      'grave',
      'rake',
      'zombie',
      'sun'
    ]
        .map((type) => Piece(
            id: type,
            type: type,
            row: 0,
            col: 0,
            layer: ObjectSpec.byId(type).layer))
        .toList();
    expect(
        stack.where((p) => ObjectFilter.matches(p, '普通植物')).map((p) => p.type),
        ['pea']);
    expect(stack.where((p) => ObjectFilter.matches(p, '容器')).map((p) => p.type),
        ['lily', 'pot']);
    expect(
        stack.where((p) => ObjectFilter.matches(p, '物品及特效')).map((p) => p.type),
        ['ladder', 'grave', 'rake', 'sun']);
  });
  test('PVZF1 is application-only and round trips', () {
    expect(
        ProjectCodec.fromAppString(ProjectCodec.appString(sample())).toJson(),
        sample().toJson());
    for (final input in ['1,2,3;4', 'javascript:alert(1)', 'PVZF1:%%%', '']) {
      expect(() => ProjectCodec.fromAppString(input), throwsFormatException);
    }
  });
  test('invalid project versions, resources, schema and fields are rejected',
      () {
    void invalid(void Function(Map<String, dynamic>) mutate) {
      final j =
          jsonDecode(ProjectCodec.encode(sample())) as Map<String, dynamic>;
      mutate(j);
      expect(() => ProjectCodec.decode(jsonEncode(j)), throwsFormatException);
    }

    invalid((j) => j['format'] = 'other');
    invalid((j) => j['version'] = 2);
    invalid((j) => j['resources']['kind'] = 'remote');
    invalid((j) => j['resources']['catalogVersion'] = 99);
    invalid((j) => j['document']['schemaVersion'] = 2);
    invalid((j) => j['document']['board']['rows'] = 99);
    invalid((j) => j['document']['sunValue'] = -1);
    invalid((j) => j['document']['objects'][1]['flippedVertical'] = 'yes');
    invalid((j) => j['document']['objects'][1]['col'] = 8);
    invalid((j) => j['document']['objects'][1]['row'] = -1);
    invalid((j) => j['document']['objects'][1]['id'] = 'base');
    invalid((j) => j['document']['objects'][1]['id'] = '');
    invalid((j) => j['document']['objects'][1]['width'] = 1);
    invalid((j) => j['document']['objects'][1]['scale'] = 4);
    invalid((j) => j['document']['objects'][1]['effects'] = ['unknown']);
    invalid((j) => j['document']['objects'][1]['row'] = '2');
    expect(() => ProjectCodec.decode('[]'), throwsFormatException);
    expect(() => ProjectCodec.decode('{broken'), throwsFormatException);
  });
  test('oversized input and nonfinite scale are rejected', () {
    expect(() => ProjectCodec.decode(' ' * (ProjectCodec.maxBytes + 1)),
        throwsFormatException);
    final j = sample().pieces[1].toJson()..['scale'] = double.nan;
    expect(() => Piece.fromJson(j), throwsFormatException);
  });
}
