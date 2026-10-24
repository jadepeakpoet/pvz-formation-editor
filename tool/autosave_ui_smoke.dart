import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/app_theme.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'sidebar_title_smoke.dart' as h;

Future<void> main() async {
  h.viewport = const Size(1240, 800);
  h.TitleBinding();
  await OriginalAssets.ensureLoaded();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  final temp = await Directory.systemTemp.createTemp('pvz-autosave-ui-');
  final path = '${temp.path}/test.sqlite';
  final repo = await FormationRepository.open(path);
  final session = EditorSession(repo);
  try {
    runApp(MaterialApp(
        theme: buildAppTheme(),
        home: app.EditorPage(session: session, continueArchive: (_) async {})));
    await h.settle();
    await h.settle();
    h.check(h.find((w) => w is Text && w.data == '自动保存已开启').isNotEmpty,
        'Autosave enabled indicator');
    session.execute(
        '放置豌豆',
        session.document.copy(pieces: [
          Piece(id: 'test-pea', type: 'pea', row: 0, col: 0, layer: 10)
        ]));
    for (var i = 0; i < 100 && session.saveState != '已保存'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await h.settle();
    h.check(session.document.pieces.length == 1 && session.error == null,
        'Editor edit completed: pieces=${session.document.pieces.length}, state=${session.saveState}, error=${session.error}');
    h.check(h.find((w) => w is Text && w.data == '已自动保存').isNotEmpty,
        'Saved indicator after actual disk write');
    final reader = await FormationRepository.open(path);
    final restored = await EditorSession.resume(reader);
    h.check(restored.document.fingerprint == session.document.fingerprint,
        'New repository connection resumes edit without explicit Save or flush');
    restored.dispose();
    await reader.close();
    session.rename('自动保存验证');
    session.undo();
    session.redo();
    for (var i = 0; i < 100 && session.saveState != '已保存'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final reader2 = await FormationRepository.open(path);
    final rows = await reader2.listArchives();
    h.check(rows.single.name == '自动保存验证',
        'Rename and undo/redo automatically reach the existing archive');
    await reader2.close();
    h.check(
        errors.isEmpty, errors.map((e) => e.exceptionAsString()).join('\n'));
    stdout.writeln(
        'PASS editor edit autosaves without Save/flush, visible saved state, second SQLite connection resumes exact document, rename/undo/redo persist');
  } finally {
    runApp(const SizedBox.shrink());
    await h.settle();
    session.dispose();
    await repo.close();
    await temp.delete(recursive: true);
  }
  exit(0);
}
