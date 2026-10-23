import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  await OriginalAssets.ensureLoaded();
  final directory =
      await Directory.systemTemp.createTemp('pvz-current-history-');
  for (final channel in [
    'plugins.flutter.io/path_provider',
    'plugins.flutter.io/path_provider_macos'
  ]) {
    ParityBinding.handlers[channel] = (_) async => directory.path;
  }
  final repo =
      await FormationRepository.open('${directory.path}/history.sqlite');
  Formation doc(int sun) => Formation(sunValue: sun);
  await repo.saveArchive(
      id: 'current', name: '当前存档', document: doc(100).toJson());
  await repo.saveArchive(
      id: 'unused',
      updateId: 'current',
      name: '当前存档',
      document: doc(200).toJson());
  final current = await repo.saveArchive(
      id: 'unused',
      updateId: 'current',
      name: '当前存档',
      document: doc(300).toJson());
  await repo.saveArchive(
      id: 'other', name: '其他存档', document: doc(800).toJson());
  await repo.saveArchive(
      id: 'unused',
      updateId: 'other',
      name: '其他存档',
      document: doc(900).toJson());
  final initialVersions = await repo.listVersions('current');
  final oldest = initialVersions.last;
  final otherVersion = (await repo.listVersions('other')).single;
  final session = EditorSession(repo,
      id: 'current-tab',
      document: doc(300),
      name: current.name,
      sourceArchiveId: current.id,
      savedFingerprint: doc(300).fingerprint);
  final tabs = EditorTabsController(repo, initial: session);
  final key = GlobalKey();
  final h = ParityHarness(
      key, await Directory('/tmp/pvz-current-history').create(recursive: true));
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: key,
      child: MaterialApp(
          home: app.EditorWorkspace(
              controller: tabs,
              libraryPath: '${directory.path}/history.sqlite',
              continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  Future<void> tap(String key) =>
      h.tapElement(h.find((w) => w.key == ValueKey(key)));
  Future<void> waitFor(bool Function() predicate, String message) async {
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (!predicate() && DateTime.now().isBefore(end)) {
      await h.settle();
    }
    h.expect(predicate(), message);
  }

  dynamic page() =>
      (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  Future<void> open() async {
    await h.settle();
    await tap('workspace-more');
    await tap('workspace-history');
    await waitFor(
        () => h
            .all((w) => w.key == const ValueKey('archive-history-dialog'))
            .isNotEmpty,
        'History dialog did not open');
  }

  int previewSun() =>
      ((h.find((w) => w.key == const ValueKey('archive-history-preview')).widget
                  as CustomPaint)
              .painter as BoardPainter)
          .document
          .sunValue;
  Future<void> toolbar(bool redo) async {
    await h.tap(redo ? '恢复' : '撤销');
  }

  try {
    final remote = Map<String, dynamic>.from(page().windowState() as Map);
    remote['documentToken'] = page().documentToken;
    remote['documentJson'] = doc(777).fingerprint;
    remote['baseFingerprint'] = session.document.fingerprint;
    page().historyRestoring = true;
    h.expect(
        page().receiveWindowState(remote) == false &&
            session.document.sunValue == 300,
        'In-flight restoration must reject remote document edits');
    remote['documentJson'] = session.document.fingerprint;
    remote['autoLily'] = !(remote['autoLily'] as bool);
    h.expect(page().receiveWindowState(remote) == true,
        'Non-document preferences should remain available while restoring');
    page().historyRestoring = false;
    await h.settle();
    await open();
    h.expect(
        h
            .all((w) =>
                w.key == ValueKey('archive-history-version-${otherVersion.id}'))
            .isEmpty,
        'History leaked another formation');
    h.expect(previewSun() == 300, 'Current version should be selected first');
    final depth = session.undoDepth;
    await tap('archive-history-version-${oldest.id}');
    h.expect(
        previewSun() == 100 &&
            session.document.sunValue == 300 &&
            session.undoDepth == depth,
        'Browsing history must not edit current document');
    await tap('archive-history-restore');
    await waitFor(
        () =>
            session.document.sunValue == 100 &&
            (h
                        .find((w) =>
                            w.key == const ValueKey('archive-history-restore'))
                        .widget as FilledButton)
                    .onPressed ==
                null,
        'Restore did not finish with new current selected');
    h.expect(
        session.id == 'current-tab' &&
            session.undoDepth == depth + 1 &&
            previewSun() == 100,
        'Restore should remain in same tab with a toolbar undo command');
    final restoredVersions = await repo.listVersions('current');
    h.expect(
        restoredVersions.length == initialVersions.length + 1 &&
            restoredVersions.first.document['sunValue'] == 300 &&
            restoredVersions.any((v) => v.id == oldest.id),
        'Restore must append prior current and retain selected old version');
    await h.screenshot('restored-current-first');
    await tap('archive-history-close');
    await h.settle();
    h.expect(page().canUndoEditing == true,
        'Toolbar undo should be enabled after restore');
    await toolbar(false);
    await session.flush();
    h.expect(session.document.sunValue == 300 && page().canRedoEditing == true,
        'Toolbar Undo must return to pre-restore formation');
    h.expect(
        (await repo.listArchives())
                .firstWhere((a) => a.id == 'current')
                .document['sunValue'] ==
            300,
        'Undo restore must persist to same archive');
    await toolbar(true);
    await session.flush();
    h.expect(session.document.sunValue == 100,
        'Toolbar Redo must restore selected historical content');
    final afterRedo = await repo.listVersions('current');
    h.expect(
        afterRedo.length == initialVersions.length + 3 &&
            afterRedo.any((v) => v.id == oldest.id),
        'Undo/redo must preserve and extend history');
    await open();
    h.expect(previewSun() == 100,
        'Reopened view should select restored latest version');
    final beforeIdentical = session.undoDepth;
    await tap('archive-history-version-${oldest.id}');
    await tap('archive-history-restore');
    await waitFor(() => session.undoDepth == beforeIdentical + 1,
        'Identical-content restore should still enter toolbar undo');
    h.expect(
        (await repo.listVersions('current')).length == afterRedo.length + 1,
        'Identical-content restore must still append a new history record');

    await tap('archive-history-close');
    await h.settle();
    h.expect(h.errors.isEmpty,
        h.errors.map((e) => e.exceptionAsString()).join('\n'));
    stdout.writeln(
        'PASS current archive only, preview, append restore, same tab, toolbar undo/redo, persisted history');
  } finally {
    runApp(const SizedBox.shrink());
    await h.settle();
    await tabs.flushAll();
    tabs.dispose();
    await repo.close();
    await directory.delete(recursive: true);
  }
  exit(0);
}
