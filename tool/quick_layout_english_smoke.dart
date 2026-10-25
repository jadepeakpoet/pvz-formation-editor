import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/app_language.dart';
import 'package:pvz_formation_editor/platform/app_theme.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  final previous = AppLanguage.locale.value;
  AppLanguage.locale.value = 'en';
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final session = EditorSession(repo, persistDraft: false);
  final key = GlobalKey();
  final h = ParityHarness(key, await Directory.systemTemp.createTemp('pvz-quick-english-'));
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(key: key, child: MaterialApp(theme: buildAppTheme(),
      home: app.EditorPage(session: session, continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  h.expect(h.all((w) => w is Text && w.data == 'Seeds').isNotEmpty &&
      h.all((w) => w is Text && w.data == 'Apply').isNotEmpty,
      'Main toolbar uses concise English action labels');
  final dynamic page = (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  page.selectToolboxTab(1);
  await h.settle();
  final contents = h.find((w) => w is SingleChildScrollView &&
      w.controller == page.toolboxScrollControllers[1]);
  final untranslated = <String>[];
  void inspect(Element element) {
    final widget = element.widget;
    final text = widget is Text ? widget.data ?? widget.textSpan?.toPlainText()
        : widget is Tooltip ? widget.message : null;
    if (text != null && RegExp(r'[\u3400-\u9fff]').hasMatch(text)) untranslated.add(text);
    element.debugVisitOnstageChildren(inspect);
  }
  inspect(contents);
  h.expect(untranslated.isEmpty, 'Untranslated Quick Layouts content: $untranslated');
  h.expect(h.errors.isEmpty, h.errors.map((e) => e.exceptionAsString()).join('\n'));
  await h.screenshot('quick-layouts-en');
  stdout.writeln('PASS English Quick Layouts labels and tooltips; concise Seeds and Apply toolbar actions');
  runApp(const SizedBox.shrink());
  await h.settle();
  session.dispose();
  await repo.close();
  AppLanguage.locale.value = previous;
  exit(0);
}
