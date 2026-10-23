// Real Flutter dialog/state behavior with simulated cross-window snapshots.
// Native channels below are test doubles, not native multi-engine acceptance.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/original_audio.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  final audioCalls = <MethodCall>[];
  ParityBinding.handlers['pvz_formation_editor/windows'] = (_) async => false;
  ParityBinding.handlers['pvz_formation_editor/language'] = (_) async => 'zh';
  ParityBinding.handlers['pvz_formation_editor/files'] = (_) async => null;
  ParityBinding.handlers[OriginalAudio.channel.name] = (call) async {
    audioCalls.add(call);
    return call.method == 'setMusicVolume' ? true : null;
  };
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final session = EditorSession(repo, persistDraft: false);
  final boundary = GlobalKey();
  final h = ParityHarness(boundary,
      await Directory('/tmp/pvz-toolbox-state-guards').create(recursive: true));
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          home: app.EditorPage(
              session: session,
              toolboxOnly: true,
              continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  final dynamic page =
      (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  Map<String, dynamic> snapshot(String token, {Formation? document}) =>
      Map<String, dynamic>.from(page.windowState() as Map)
        ..['documentToken'] = token
        ..['name'] = 'snapshot $token'
        ..['documentJson'] =
            jsonEncode((document ?? session.document).toJson());
  h.expect(page.receiveWindowState(snapshot('first')) == true,
      'Initial simulated window snapshot rejected');

  final image = Uint8List.fromList([1, 2, 3]);
  page.generatedPng = image;
  page.generatedPngName = 'first image';
  page.receiveWindowState(snapshot('first'));
  h.expect(identical(page.generatedPng, image),
      'Same-document preference synchronization cleared generated snapshot');
  page.receiveWindowState(snapshot('second'));
  h.expect(page.generatedPng == null && page.generatedPngName == null,
      'Switching toolbox document retained previous PNG preview');

  final volumes = snapshot('second')
    ..['musicLevel'] = 3
    ..['soundLevel'] = 1;
  page.receiveWindowState(volumes);
  await h.settle();
  h.expect(OriginalAudio.musicVolume == .75 && OriginalAudio.soundVolume == .25,
      'Received audio choices did not update engine preference state');
  h.expect(
      audioCalls.any((c) =>
          c.method == 'setMusicVolume' &&
          (c.arguments as Map)['volume'] == .75),
      'Received music volume was not applied');

  page.tool = '放置';
  page.setSelectionMode(true);
  h.expect(
      page.tool == '放置', 'Entering batch mode cleared active planting tool');
  page.updateBatchSelection({1}, {1});
  page.setSelectionMode(false);
  h.expect(page.tool == '放置' && page.cells.isEmpty,
      'Leaving batch mode cleared active tool or retained operational cell selection');
  page.setSelectionMode(true);
  h.expect(page.cells.length == 1, 'Changing modes forgot selected axes');
  page.selectedType = 'pea';
  page.selectedId = null;

  Future<void> confirmAppearance() => h.tapElement(h.find((w) =>
      w is TextButton && w.child is Text && (w.child as Text).data == '默认外表'));
  Future<void> rejectedAfter(
      Future<void> Function() mutate, String reason) async {
    final pending = page.chooseAppearance(plantBatch: true) as Future<void>;
    await h.settle();
    await h.settle();
    h.expect(h.all((w) => w is AlertDialog).isNotEmpty,
        'Appearance picker did not open for $reason');
    await mutate();
    final before = session.document.fingerprint, depth = session.undoDepth;
    await confirmAppearance();
    await pending;
    await h.settle();
    h.expect(
        session.document.fingerprint == before && session.undoDepth == depth,
        'Stale appearance confirmation planted after $reason');
  }

  await rejectedAfter(() async {
    page.receiveWindowState(snapshot('third'));
  }, 'document token change');
  await rejectedAfter(() async {
    page.receiveWindowState(snapshot('third',
        document:
            session.document.copy(sunValue: session.document.sunValue + 1)));
  }, 'same-document remote edit');
  await rejectedAfter(() async {
    page.selectedType = 'sunflower';
    page.update();
  }, 'selected card change');
  page.selectedType = 'pea';
  final beforeEarly = session.document.fingerprint;
  final beforeAssets = page.chooseAppearance(plantBatch: true) as Future<void>;
  page.selectedType = 'sunflower';
  await beforeAssets;
  await h.settle();
  h.expect(
      h.all((w) => w is AlertDialog).isEmpty &&
          session.document.fingerprint == beforeEarly,
      'Async asset setup opened stale appearance picker');

  page.selectedType = 'pea';
  final current = page.chooseAppearance(plantBatch: true) as Future<void>;
  await h.settle();
  await h.settle();
  await confirmAppearance();
  await current;
  await h.settle();
  h.expect(
      session.document.pieces.length == 1 &&
          session.document.pieces.single.type == 'pea',
      'Current appearance confirmation failed to batch plant');

  runApp(const SizedBox.shrink());
  await h.settle();
  final next = EditorSession(repo, persistDraft: false);
  runApp(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          home: app.EditorPage(session: next, continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  final dynamic nextPage =
      (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  h.expect(
      nextPage.musicLevel == 3 &&
          nextPage.soundLevel == 1 &&
          OriginalAudio.musicVolume == .75 &&
          OriginalAudio.soundVolume == .25,
      'New editor page restored older audio values');
  h.expect(h.errors.isEmpty,
      h.errors.map((error) => error.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS stale appearance token/document/card guards, current batch confirmation, toolbox PNG invalidation, mode tool retention and audio preference continuity');
  runApp(const SizedBox.shrink());
  await h.settle();
  session.dispose();
  next.dispose();
  await repo.close();
  exit(0);
}
