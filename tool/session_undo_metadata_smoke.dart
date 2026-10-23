// Real Flutter engine and SQLite: all history lives until its tab closes.
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

void check(bool value, String why) {
  if (!value) throw StateError(why);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await Directory.systemTemp.createTemp('pvz-undo-metadata-');
  final repo = await FormationRepository.open('${dir.path}/library.sqlite');
  final session = EditorSession(repo, name: '原名');
  try {
    await session.flush();
    check(session.undoDepth == 0 && session.newCommandSerial == 0,
        'initial autosave is not a command');
    session.execute('种植', session.document.copy(sunValue: 7));
    session.rename('新名');
    check(session.undoDepth == 2 && session.newCommandSerial == 2,
        'rename is a distinct command');
    session.undo();
    check(session.name == '原名' && session.document.sunValue == 7,
        'rename undo preserves document');
    session.undo();
    check(session.name == '原名' && session.document.sunValue == 9990,
        'previous document command remains undoable');
    session.redo();
    session.redo();
    await session.flush();
    check(
        session.name == '新名' &&
            session.document.sunValue == 7 &&
            session.newCommandSerial == 2 &&
            session.matchesArchive,
        'redo saves atomic document and name without new commands');
    session.execute('替换阵型', Formation(sunValue: 8), name: '替换名');
    session.undo();
    check(session.name == '新名' && session.document.sunValue == 7,
        'document replacement restores its previous title');
    session.redo();
    for (var i = 0; i < 125; i++) {
      session.execute('edit $i', session.document.copy(sunValue: i));
    }
    check(session.undoDepth == 128 && session.newCommandSerial == 128,
        'all commands beyond old 100-command limit retained');
    for (var i = 0; i < 128; i++) {
      session.undo();
    }
    check(
        !session.canUndo &&
            session.redoDepth == 128 &&
            session.name == '原名' &&
            session.document.sunValue == 9990,
        'entire open-tab history restores original document and title');
    await session.flush();
    check(
        session.error == null &&
            session.matchesArchive &&
            session.newCommandSerial == 128,
        'SQLite autosave persists undo without changing history serial');
    final saved = (await repo.listArchives()).single;
    check(saved.name == '原名' && saved.document['sunValue'] == 9990,
        'persisted final state includes restored title');
    stdout.writeln('session metadata and lifetime undo checks passed');
    exitCode = 0;
  } catch (e, stack) {
    stderr.writeln('$e\n$stack');
    exitCode = 1;
  } finally {
    session.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  }
  exit(exitCode);
}
