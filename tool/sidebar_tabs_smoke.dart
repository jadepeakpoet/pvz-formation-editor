import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'package:pvz_formation_editor/platform/export_preferences.dart';
import 'package:pvz_formation_editor/widgets/sidebar_tabs.dart';
import 'package:pvz_formation_editor/platform/app_theme.dart';
import 'package:pvz_formation_editor/platform/app_language.dart';
import 'sidebar_title_smoke.dart' as h;

Future<void> main() async {
  h.viewport = const Size(1240, 800);
  h.TitleBinding();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  final temp = await Directory.systemTemp.createTemp('pvz-sidebar-tabs-');
  final repo = await FormationRepository.open('${temp.path}/test.sqlite');
  final previousLanguage = AppLanguage.locale.value;
  ExportPreferences.fileOverride = File('${temp.path}/preferences.json');
  ExportPreferences.documentsDirectoryOverride = temp;
  try {
    await OriginalAssets.ensureLoaded();
    runApp(MaterialApp(
        theme: buildAppTheme(),
        home: app.EditorPage(
            session: EditorSession(repo), continueArchive: (_) async {})));
    await h.settle();
    await h.settle();
    await h.settle();
    final dynamic page =
        (h.find((w) => w is app.EditorPage).single as StatefulElement).state;
    h.check(page.classicTab == 2, 'First toolbox page is encyclopedia');
    final tabs = h.find((w) => w is SidebarTabs).single.widget as SidebarTabs;
    h.check(tabs.selected == 2, 'Encyclopedia tab is selected');
    await h.tap('sidebar-library-tab');
    await h.settle();
    await h.settle();
    h.check(page.sidebarMode == 'library',
        'Library tab opens retained library page');
    h.check(
        (h.find((w) => w is SidebarTabs).single.widget as SidebarTabs)
                .selected ==
            0,
        'Library selected');
    await h.tap('toolbox-tab-4');
    await h.settle();
    h.check(page.sidebarMode == 'toolbox' && page.classicTab == 4,
        'Return directly to Load/Export');
    final fetch =
        h.find((w) => w.key == const ValueKey('formation-read-game')).single;
    final input = h
        .find((w) => w is TextField && w.controller == page.inputFormation)
        .single;
    final fetchBox = fetch.renderObject as RenderBox,
        inputBox = input.renderObject as RenderBox;
    h.check(
        fetchBox.localToGlobal(Offset.zero).dy <
            inputBox.localToGlobal(Offset.zero).dy,
        'Read game above input');
    final old = await Directory('${temp.path}/PVZ Formation Editor').create();
    await ExportPreferences.fileOverride!
        .writeAsString(jsonEncode({'directory': old.path}));
    h.check(
        (await ExportPreferences.loadDirectory())!
            .endsWith('PvzFormationEditor'),
        'Old default resolves new folder');
    AppLanguage.locale.value = 'en';
    runApp(MaterialApp(theme: buildAppTheme(), home: const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 410, height: 34,
            child: SidebarTabs(selected: 4, onSelected: ignoreTab)))));
    await h.settle();
    for (var i = 0; i < SidebarTabs.englishLabels.length; i++) {
      final label = SidebarTabs.englishLabels[i];
      final text = h.find((w) => w is Text && w.data == label).single.renderObject as RenderBox;
      final tab = h.find((w) => w.key == ValueKey(i == 0 ? 'sidebar-library-tab' : 'toolbox-tab-$i')).single.renderObject as RenderBox;
      final center = text.localToGlobal(text.size.center(Offset.zero));
      final tabCenter = tab.localToGlobal(tab.size.center(Offset.zero));
      h.check(!label.contains(' ') && (center.dx - tabCenter.dx).abs() < .5 &&
          text.size.width <= tab.size.width, 'English tab must be one word, centered and fit: $label');
    }
    h.check(errors.isEmpty, errors.map((e) => e.exceptionAsString()).join('\n'));
    stdout.writeln(
        'PASS shared sidebar tab navigation, first page, read button position and export folder migration');
  } finally {
    AppLanguage.locale.value = previousLanguage;
    runApp(const SizedBox.shrink());
    await h.settle();
    await repo.close();
    ExportPreferences.fileOverride = null;
    ExportPreferences.documentsDirectoryOverride = null;
    await temp.delete(recursive: true);
  }
  exit(0);
}

void ignoreTab(int index) {}
