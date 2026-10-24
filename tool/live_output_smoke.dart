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
  final directory = Directory('${Directory.systemTemp.path}/pvz-live-output');
  await directory.create(recursive: true);
  final h = ParityHarness(key, directory);
  FlutterError.onError = h.errors.add;
  var session = EditorSession(repo, persistDraft: false);
  String clipboard = '';
  String? clipboardInput;
  ParityBinding.handlers[SystemChannels.platform.name] = (call) async {
    if (call.method == 'Clipboard.getData') {
      return clipboardInput == null ? null : {'text': clipboardInput};
    }
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
    final dynamic editorState = (h.find((w) => w is app.EditorPage) as StatefulElement).state;
    h.expect(editorState.keepPlantsOnMapChange == true,
        'Changing maps must retain plants by default');
    h.expect(editorState.pokerWidth == false,
        'Image export must preserve the original aspect ratio by default');
    final radios = h.all((w) => w is Radio<FormationFormat>);
    final radioGroups = h.all((w) => w is RadioGroup<FormationFormat>);
    h.expect(radios.length == 4 && radioGroups.length == 2 && radioGroups.every((e) =>
        (e.widget as RadioGroup<FormationFormat>).groupValue == FormationFormat.toolkit),
        'Read and copy each default to Toolkit with two exclusive choices');
    final input = h.find((w) => w.key == const ValueKey('formation-input')).widget as TextField;
    input.controller!.text = 'keep pasted text';
    await h.tapElement(h.find((w) => w.key == const ValueKey('formation-read-format-website')));
    h.expect(input.controller!.text == 'keep pasted text' &&
        (h.find((w) => w.key == const ValueKey('formation-output-format-toolkit')).widget is InkWell),
        'Reading-format choice must preserve pasted input and independent output choice');
    await h.tapElement(h.find((w) => w.key == const ValueKey('formation-read-format-toolkit')));
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
    await h.tap('恢复');
    matches();
    h.expect(
        FormationExchange.decode(output().controller!.text).pieces.length == 1,
        'Redo output stale');
  });
  await h.run('live.clipboard-import', 'Validate clipboard before importing', () async {
    final input = h.find((w) => w.key == const ValueKey('formation-input')).widget as TextField;
    input.controller!.text = 'keep input';
    final before = jsonEncode(session.document.toJson());
    for (final invalid in <String?>[null, '   ', 'invalid formation code']) {
      clipboardInput = invalid;
      await h.tapElement(h.find((w) => w.key == const ValueKey('formation-paste-import')));
      await h.settle();
      h.expect(jsonEncode(session.document.toJson()) == before && input.controller!.text == 'keep input',
          'Invalid clipboard changed the current document or input');
    }
    for (final format in [FormationFormat.toolkit, FormationFormat.website]) {
      final document = OriginalCatalog.formations[1].decode();
      clipboardInput = FormationExchange.encode(document, format: format);
      await h.tapElement(h.find((w) => w.key == const ValueKey('formation-paste-import')));
      await h.settle();
      h.expect(FormationExchange.encode(session.document, format: format) == clipboardInput,
          'Valid clipboard formation was not loaded');
    }
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
  await h.run('live.decorative-layout',
      'Decorations are omitted from executable code with a visible notice', () async {
    session.execute('zombie illustration', Formation(pieces: [
      Piece(id: 'z', type: 'zombie', row: 0, col: 0,
          layer: ObjectSpec.byId('zombie').layer),
    ]));
    await h.settle();
    await h.tapElement(h.find((w) => w.key == const ValueKey('formation-output-format-toolkit')));
    h.expect(FormationExchange.decode(output().controller!.text).pieces.isEmpty,
        'Toolkit layout must omit zombie illustrations');
    h.expect(h.all((w) => w.key == const ValueKey('formation-layout-notice')).isNotEmpty,
        'Omission must be visible before copying or applying');
    h.expect(session.document.pieces.single.type == 'zombie',
        'Extracting output must preserve the original editor document');
  });
  await h.run('live.website-code', 'Website copy keeps zombie states while Toolkit copy stays compatible', () async {
    session.execute('unboxed zombie', Formation(mapId: 'day', pieces: [
      Piece(id: 'jack', type: 'jack', row: 1, col: 1,
          layer: ObjectSpec.byId('jack').layer, frameRow: 1, frameCol: 2),
    ]));
    await h.settle();
    await h.tapElement(h.find((w) => w.key == const ValueKey('formation-output-format-website')));
    await h.tapElement(h.find((w) => w.key == const ValueKey('formation-copy')));
    final restored = FormationExchange.decode(clipboard);
    h.expect(restored.pieces.single.type == 'jack' &&
        restored.pieces.single.frameRow == 1 && restored.pieces.single.frameCol == 2,
        'Website clipboard lost the unboxed eating state');
    await h.tapElement(h.find((w) => w.key == const ValueKey('formation-output-format-toolkit')));
    await h.tapElement(h.find((w) => w.key == const ValueKey('formation-copy')));
    h.expect(FormationExchange.decode(clipboard).pieces.isEmpty,
        'Toolkit clipboard must stay plant-only');
    final buttons = h.all((w) => w.key == const ValueKey('board-apply-game'));
    h.expect(buttons.length == 1, 'Main game-sync button missing');
    h.expect(h.all((w) => w is Icon && w.icon == Icons.play_arrow_rounded).isNotEmpty,
        'Sync action must display a play icon');
    h.expect(h.all((w) => w is Tooltip && (w.message ?? '').contains('替换现有布阵')).isNotEmpty,
        'Sync action needs an explanatory tooltip');
  });
  await h.run('live.unsupported',
      'Unsupported state clears stale code, disables copy and recovers',
      () async {
    final before = output().controller!.text;
    session.execute(
        'conflicting plants',
        Formation(pieces: [
          Piece(
              id: 'unsupported',
              type: 'pea',
              row: 0,
              col: 0,
              layer: ObjectSpec.byId('pea').layer),
          Piece(id: 'overlap', type: 'wallnut', row: 0, col: 0, layer: 10),
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
  await File('${Directory.systemTemp.path}/pvz-live-output-report.json').writeAsString(jsonEncode({
    'cases': h.cases,
    'scope':
        'real headless Flutter UI; clipboard simulated; native secondary output checked separately'
  }));
  session.dispose();
  await repo.close();
  exit(h.cases.any((c) => c['status'] != 'pass') ? 1 : 0);
}
