// Real engine key dispatch through editor shortcuts and both rename entry points.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  final binding = ParityBinding();
  // macOS text keys use native selectors; Linux bindings exercise hardware key
  // propagation in the headless engine without pretending to test native input.
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final session = EditorSession(repo,
      persistDraft: false,
      name: '测试名称AB',
      document: Formation(pieces: [
        Piece(id: 'keep', type: 'pea', row: 0, col: 0, layer: 10),
      ]));
  final boundary = GlobalKey();
  final h = ParityHarness(boundary,
      await Directory('/tmp/pvz-rename-keys').create(recursive: true));
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          home: app.EditorPage(
              session: session, continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  final dynamic page =
      (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  page.selectedId = 'keep';
  page.update();
  await h.settle();
  var clock = 0;
  Future<void> key(
      PhysicalKeyboardKey physical, LogicalKeyboardKey logical) async {
    for (final type in [ui.KeyEventType.down, ui.KeyEventType.up]) {
      binding.platformDispatcher.onKeyData!(ui.KeyData(
          timeStamp: Duration(milliseconds: ++clock),
          type: type,
          physical: physical.usbHidUsage,
          logical: logical.keyId,
          character: null,
          synthesized: true));
    }
    await h.settle();
  }

  Future<void> deletion(String fieldKey) async {
    TextField field() =>
        h.find((w) => w.key == ValueKey(fieldKey)).widget as TextField;
    final controller = field().controller!;
    final before = session.document.fingerprint;
    final depth = session.undoDepth;
    controller.value = const TextEditingValue(
        text: '中文AB', selection: TextSelection.collapsed(offset: 4));
    await key(PhysicalKeyboardKey.backspace, LogicalKeyboardKey.backspace);
    h.expect(controller.text == '中文A', 'Backspace must delete one character');
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    await key(PhysicalKeyboardKey.backspace, LogicalKeyboardKey.backspace);
    h.expect(
        controller.text == 'A', 'Backspace must delete selected Chinese text');
    controller.value = const TextEditingValue(
        text: 'ABCD', selection: TextSelection.collapsed(offset: 1));
    await key(PhysicalKeyboardKey.delete, LogicalKeyboardKey.delete);
    h.expect(controller.text == 'ACD', 'Delete must remove next character');
    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    await key(PhysicalKeyboardKey.delete, LogicalKeyboardKey.delete);
    h.expect(controller.text == 'A', 'Delete must remove selected text');
    h.expect(
        session.document.fingerprint == before && session.undoDepth == depth,
        'Text deletion must not delete board objects or add history');
  }

  await page.renameDocument();
  await h.settle();
  await deletion('document-name-input');
  await page.finishDocumentRename(cancel: true);
  await h.settle();
  h.expect(session.name == '测试名称AB', 'Inline cancel changed saved name');
  await page.renameDocument();
  await h.settle();
  await deletion('document-name-input');
  await page.finishDocumentRename();
  await h.settle();
  h.expect(session.name == 'A', 'Inline confirm did not save edited name');
  session.rename('测试名称AB');
  await session.flush();
  await h.settle();
  final dialog = page.renameFromMenu() as Future<void>;
  await h.settle();
  await h.settle();
  await deletion('workspace-rename-input');
  await h.tapElement(
      h.find((w) => w.key == const ValueKey('workspace-rename-cancel')));
  await dialog;
  h.expect(session.name == '测试名称AB', 'Dialog cancel changed saved name');
  final confirm = page.renameFromMenu() as Future<void>;
  await h.settle();
  await h.settle();
  await deletion('workspace-rename-input');
  await h.tapElement(
      h.find((w) => w.key == const ValueKey('workspace-rename-confirm')));
  await confirm;
  h.expect(session.name == 'A', 'Dialog did not confirm edited name');
  h.expect(session.document.pieces.single.id == 'keep', 'Rename deleted plant');
  h.expect(
      h.errors.isEmpty, h.errors.map((e) => e.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS inline and menu rename backspace, selected text, forward delete, cancel/confirm and board preservation');
  runApp(const SizedBox.shrink());
  await h.settle();
  debugDefaultTargetPlatformOverride = null;
  await repo.close();
  exit(0);
}
