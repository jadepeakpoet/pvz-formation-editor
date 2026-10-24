// Real library/workspace and SQLite. Opening a template creates saved editable work.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'sidebar_title_smoke.dart' as h;

Future<void> main() async {
  h.TitleBinding();
  await OriginalAssets.ensureLoaded();
  final temp = await Directory.systemTemp.createTemp('pvz-template-autosave-');
  final path = '${temp.path}/test.sqlite';
  final repo = await FormationRepository.open(path);
  final opened = <EditorSession>[];
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  try {
    runApp(MaterialApp(
        home: app.LibraryPage(
            repository: repo,
            showTitle: false,
            onOpenSession: (session) async {
              opened.add(session);
            },
            onOpenTab: (session) async {
              opened.add(session);
            })));
    await h.settle();
    await h.settle();
    h.check((await repo.listArchives()).isEmpty,
        'Browsing alone creates no archive');
    final dynamic library =
        (h.find((w) => w is app.LibraryPage).single as StatefulElement).state;
    final preset = LibraryPresets.all.first;
    await library.presetAction('open-current', preset);
    final rows = await repo.listArchives();
    h.check(rows.length == 1 && opened.last.matchesArchive,
        'Open current tab autosaves immediately before editing');
    h.check(
        Formation.fromJson(rows.single.document).fingerprint ==
            preset.document.fingerprint,
        'Full template content saved');
    final id = rows.single.id;
    await library.presetAction('open-current', preset);
    h.check(
        (await repo.listArchives()).length == 1 &&
            opened.last.sourceArchiveId == id,
        'Repeated same template reuses identical archive');
    await library.presetAction('open-tab', preset);
    h.check(
        (await repo.listArchives()).length == 1 &&
            opened.last.sourceArchiveId == id,
        'Open new tab reuses saved identical archive');
    final session = opened.last;
    session.rename('自动保存名阵');
    for (var i = 0; i < 100 && session.saveState != '已保存'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final reader = await FormationRepository.open(path);
    final saved = (await reader.listArchives()).single;
    h.check(saved.id == id && saved.name == '自动保存名阵',
        'Subsequent edit autosaves same record without explicit Save/flush');
    final resumed = await EditorSession.resume(reader);
    h.check(
        resumed.sourceArchiveId == id &&
            resumed.document.fingerprint == session.document.fingerprint,
        'Independent reopen restores full saved template');
    resumed.dispose();
    await reader.close();
    await library.presetAction('preview', LibraryPresets.all[1]);
    h.check(opened.last.readOnly && (await repo.listArchives()).length == 1,
        'Read-only preview remains unsaved');
    h.check(
        errors.isEmpty, errors.map((e) => e.exceptionAsString()).join('\n'));
    stdout.writeln(
        'PASS template open-current/open-tab autosave, repeated opens reuse archive, edits update same ID, reopen restores, read-only preview does not save');
  } finally {
    runApp(const SizedBox.shrink());
    await h.settle();
    for (final session in opened) {
      session.dispose();
    }
    await repo.close();
    await temp.delete(recursive: true);
  }
  exit(0);
}
