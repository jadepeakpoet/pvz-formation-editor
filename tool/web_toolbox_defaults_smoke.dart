// Real Flutter UI; native audio transport is explicitly mocked below.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/seed_chooser.dart';
import 'package:pvz_formation_editor/platform/original_audio.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  final audioCalls = <MethodCall>[];
  final fileCalls = <MethodCall>[];
  ParityBinding.handlers[OriginalAudio.channel.name] = (call) async {
    audioCalls.add(call);
    if (call.method == 'setMusicVolume' || call.method == 'playPlantingSound') {
      return true;
    }
    return null;
  };
  ParityBinding.handlers['pvz_formation_editor/files'] = (call) async {
    fileCalls.add(call);
    if (call.method == 'copyImage') return true;
    // Cancel the save picker; this tests export dispatch without writing a file.
    return null;
  };
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final session = EditorSession(repo, persistDraft: false);
  final boundary = GlobalKey();
  final h = ParityHarness(boundary,
      await Directory('/tmp/pvz-web-toolbox-defaults').create(recursive: true));
  FlutterError.onError = h.errors.add;
  h.expect(OriginalAudio.musicVolume == .25 && OriginalAudio.soundVolume == .5,
      'Fresh audio defaults must match source 25% music / 50% effects');
  runApp(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          home: app.EditorPage(
              session: session, continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  final dynamic page =
      (h.find((w) => w is app.EditorPage) as StatefulElement).state;

  Future<void> tab(int index) async {
    await h.tapElement(h.find((w) => w.key == ValueKey('toolbox-tab-$index')));
    await h.settle();
  }

  bool text(String value) =>
      h.all((w) => w is Text && w.data == value).isNotEmpty;
  Checkbox checkbox(String key) =>
      h.find((w) => w.key == ValueKey(key)).widget as Checkbox;
  bool radioSelected(String key) {
    Radio<int>? radio;
    void visit(Element element) {
      if (element.widget is Radio<int>) radio = element.widget as Radio<int>;
      element.visitChildren(visit);
    }

    visit(h.find((w) => w.key == ValueKey(key)));
    return radio != null && radio!.value == radio!.groupValue;
  }

  h.expect(h.all((w) => w.key == const ValueKey('toolbox-tab-0')).isEmpty,
      'Toolbox must not retain a duplicate seed chooser tab');
  h.expect(
      h
              .all((w) =>
                  w is InkWell &&
                  w.key is ValueKey<String> &&
                  (w.key as ValueKey<String>).value.startsWith('toolbox-tab-'))
              .length ==
          5,
      'Toolbox should expose five source content tabs');
  h.expect(text('卡槽选卡'), 'Board chooser button must keep its fixed label');
  await h.tapElement(
      h.find((w) => w.key == const ValueKey('board-picker-toggle')));
  h.expect(
      page.seedChooserOpen == true &&
          h.all((w) => w is OriginalSeedChooser).isNotEmpty &&
          text('卡槽选卡'),
      'Board seed chooser did not open with fixed label');
  await h.tapElement(
      h.find((w) => w.key == const ValueKey('board-picker-toggle')));
  h.expect(
      page.seedChooserOpen == false &&
          h.all((w) => w is OriginalSeedChooser).isEmpty &&
          text('卡槽选卡'),
      'Board seed chooser did not close with fixed label');

  await tab(5);
  h.expect(
      radioSelected('original-cMusic1') &&
          radioSelected('original-cAudio2') &&
          radioSelected('original-rWindow1'),
      'Settings selected radio defaults differ from source');
  h.expect(
      checkbox('original-cSoil').value == true &&
          checkbox('original-rSeed').value == true &&
          checkbox('original-rClear').value == true &&
          checkbox('original-rBrain').value == false &&
          checkbox('original-rCtc').value == false &&
          session.document.sunValue == 9990 &&
          session.document.fogColumns == 0,
      'Settings display defaults differ from source');
  h.expect(
      audioCalls.any((c) =>
              c.method == 'setMusicVolume' &&
              (c.arguments as Map)['volume'] == .25) &&
          audioCalls.any((c) =>
              c.method == 'setSoundVolume' &&
              (c.arguments as Map)['volume'] == .5),
      'Selected defaults were not sent to native audio transport');

  await h
      .tapElement(h.find((w) => w.key == const ValueKey('original-cMusic3')));
  await h
      .tapElement(h.find((w) => w.key == const ValueKey('original-cAudio0')));
  session.execute(
      'existing display fixture',
      session.document.copy(sunValue: 1234, fogColumns: 3, display: {
        ...session.document.display,
        '卡槽': false,
        '阳光': false,
        '小推车': false,
        '脑子': true,
        '继续标识': true,
        '泥土': false,
        '迷雾': true,
      }));
  await h.settle();
  final selectedDocument = session.document.fingerprint;
  await tab(1);
  await tab(5);
  h.expect(
      session.document.fingerprint == selectedDocument &&
          checkbox('original-cSoil').value == false &&
          checkbox('original-rSeed').value == false &&
          checkbox('original-rClear').value == false &&
          checkbox('original-rBrain').value == true &&
          checkbox('original-rCtc').value == true &&
          radioSelected('original-cMusic3') &&
          radioSelected('original-cAudio0') &&
          OriginalAudio.musicVolume == .75 &&
          OriginalAudio.soundVolume == 0,
      'Re-entering settings reset an existing document or selected volume');
  final sunBox = h.find((w) => w.key == const ValueKey('original-tSun')).renderObject as RenderBox;
  final sunField = h.find((w) => w.key == const ValueKey('original-tSun')).widget as TextField;
  final sunLabel = h.find((w) => w is Text && w.data == '显示阳光、卡片槽').renderObject as RenderBox;
  h.expect(sunBox.size.height >= 32 && sunField.textAlignVertical == TextAlignVertical.center && sunField.expands &&
      (sunBox.localToGlobal(sunBox.size.center(Offset.zero)).dy -
       sunLabel.localToGlobal(sunLabel.size.center(Offset.zero)).dy).abs() < 1,
      'Settings sun field must have comfortable height and align with its label');
  page.toolboxPosition = const Offset(40, 90);
  await h.tapElement(h.find((w) => w.key == const ValueKey('settings-reset-window-positions')));
  h.expect(page.toolboxPosition == const Offset(808, 0) && session.document.fingerprint == selectedDocument,
      'Settings reset must restore fallback window positions without editing formation');
  final windowCalls = <MethodCall>[];
  ParityBinding.handlers['pvz_formation_editor/windows'] = (call) async {
    windowCalls.add(call);
    return true;
  };
  page.nativeWindows = true;
  await h.tapElement(h.find((w) => w.key == const ValueKey('settings-reset-window-positions')));
  h.expect(windowCalls.any((call) => call.method == 'resetWindowPositions'),
      'Settings reset must dispatch native window positioning');
  page.nativeWindows = false;
  await h.screenshot('settings-retained-values');

  await tab(3);
  h.expect(text('创建当前阵型的镜像窗口') && !text('创建镜像'),
      'Mirror panel should use source heading without duplicate create button');
  h.expect(
      checkbox('original-cMirrorBack').value == true &&
          checkbox('original-cPokerBack').value == true,
      'Mirror background / poker width defaults differ from source InitCookie');
  for (var index = 0; index < 6; index++) {
    h.expect(
        h.all((w) => w.key == ValueKey('original-clone-$index')).length == 1,
        'Mirror source scale button $index missing');
  }
  await h
      .tapElement(h.find((w) => w.key == const ValueKey('original-clone-3')));
  h.expect(
      page.mirrors.length == 1 &&
          page.mirrorScales.single == .5 &&
          page.mirrorPokerWidths.single == true,
      'Source half-size mirror button created incorrect snapshot');
  final snapshot = (page.mirrors.single as Formation).fingerprint;
  session.execute('change after mirror', session.document.copy(sunValue: 4321));
  await h.settle();
  h.expect(
      (page.mirrors.single as Formation).fingerprint == snapshot &&
          session.document.fingerprint != snapshot,
      'Mirror snapshot followed later edits');
  await h.screenshot('source-mirror-controls');

  await tab(4);
  for (final removed in [
    '导入阵图文件',
    '导出 / 另存阵图',
    '保存到原文件',
    '撤销文件覆盖',
    '保存到我的存档',
    '另存为新存档',
    '打开存档库',
  ]) {
    h.expect(
        !text(removed), 'Transfer page still exposes custom action $removed');
  }
  h.expect(
      h.all((w) => w.key == const ValueKey('formation-live-output')).length ==
              1 &&
          text('载入') &&
          text('清空输入') &&
          text('复制') &&
          h
              .all((w) => w.key == const ValueKey('formation-generate-image'))
              .isNotEmpty,
      'Removing custom footer also removed source string / PNG controls');
  h.expect(
      h
              .all((w) => w.key == const ValueKey('formation-image-preview'))
              .isEmpty &&
          h
              .all((w) => w.key == const ValueKey('formation-export-image'))
              .isEmpty && h.all((w) => w.key == const ValueKey('formation-copy-image')).isEmpty,
      'Image preview/export must not exist before generation');
  final ratioDropdown = h.find((w) => w is DropdownButton<double>).widget
      as DropdownButton<double>;
  h.expect(
      ratioDropdown.items!.map((item) => (item.child as Text).data).join(',') ==
          '1/1×,3/4×,2/3×,1/2×',
      'Output ratios must use fraction labels');
  await h.choose<double>(.75);
  await h.tapElement(
      h.find((w) => w.key == const ValueKey('formation-generate-image')));
  for (var attempt = 0; attempt < 80 && page.generatingPng == true; attempt++) {
    await h.settle();
  }
  h.expect(page.generatedPng != null && page.generatingPng == false,
      'PNG preview generation did not complete');
  final png = page.generatedPng as Uint8List;
  final header = ByteData.sublistView(png);
  h.expect(
      header.getUint32(16) == (917 * .75).round() &&
          header.getUint32(20) == (600 * .75).round(),
      'Generated PNG dimensions do not match poker width / selected 3/4 ratio');
  h.expect(
      h
              .all((w) => w.key == const ValueKey('formation-image-preview'))
              .isNotEmpty &&
          h
              .all((w) => w.key == const ValueKey('formation-export-image'))
              .isNotEmpty &&
          !fileCalls.any((c) => c.method == 'chooseSavePath'),
      'Generation must expose preview/export without opening a save picker');
  for (final key in ['formation-generate-image', 'formation-export-image', 'formation-copy-image']) {
    h.expect(h.find((w) => w.key == ValueKey(key)).findAncestorWidgetOfExactType<Wrap>()?.key ==
        const ValueKey('formation-image-actions'), 'Image actions must stay together above preview');
  }
  await h.tapElement(h.find((w) => w.key == const ValueKey('formation-copy-image')));
  final copied = (fileCalls.singleWhere((c) => c.method == 'copyImage').arguments as Map)['bytes'] as List<int>;
  final copiedPng = page.generatedPng as List<int>;
  h.expect(copied.length == copiedPng.length &&
      copiedPng.asMap().entries.every((entry) => copied[entry.key] == entry.value) &&
      !fileCalls.any((c) => c.method == 'chooseSavePath'),
      'Copy image must send exact generated PNG bytes without opening export picker');
  final previewElement =
      h.find((w) => w.key == const ValueKey('formation-image-preview'));
  await precacheImage((previewElement.widget as Image).image, previewElement);
  await h.settle();
  await h.tapElement(
      h.find((w) => w.key == const ValueKey('formation-export-image')));
  for (var attempt = 0;
      attempt < 30 && !fileCalls.any((c) => c.method == 'chooseSavePath');
      attempt++) {
    await h.settle();
  }
  h.expect(
      fileCalls.where((c) => c.method == 'chooseSavePath').length == 1 &&
          identical(page.generatedPng, png),
      'Export should open the picker after generation and retain preview on cancel: '
      '${fileCalls.map((c) => c.method).toList()}, same bytes=${identical(page.generatedPng, png)}, '
      'messages=${h.all((w) => w is SnackBar).map((e) => (e.widget as SnackBar).content)}');
  await h.screenshot('source-transfer-controls');
  h.expect(
      h.errors.isEmpty, h.errors.map((e) => e.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS source settings/audio defaults, retained document and volume choices, five content tabs, fixed seed toggle, six mirror scales and frozen snapshot, source transfer controls, fractional PNG generation/preview before export');
  runApp(const SizedBox.shrink());
  await h.settle();
  await OriginalAudio.dispose();
  ParityBinding.handlers.remove(OriginalAudio.channel.name);
  ParityBinding.handlers.remove('pvz_formation_editor/files');
  await repo.close();
  exit(0);
}
