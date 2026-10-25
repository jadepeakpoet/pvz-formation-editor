import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  await OriginalAssets.ensureLoaded();
  final repository = await FormationRepository.open(':memory:');
  final session = EditorSession(repository, persistDraft: false);
  final key = GlobalKey();
  final h = ParityHarness(key, await Directory.systemTemp.createTemp('pvz-cannon-support-'));
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(key: key, child: MaterialApp(home: app.EditorPage(
      session: session, continueArchive: (_) async {}))));
  await h.settle(); await h.settle();
  final dynamic page = (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  page.selectToolboxTab(1);
  await h.settle();
  List<Piece> cannon(String id, int row, int col, String base) => [
    Piece(id: id, type: 'cob', row: row, col: col, layer: 10),
    for (final cell in [col, col + 1]) Piece(id: '$id-base-$cell', type: base,
      row: row, col: cell, layer: 0, effects: {'模仿者'}),
  ];
  List<String> shape(Formation f) => f.pieces.map((p) => '${p.type}:${p.row}:${p.col}').toList()..sort();
  var cases = 0;
  for (final value in [
    ('roof', '碾花盆', <Piece>[...cannon('land', 0, 1, 'pot')], {'land-base-2'}),
    ('pool', '炸荷叶', <Piece>[...cannon('water', 2, 1, 'lily')], {'water-base-2'}),
    ('roof', '碾花盆', <Piece>[
      ...cannon('a', 0, 0, 'pot'), ...cannon('b', 0, 2, 'pot'),
      ...cannon('edge', 0, 7, 'pot')], {'a-base-1', 'b-base-3', 'edge-base-8'}),
    ('pool', '碾花盆', <Piece>[
      ...cannon('land', 0, 1, 'pot'), ...cannon('water', 2, 1, 'lily')], {'land-base-2'}),
    ('pool', '炸荷叶', <Piece>[
      ...cannon('land', 0, 1, 'pot'), ...cannon('water', 2, 1, 'lily')], {'water-base-2'}),
  ]) {
    final before = Formation(mapId: value.$1, pieces: value.$3);
    session.execute('fixture', before);
    await h.settle();
    await h.tapElement(h.find((w) => w.key == ValueKey('lazy-action-${value.$2}')));
    final after = session.document;
    h.expect(before.pieces.map((p) => p.id).toSet().difference(after.pieces.map((p) => p.id).toSet()).difference(value.$4).isEmpty &&
        after.pieces.length == before.pieces.length - value.$4.length,
        'Button must remove only the cannon front support: ${value.$1}/${value.$2}');
    for (final format in [FormationFormat.toolkit, FormationFormat.website]) {
      final decoded = FormationExchange.decode(FormationExchange.encode(after, format: format));
      h.expect(shape(decoded).join('|') == shape(after).join('|'), 'Export must not restore removed bases: $format');
    }
    session.undo();
    h.expect(session.document.fingerprint == before.fingerprint, 'Undo must restore both supports');
    session.redo();
    h.expect(session.document.fingerprint == after.fingerprint, 'Redo must remove the front support');
    cases++;
  }
  h.expect(h.errors.isEmpty, h.errors.map((e) => e.exceptionAsString()).join('\n'));
  stdout.writeln('PASS $cases actual lazy-layout button cases, adjacent/edge cannons, mixed terrain, undo/redo and Toolkit/website exchange');
  runApp(const SizedBox.shrink()); await h.settle();
  session.dispose(); await repository.close(); exit(0);
}
