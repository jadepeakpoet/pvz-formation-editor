import 'dart:io';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final temp = await Directory.systemTemp.createTemp('pvz-workspace-resume-');
  final path = '${temp.path}/library.sqlite';
  var repo = await FormationRepository.open(path);
  try {
    var tabs = await EditorTabsController.restore(repo);
    await tabs.ready;
    check(tabs.sessions.length == 1 && tabs.active.sourceArchiveId == null,
        'First startup has one transient blank');
    final a = tabs.active;
    a.execute(
        'plant',
        a.document.copy(pieces: [
          Piece(id: 'pea', type: 'pea', row: 1, col: 1, layer: 10)
        ]));
    check(await tabs.flushAll(), 'Autosave first real work');
    final aId = a.sourceArchiveId;
    final b = EditorSession(repo,
        name: 'Second formation', document: Formation(mapId: 'night'));
    b.filePath = 'C:/Example/Test.pvz';
    b.fileFormat = 'toolkit';
    await tabs.open(b, newTab: true);
    await tabs.activate(0);
    check(await tabs.flushAll(), 'Save complete workspace');
    final bId = b.sourceArchiveId;
    tabs.dispose();
    await repo.close();
    repo = await FormationRepository.open(path);
    tabs = await EditorTabsController.restore(repo);
    await tabs.ready;
    check(tabs.sessions.length == 2 && tabs.activeIndex == 0,
        'Restore all pages and selected page without adding a new tab');
    check(
        tabs.active.sourceArchiveId == aId &&
            tabs.active.document.pieces.single.type == 'pea',
        'Restore exact previous work');
    check(
        tabs.sessions[1].sourceArchiveId == bId &&
            tabs.sessions[1].filePath == 'C:/Example/Test.pvz',
        'Restore file association');
    await tabs.activate(1);
    check(await tabs.flushAll(), 'Remember active second tab');
    tabs.dispose();
    await repo.close();
    repo = await FormationRepository.open(path);
    tabs = await EditorTabsController.restore(repo);
    check(tabs.sessions.length == 2 && tabs.activeIndex == 1,
        'Second restart keeps activation order');
    await tabs.close(1);
    await tabs.close(0);
    check(await tabs.flushAll(), 'Close all pages');
    check(tabs.sessions.length == 1 && tabs.active.sourceArchiveId == null,
        'All-close leaves a transient blank');
    tabs.dispose();
    await repo.close();
    repo = await FormationRepository.open(path);
    tabs = await EditorTabsController.restore(repo);
    check(
        tabs.sessions.length == 1 &&
            tabs.active.sourceArchiveId == null &&
            tabs.active.document.pieces.isEmpty,
        'All-closed workspace does not reopen an old archive');
    check((await repo.listArchives()).length == 2,
        'Empty page restoration creates no duplicate archives');
    final preview = EditorSession(repo,
        id: 'readonly-preview',
        name: 'Preview',
        readOnly: true,
        persistDraft: false,
        document: Formation(mapId: 'roof'));
    await tabs.open(preview, newTab: true);
    check(await tabs.flushAll(), 'Persist readonly preview workspace');
    tabs.dispose();
    await repo.close();
    repo = await FormationRepository.open(path);
    tabs = await EditorTabsController.restore(repo);
    check(tabs.active.readOnly && tabs.active.document.mapId == 'roof',
        'Readonly preview restored without saving as editable archive');
    check((await repo.listArchives()).length == 2,
        'Preview restoration creates no archive');
    check(await tabs.flushAll(), 'Final flush');
    tabs.dispose();
    await repo.close();
    stdout.writeln(jsonEncode({
      'status': 'pass',
      'cases': [
        'first-launch',
        'multi-tab-restore',
        'active-tab',
        'file-association',
        'all-closed',
        'no-duplicate-blank',
        'readonly-preview'
      ]
    }));
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
