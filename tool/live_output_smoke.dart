// Real Flutter editor. Clipboard is simulated; no native windows or game process.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/domain/original_catalog.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final key = GlobalKey();
  final directory = Directory('/tmp/pvz-live-output');
  await directory.create(recursive: true);
  final h = ParityHarness(key, directory);
  FlutterError.onError = h.errors.add;
  var session = EditorSession(repo, persistDraft: false);
  String clipboard = '';
  ParityBinding.handlers[SystemChannels.platform.name] = (call) async {
    if (call.method == 'Clipboard.setData') {
      clipboard = (call.arguments as Map)['text'] as String;
    }
    return null;
  };
  Future<void> mount() async {
    runApp(RepaintBoundary(
        key: key,
        child: MaterialApp(
            key: UniqueKey(),
            theme: ThemeData(useMaterial3: true),
            home: app.EditorPage(
                session: session, continueArchive: (_) async {}))));
    await h.settle();
    await h.settle();
    await h.tap('载入导出');
  }

  TextField output() =>
      h.find((w) => w.key == const ValueKey('formation-live-output')).widget
          as TextField;
  void matches() {
    final encoded = output().controller!.text;
    h.expect(encoded == FormationExchange.encode(session.document),
        'Live output differs from current formation');
  }

  await mount();
  await h.run('live.initial', 'Initial automatic readonly Toolkit code',
      () async {
    matches();
    h.expect(output().readOnly, 'Output must be readonly');
    h.expect(
        h
            .all((w) =>
                w is Text &&
                ['获取', '清空输出', '获取 PVZF1', '搜索卡片'].contains(w.data))
            .isEmpty,
        'Removed controls remain');
  });
  await h.run(
      'live.pointer-history', 'Actual board plant, undo and redo refresh code',
      () async {
    final board = h
        .find((w) => w is CustomPaint && w.painter is BoardPainter)
        .renderObject as RenderBox;
    await h.tapAt(
        board.localToGlobal(BoardGeometry(session.document).cellCenter(0, 0)));
    matches();
    h.expect(
        FormationExchange.decode(output().controller!.text).pieces.length == 1,
        'Plant output stale');
    await h.tap('撤销');
    matches();
    h.expect(FormationExchange.decode(output().controller!.text).pieces.isEmpty,
        'Undo output stale');
    await h.tap('重做');
    matches();
    h.expect(
        FormationExchange.decode(output().controller!.text).pieces.length == 1,
        'Redo output stale');
  });
  await h.run('live.commands',
      'Map, source preset and session commands refresh automatically',
      () async {
    session.execute('map command', Formation(mapId: 'roof'));
    await h.settle();
    matches();
    session.execute('source preset', OriginalCatalog.formations[1].decode());
    await h.settle();
    matches();
    session.execute('clear command', session.document.copy(pieces: []));
    await h.settle();
    matches();
  });
  await h.run('live.formats-copy',
      'Clipboard output fixed to Toolkit with no format switch', () async {
    h.expect(
        h
            .all((w) => w.key == const ValueKey('formation-export-format'))
            .isEmpty,
        'Clipboard output must not expose a Website/JSON format switch');
    matches();
    await h
        .tapElement(h.find((w) => w.key == const ValueKey('formation-copy')));
    h.expect(
        clipboard == output().controller!.text &&
            clipboard == FormationExchange.encode(session.document),
        'Clipboard must contain exact Toolkit placement code');
  });
  await h.run('live.unsupported',
      'Unsupported state clears stale code, disables copy and recovers',
      () async {
    final before = output().controller!.text;
    session.execute(
        'unsupported zombie',
        Formation(pieces: [
          Piece(
              id: 'unsupported',
              type: 'zombie',
              row: 0,
              col: 0,
              layer: ObjectSpec.byId('zombie').layer)
        ]));
    await h.settle();
    h.expect(before.isNotEmpty && output().controller!.text.isEmpty,
        'Unsupported formation retains stale code');
    h.expect(
        h
            .all((w) => w.key == const ValueKey('formation-output-error'))
            .isNotEmpty,
        'Missing inline unsupported error');
    h.expect(
        (h.find((w) => w.key == const ValueKey('formation-copy')).widget
                    as OutlinedButton)
                .onPressed ==
            null,
        'Unsupported copy enabled');
    session.execute('recover', Formation());
    await h.settle();
    matches();
    h.expect(
        (h.find((w) => w.key == const ValueKey('formation-copy')).widget
                    as OutlinedButton)
                .onPressed !=
            null,
        'Copy did not recover');
  });
  await h
      .run('live.readonly', 'Readonly snapshot still auto-encodes without Get',
          () async {
    final old = session;
    session = EditorSession(repo,
        persistDraft: false,
        document: OriginalCatalog.formations[1].decode(),
        readOnly: true);
    await mount();
    old.dispose();
    matches();
    h.expect(output().readOnly && session.readOnly,
        'Readonly snapshot code missing');
  });
  await h.report();
  await File('/tmp/pvz-live-output-report.json').writeAsString(jsonEncode({
    'cases': h.cases,
    'scope':
        'real headless Flutter UI; clipboard simulated; native secondary output checked separately'
  }));
  session.dispose();
  await repo.close();
  exit(h.cases.any((c) => c['status'] != 'pass') ? 1 : 0);
}
