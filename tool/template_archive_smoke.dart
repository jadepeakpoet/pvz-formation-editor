// Real Workspace and temporary SQLite. Browsing templates must stay transient;
// explicit edits, Save, Save As and Add to My Archives still create archives.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/layouts.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final tabs = EditorTabsController(repo);
  await tabs.ready;
  final boundary = GlobalKey();
  final h = ParityHarness(boundary,
      await Directory('/tmp/pvz-template-archive').create(recursive: true));
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          home: app.EditorWorkspace(
              controller: tabs, continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  dynamic page() =>
      (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  Future<void> settled() async {
    await h.settle();
    await tabs.ready;
    await h.settle();
  }

  h.expect((await repo.listArchives()).isEmpty, 'Blank startup was saved');
  for (var i = 0; i < 5; i++) {
    await page().useFormationPreset('阵型', 0);
    await settled();
    await tabs.flushAll();
    h.expect((await repo.listArchives()).isEmpty,
        'Opening the same full preset generated an archive at iteration $i');
  }
  for (final group in ['炮位', '无炮']) {
    await page().useFormationPreset(group, 0);
    await settled();
  }
  await page().navigateFormation(
      OriginalActions.apply(tabs.active.document, '智能搭梯'),
      name: tabs.active.name);
  await settled();
  await tabs.goBack();
  await settled();
  await tabs.goForward();
  await settled();
  await tabs.newBlank();
  await settled();
  await tabs.activate(0);
  await settled();
  await tabs.flushAll();
  h.expect((await repo.listArchives()).isEmpty,
      'Partial/one-click navigation, history or tab activation saved untouched templates');
  stdout.writeln(
      'PASS repeated full/partial/one-click browsing, history and tab switching create no archives');

  final edited = tabs.active;
  edited.execute('first actual edit',
      edited.document.copy(sunValue: edited.document.sunValue + 1));
  await edited.flush();
  final firstId = edited.sourceArchiveId;
  h.expect(firstId != null && (await repo.listArchives()).length == 1,
      'First actual edit must create exactly one archive');
  for (var i = 0; i < 4; i++) {
    edited.execute('next edit',
        edited.document.copy(sunValue: edited.document.sunValue + 1));
  }
  await edited.flush();
  h.expect(
      edited.sourceArchiveId == firstId &&
          (await repo.listArchives()).length == 1,
      'Subsequent autosaves must update the same archive');
  stdout.writeln(
      'PASS first edit creates one archive and subsequent edits preserve identity');

  await page().useFormationPreset('阵型', 1);
  await settled();
  h.expect((await repo.listArchives()).length == 1,
      'Opening another template created an archive before Save');
  await page().saveArchive();
  await settled();
  h.expect(
      (await repo.listArchives()).length == 2 &&
          tabs.active.sourceArchiveId != firstId,
      'Explicit Save must persist the current untouched template once');
  await page().saveArchive();
  await settled();
  h.expect((await repo.listArchives()).length == 2,
      'Repeated explicit Save created a duplicate archive');
  final savedId = tabs.active.sourceArchiveId;
  final saving = page().saveArchive(saveAs: true) as Future<void>;
  await h.settle();
  await h.settle();
  await h.tapElement(h.find((w) => w.key == const ValueKey('archive-confirm')));
  await saving;
  await settled();
  h.expect(
      (await repo.listArchives()).length == 3 &&
          tabs.active.sourceArchiveId != savedId,
      'Save As must still create an intentional independent copy');
  stdout.writeln(
      'PASS explicit Save stays singular and Save As creates an independent copy');

  // Mount the real LibraryPage without startup/resume. Its template callbacks
  // must also open transient sessions while explicit Add creates a copy.
  runApp(const SizedBox.shrink());
  await h.settle();
  await tabs.flushAll();
  tabs.dispose();
  final opened = <EditorSession>[];
  runApp(MaterialApp(
      home: app.LibraryPage(
          repository: repo,
          onOpenSession: (session) async {
            opened.add(session);
          })));
  await h.settle();
  await h.settle();
  final dynamic library =
      (h.find((w) => w is app.LibraryPage) as StatefulElement).state;
  final preset = LibraryPresets.all.first;
  await library.presetAction('open-current', preset);
  await library.presetAction('open-current', preset);
  for (final session in opened) {
    await session.flush();
  }
  h.expect(opened.length == 2 && (await repo.listArchives()).length == 3,
      'Library template open created duplicates before editing');
  await library.addPreset(preset);
  h.expect((await repo.listArchives()).length == 4,
      'Explicit Add to My Archives must still create a copy');
  h.expect(
      h.errors.isEmpty, h.errors.map((e) => e.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS library browsing remains transient and explicit Add preserves intentional copies');
  runApp(const SizedBox.shrink());
  await h.settle();
  for (final session in opened) {
    session.dispose();
  }
  await repo.close();
  exit(0);
}
