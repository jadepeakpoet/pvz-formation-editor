// Real Workspace/LibraryPage UI with temporary SQLite/files. Only OS pickers
// and Clipboard are simulated; template actions use the production callbacks.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as key_ui;
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';
import 'sidebar_fallback_smoke.dart' as ui;

Future<void> main() async {
  ui.FallbackBinding();
  await OriginalAssets.ensureLoaded();
  final directory =
      await Directory.systemTemp.createTemp('pvz-document-workflow-');
  final repo = await FormationRepository.open('${directory.path}/test.sqlite');
  final tabs = EditorTabsController(repo);
  final errors = <FlutterErrorDetails>[];
  final cases = <Map<String, dynamic>>[];
  FlutterError.onError = errors.add;
  String clipboard = '';
  final exportPath = '${directory.path}/template.txt';
  String? pickPath;
  String? savedWorkflowId;
  for (final channel in [
    'plugins.flutter.io/path_provider',
    'plugins.flutter.io/path_provider_macos'
  ]) {
    ParityBinding.handlers[channel] = (_) async => directory.path;
  }
  ParityBinding.handlers[SystemChannels.platform.name] = (call) async {
    if (call.method == 'Clipboard.setData') {
      clipboard = (call.arguments as Map)['text'] as String;
    }
    return null;
  };
  ParityBinding.handlers['pvz_formation_editor/files'] = (call) async {
    if (call.method == 'chooseSavePath') return exportPath;
    if (call.method == 'pickFormation') {
      return pickPath == null
          ? null
          : {'path': pickPath, 'bytes': await File(pickPath!).readAsBytes()};
    }
    throw MissingPluginException();
  };
  runApp(MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: app.EditorWorkspace(
          controller: tabs,
          libraryPath: '${directory.path}/test.sqlite',
          continueArchive: (_) async {})));
  await ui.settle();
  await ui.settle();
  dynamic page() =>
      (ui.elements((w) => w is app.EditorPage).single as StatefulElement).state;
  Future<void> wait(bool Function() condition, String reason) async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (!condition() && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    ui.check(condition(), reason);
  }

  Future<void> test(
      String id, Future<void> Function(Map<String, dynamic>) body) async {
    final filter = Platform.environment['PVZ_DOCUMENT_FILTER'];
    if (filter != null && !RegExp(filter).hasMatch(id)) return;
    final row = <String, dynamic>{'id': id, 'status': 'pass'};
    final before = errors.length;
    try {
      await body(row);
      ui.check(
          errors.length == before, 'Flutter errors ${errors.skip(before)}');
    } catch (e, stack) {
      row.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
    }
    cases.add(row);
    await File(filter == null
            ? '${Directory.systemTemp.path}/pvz-document-workflow-report.json'
            : '${Directory.systemTemp.path}/pvz-document-workflow-focused-report.json')
        .writeAsString(jsonEncode({
      'scope':
          'real headless Workspace and LibraryPage; temporary SQLite/files; OS picker/clipboard simulated',
      'cases': cases
    }));
    stdout.writeln('${row['status']}: $id ${row['error'] ?? ''}');
  }

  Future<void> libraryList() async {
    if (page().sidebarMode != 'library' || page().toolboxVisible != true) {
      await ui.tap('sidebar-library-tab');
    }
    if (ui.keyed('library-detail-back') != null) {
      await ui.tap('library-detail-back');
    }
    await wait(() => ui.keyed('library-section-预制名阵') != null, 'library list');
    await ui.tap('library-section-预制名阵');
  }

  final preset = LibraryPresets.all.first;
  final original = jsonEncode(preset.document.toJson());
  Future<void> presetDetail() async {
    await libraryList();
    await ui.tap('library-item-preset:${preset.id}');
  }

  Future<void> tapElement(Element element) async {
    await Scrollable.ensureVisible(element,
        duration: Duration.zero, alignment: .5);
    await ui.settle();
    final box = element.renderObject as RenderBox;
    final point = box.localToGlobal(box.size.center(Offset.zero));
    GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: 77, position: point, buttons: 1));
    GestureBinding.instance
        .handlePointerEvent(PointerUpEvent(pointer: 77, position: point));
    await ui.settle();
  }

  Future<void> menu(String action) async {
    await ui.tap('library-menu-preset:${preset.id}');
    final item = ui
        .elements((w) => w is PopupMenuItem<String> && w.value == action)
        .single;
    await tapElement(item);
  }

  Future<void> clickText(String text) async {
    await tapElement(ui.elements((w) => w is Text && w.data == text).last);
  }

  Future<void> typeInlineName(String value) async {
    final editor = ui
        .elements((w) =>
            w is EditableText && w.controller == page().documentNameEditor)
        .single as StatefulElement;
    (editor.state as EditableTextState).updateEditingValue(TextEditingValue(
        text: value, selection: TextSelection.collapsed(offset: value.length)));
    await ui.settle();
  }

  Future<void> submitInlineName() async {
    final editor = ui
        .elements((w) =>
            w is EditableText && w.controller == page().documentNameEditor)
        .single as StatefulElement;
    (editor.state as EditableTextState).performAction(TextInputAction.done);
    await ui.settle();
    await page().finishDocumentRename();
  }

  Future<void> escapeInlineName() async {
    for (final type in [key_ui.KeyEventType.down, key_ui.KeyEventType.up]) {
      ServicesBinding.instance.platformDispatcher.onKeyData!(key_ui.KeyData(
          timeStamp: Duration.zero,
          type: type,
          physical: PhysicalKeyboardKey.escape.usbHidUsage,
          logical: LogicalKeyboardKey.escape.keyId,
          character: null,
          synthesized: true));
    }
    await ui.settle();
  }

  await test('workflow.fallback-window-height', (row) async {
    await libraryList();
    final sidebar =
        ui.keyed('fallback-sidebar-window')!.renderObject as RenderBox;
    final scene =
        ui.keyed('original-window-background-1')!.renderObject as RenderBox;
    ui.check(
        sidebar.size.height == scene.size.height && scene.size.height > 500,
        'Fallback side/PVZ visible window heights differ');
    ui.check(
        (sidebar.localToGlobal(Offset.zero).dy -
                    scene.localToGlobal(Offset.zero).dy)
                .abs() <
            1,
        'Fallback windows not top aligned');
    row['height'] = sidebar.size.height;
  });
  await test('workflow.template-current-new', (row) async {
    await presetDetail();
    await ui.tap('library-open-current');
    await wait(
        () => page().sidebarMode == 'toolbox', 'template current toolbox');
    ui.check(
        tabs.sessions.length == 1 &&
            !tabs.active.readOnly &&
            jsonEncode(tabs.active.document.toJson()) == original,
        'Template current must be editable exact source');
    final first = tabs.active;
    await presetDetail();
    await ui.tap('library-open-tab');
    ui.check(tabs.sessions.length == 1 && identical(tabs.active, first),
        'Already-open template workcopy should be reused');
    await libraryList();
    await ui.tap('library-item-preset:${LibraryPresets.all[1].id}');
    await ui.tap('library-open-tab');
    await wait(() => tabs.sessions.length == 2, 'template new tab');
    ui.check(
        !tabs.active.readOnly &&
            tabs.active.id != first.id &&
            tabs.sessions.first == first,
        'Template new tab lost old workcopy');
    ui.check(
        jsonEncode(preset.document.toJson()) == original, 'Template mutated');
    row['names'] = tabs.sessions.map((s) => s.name).toList();
  });
  await test('workflow.template-copy', (row) async {
    await presetDetail();
    await ui.tap('library-copy-code');
    ui.check(clipboard == FormationExchange.encode(preset.document),
        'Template copy is not Toolkit');
    row['clipboard'] = clipboard;
  });
  await test('workflow.template-preview-export', (row) async {
    await presetDetail();
    await menu('export');
    await clickText('选择保存位置');
    await wait(
        () => File(exportPath).existsSync(), 'template actual exported file');
    ui.check(
        await File(exportPath).readAsString() ==
            FormationExchange.encode(preset.document),
        'Template export differs');
    await menu('preview');
    await wait(() => tabs.active.readOnly, 'readonly template preview');
    ui.check(jsonEncode(tabs.active.document.toJson()) == original,
        'Preview mutated source');
    row['readonly'] = tabs.active.readOnly;
  });
  await test('workflow.template-copy-persistence-favorites-hidden', (row) async {
    await presetDetail();
    ui.check(ui.keyed('library-favorite') == null, 'Favorite entry stays hidden');
    await repo.setPresetFavorite(preset.id, true);
    ui.check((await repo.listFavoritePresets()).contains(preset.id),
        'Favorite not persisted');
    final reloaded =
        await FormationRepository.open('${directory.path}/test.sqlite');
    ui.check((await reloaded.listFavoritePresets()).contains(preset.id),
        'Favorite lost after second connection');
    await reloaded.close();
    final count = (await repo.listArchives()).length;
    final active = tabs.active;
    await ui.tap('library-add-preset');
    await ui.tap('library-add-preset');
    final copies = await repo.listArchives();
    ui.check(copies.length == count + 2 && tabs.active == active,
        'Add to mine must only create own copies');
    ui.check(copies.map((a) => a.name).toSet().length == copies.length,
        'Copy names collide');
    ui.check(jsonEncode(preset.document.toJson()) == original,
        'Built-in catalog mutated');
    row['archives'] = copies.length;
  });
  await test('workflow.save-rename-history', (row) async {
    await presetDetail();
    await ui.tap('library-open-current');
    await tabs.active.flush();
    final id = tabs.active.sourceArchiveId!;
    savedWorkflowId = id;
    final before = (await repo.listVersions(id)).length;
    final titleBox = ui
        .elements((w) => w.key == const ValueKey('document-title'))
        .single
        .renderObject as RenderBox;
    final renameBox = ui
        .elements((w) => w.key == const ValueKey('document-rename'))
        .single
        .renderObject as RenderBox;
    final gap = renameBox.localToGlobal(Offset.zero).dx -
        titleBox.localToGlobal(Offset(titleBox.size.width, 0)).dx;
    ui.check(gap >= -1 && gap <= 6,
        'Rename icon must sit directly beside document title');
    final originalName = tabs.active.name;
    final originalDepth = tabs.active.undoDepth;
    await ui.tap('document-title');
    ui.check(
        ui.elements((w) => w is AlertDialog).isEmpty &&
            ui.keyed('document-name-input') != null,
        'Title must become inline field without dialog');
    ui.check(
        page().documentNameEditor.selection.baseOffset == 0 &&
            page().documentNameEditor.selection.extentOffset ==
                originalName.length,
        'Inline name must select original text');
    await typeInlineName('工作流存档');
    await submitInlineName();
    ui.check(tabs.active.undoDepth == originalDepth + 1,
        'Submit must create exactly one rename command');
    await page().undoEditing();
    ui.check(tabs.active.name == originalName,
        'Inline rename undo lost original title');
    await page().redoEditing();

    await tabs.active.flush();
    ui.check(
        tabs.active.name == '工作流存档', 'Tab/session name did not adopt rename');
    final renameDepth = tabs.active.undoDepth;
    await ui.settle();
    await ui.tap('document-rename');
    ui.check(
        ui.keyed('document-name-input') != null &&
            ui.elements((w) => w is AlertDialog).isEmpty,
        'Adjacent icon must edit inline');
    await typeInlineName('取消这个名称');
    await escapeInlineName();
    ui.check(ui.keyed('document-name-input') == null,
        'Escape did not close inline field');

    ui.check(
        tabs.active.name == '工作流存档' && tabs.active.undoDepth == renameDepth,
        'Cancel rename changed name or undo history');
    await ui.tap('document-title');
    await typeInlineName('   ');
    await submitInlineName();
    ui.check(
        tabs.active.name == '工作流存档' && tabs.active.undoDepth == renameDepth,
        'Empty inline input must preserve original name/history');
    await ui.tap('document-title');
    await typeInlineName('工作流失焦保存');
    await ui.tap('workspace-more');
    await ui.tap('archive-save');
    await wait(() => tabs.active.name == '工作流失焦保存',
        'Blur/save did not commit inline rename');
    await tabs.active.flush();
    ui.check(tabs.active.undoDepth == renameDepth + 1,
        'Blur and Save duplicated rename command');
    await page().undoEditing();
    ui.check(tabs.active.name == '工作流存档', 'Blur rename was not undoable');
    tabs.active
        .execute('UI workflow edit', tabs.active.document.copy(sunValue: 1234));
    await tabs.active.flush();
    await ui.tap('workspace-more');
    await ui.tap('archive-save');
    ui.check(ui.elements((w) => w is AlertDialog).isEmpty,
        'Save must not show Save As dialog');
    final saved = (await repo.listArchives()).singleWhere((a) => a.id == id);
    ui.check(
        saved.name == tabs.active.name &&
            Formation.fromJson(saved.document).sunValue == 1234,
        'In-place archive/name differs');
    ui.check((await repo.listVersions(id)).length >= before + 2,
        'Rename/edit history missing');
    ui.check((await repo.listDrafts()).isEmpty,
        'Draft UI model must not create storage records');
    row.addAll({
      'archiveId': id,
      'name': saved.name,
      'versions': (await repo.listVersions(id)).length
    });
  });
  await test('workflow.save-as-identity-name', (row) async {
    final originalId = tabs.active.sourceArchiveId;
    final originalName = tabs.active.name;
    final saving = page().saveArchive(saveAs: true) as Future<void>;
    await ui.settle();
    final suggested =
        (ui.keyed('archive-name')!.widget as TextField).controller!.text;
    ui.check(suggested != originalName, 'Save As suggested a colliding name');
    await ui.tap('archive-confirm');
    await saving;
    ui.check(
        tabs.active.sourceArchiveId != originalId &&
            tabs.active.name == suggested,
        'Save As did not adopt unique identity/name');
    final saved = (await repo.listArchives())
        .singleWhere((a) => a.id == tabs.active.sourceArchiveId);
    ui.check(
        saved.name == tabs.active.name, 'Save As archive/tab names differ');
    row.addAll({'archiveId': saved.id, 'name': saved.name});
  });
  await test('workflow.actual-history-rollback-linked-tabs', (row) async {
    final id = savedWorkflowId!;
    for (var i = 0; i < 2; i++) {
      await page()
          .openLibraryItem({'kind': 'archive-edit', 'id': id, 'newTab': true});
      await ui.settle();
    }
    final before = (await repo.listVersions(id)).length;
    final expected = (await repo.listVersions(id)).first;
    await libraryList();
    await ui.tap('library-section-我的存档');
    await ui.tap('library-menu-archive:$id');
    await tapElement(ui
        .elements((w) => w is PopupMenuItem<String> && w.value == 'versions')
        .single);
    await tapElement(ui.elements((w) => w is SimpleDialogOption).first);
    await wait(
        () =>
            tabs.active.document.fingerprint ==
            Formation.fromJson(expected.document).fingerprint,
        'actual history selection restored');
    final linked = tabs.sessions
        .where((s) => !s.readOnly && s.sourceArchiveId == id)
        .toList();
    ui.check(
        linked.length == 1 &&
            linked.every((s) =>
                s.document.fingerprint ==
                    Formation.fromJson(expected.document).fingerprint &&
                s.name == tabs.active.name),
        'Linked tabs not synchronized to restored saved baseline');
    ui.check((await repo.listVersions(id)).length == before + 1,
        'Rollback must preserve prior head as one version');
    tabs.active.execute(
        'edit after rollback', tabs.active.document.copy(sunValue: 4321));
    await tabs.active.flush();
    ui.check(
        tabs.active.error == null &&
            Formation.fromJson((await repo.listArchives())
                        .singleWhere((a) => a.id == id)
                        .document)
                    .sunValue ==
                4321,
        'Restored tab cannot continue saving');
    row.addAll({
      'linkedTabs': linked.length,
      'versions': (await repo.listVersions(id)).length
    });
  });
  await test('workflow.import-skips-identical', (row) async {
    await libraryList();
    final document = Formation(mapId: 'day', sunValue: 2222);
    pickPath = '${directory.path}/myformation.pvzf.json';
    await File(pickPath!).writeAsString(ProjectCodec.encode(document));
    final count = (await repo.listArchives()).length;
    dynamic libraryPage() =>
        (ui.elements((w) => w is app.LibraryPage).single as StatefulElement)
            .state;
    await libraryPage().importProject();
    await tabs.active.flush();
    ui.check(
        (await repo.listArchives()).length == count + 1 &&
            tabs.active.filePath == pickPath &&
            tabs.active.name == 'myformation',
        'Single formation import failed or file association lost');
    await libraryList();
    await libraryPage().importProject();
    ui.check((await repo.listArchives()).length == count + 1,
        'Duplicate single import created another archive');
    await File(pickPath!)
        .writeAsString(ProjectCodec.encode(document.copy(sunValue: 2223)));
    await libraryPage().importProject();
    await tabs.active.flush();
    ui.check(
        (await repo.listArchives()).length == count + 2 &&
            tabs.active.name == 'myformation（2）',
        'Differing content with same filename did not receive unique canonical name');
    await libraryList();
    const website = '2,0 1 1 0 0 0';
    pickPath = '${directory.path}/website.txt';
    await File(pickPath!).writeAsString(website);
    final websiteCount = (await repo.listArchives()).length;
    ui.check(
        WebsiteCodec.decode(website).fingerprint !=
            WebsiteCodec.decode(website).fingerprint,
        'Website fixture must generate fresh IDs to exercise content deduplication');
    await libraryPage().importProject();
    await tabs.active.flush();
    await libraryList();
    await libraryPage().importProject();
    ui.check((await repo.listArchives()).length == websiteCount + 1,
        'Repeated Website code with new object IDs was not skipped');
    row['skippedIdentical'] = true;
  });
  await test('workflow.new-blank-auto-archives', (row) async {
    final count = (await repo.listArchives()).length;
    final created = <String>[];
    for (var i = 0; i < 3; i++) {
      await ui.tap('editor-new-tab');
      await tabs.active.flush();
      ui.check(tabs.active.sourceArchiveId == null, 'Untouched new tab remains temporary');
      tabs.active.rename('Auto archive $i');
      await tabs.active.flush();
      created.add(tabs.active.name);
      ui.check(
          tabs.active.sourceArchiveId != null &&
              tabs.active.document.pieces.isEmpty,
          'New blank not auto archived');
    }
    ui.check(created.toSet().length == 3, 'New blank names collide');
    ui.check(
        (await repo.listArchives()).length == count + 3 &&
            (await repo.listDrafts()).isEmpty,
        'New blanks must be own archives only');
    row['names'] = created;
  });
  await test('workflow.inline-rename-switch', (row) async {
    await tabs.newBlank();
    await ui.settle();
    final previous = tabs.active;
    final previousName = previous.name;
    await ui.tap('document-title');
    await typeInlineName('切换前原地命名');
    await ui.tap('editor-new-tab');
    await wait(() => !identical(tabs.active, previous),
        'Inline rename blocked tab creation');
    ui.check(
        previous.name == '切换前原地命名' &&
            tabs.active.name != previous.name &&
            !page().editingDocumentName,
        'Inline name leaked to another tab or was discarded');
    await tabs.activate(tabs.sessions.indexOf(previous));
    await ui.settle();
    await page().undoEditing();
    ui.check(previous.name == previousName,
        'Rename before tab switch must remain undoable');
    await tabs.open(
        EditorSession(repo,
            document: previous.document, name: '只读标题', readOnly: true),
        newTab: true);
    await ui.settle();
    final title = ui.keyed('document-title')!.widget as InkWell;
    final icon = ui.keyed('document-rename')!.widget as IconButton;
    ui.check(
        title.onTap == null &&
            icon.onPressed == null &&
            ui.keyed('document-name-input') == null,
        'Readonly document must not allow inline rename');
  });
  await tabs.flushAll();
  runApp(const SizedBox.shrink());
  await ui.settle();
  tabs.dispose();
  await repo.close();
  exit(cases.every((c) => c['status'] == 'pass') ? 0 : 1);
}
