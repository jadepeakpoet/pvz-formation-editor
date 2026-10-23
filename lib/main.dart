import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, File;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'domain/formation.dart';
import 'domain/formation_exchange.dart';
import 'domain/formation_formatter.dart';
import 'domain/game_save_codec.dart';
import 'domain/archive_bundle.dart';
import 'domain/original_terrain.dart';
import 'domain/planting_support.dart';
import 'platform/planting_preferences.dart';
import 'platform/app_language.dart';
import 'platform/language_selector.dart';
import 'domain/layouts.dart';
import 'domain/object_filter.dart';
import 'editor/board_painter.dart';
import 'editor/board_sun_editor.dart';
import 'editor/batch_selection_overlay.dart';
import 'widgets/app_dropdown.dart';
import 'editor/rename_dialog.dart';
import 'editor/map_picker_dialog.dart';
import 'editor/archive_history_dialog.dart';
import 'editor/shovel_targets.dart';
import 'editor/classic_window.dart';
import 'editor/original_assets.dart';
import 'domain/original_catalog.dart';
import 'editor/editor_session.dart';
import 'editor/editor_tabs.dart';
import 'editor/seed_chooser.dart';
import 'platform/project_files.dart';
import 'platform/original_audio.dart';
import 'platform/window_bridge.dart';
import 'storage/formation_repository.dart';
import 'library/library_browser.dart';
import 'library/archive_tags_dialog.dart';
import 'library/library_presets.dart';
import 'library/archive_dedup_dialog.dart';
import 'library/game_panel.dart';
import 'library/archive_files.dart';
import 'library/formation_images.dart';
import 'library/export_settings_dialog.dart';
import 'storage/file_backups.dart';

final List<Future<bool> Function()> exitGuards = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const MethodChannel('pvz_formation_editor/lifecycle')
      .setMethodCallHandler((call) async {
    if (call.method != 'prepareExit') throw MissingPluginException();
    for (final guard in exitGuards.reversed.toList()) {
      if (!await guard()) return false;
    }
    return true;
  });
  runApp(_StartupApp(
      label: '正在打开庭院…',
      prepare: () async {
        await Future.wait([
          OriginalAssets.ensureLoaded(),
          PlantingPreferences.load(),
          AppLanguage.load()
        ]);
        return const FormationApp();
      }));
}

@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(_StartupApp(
      label: '正在加载工具箱…',
      prepare: () async {
        await Future.wait([OriginalAssets.ensureLoaded(), AppLanguage.load()]);
        final repository = await FormationRepository.open(':memory:');
        final session = EditorSession(repository, persistDraft: false);
        return LanguageScope(
            builder: () => MaterialApp(
                locale: Locale(AppLanguage.locale.value),
                supportedLocales: const [Locale('zh'), Locale('en')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                title: AppLanguage.text('布阵器工具箱'),
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                    useMaterial3: true,
                    inputDecorationTheme: const InputDecorationTheme(
                        border: OutlineInputBorder(), isDense: true)),
                home: EditorPage(
                    session: session,
                    toolboxOnly: true,
                    continueArchive: (_) async {})));
      }));
}

/// Paint a first frame before preparing a separate engine's artwork.
@pragma('vm:entry-point')
Future<void> libraryMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(_StartupApp(
      label: '正在加载存档库…',
      prepare: () async {
        await Future.wait([OriginalAssets.ensureLoaded(), AppLanguage.load()]);
        return LanguageScope(
            builder: () => MaterialApp(
                  locale: Locale(AppLanguage.locale.value),
                  supportedLocales: const [Locale('zh'), Locale('en')],
                  localizationsDelegates: GlobalMaterialLocalizations.delegates,
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(
                      useMaterial3: true,
                      colorScheme: ColorScheme.fromSeed(
                          seedColor: const Color(0xff456b4e))),
                  home: const LibraryPage(independent: true, showTitle: false),
                ));
      }));
}

class _StartupApp extends StatefulWidget {
  final String label;
  final Future<Widget> Function() prepare;
  const _StartupApp({required this.label, required this.prepare});
  @override
  State<_StartupApp> createState() => _StartupAppState();
}

class _StartupAppState extends State<_StartupApp> {
  late Future<Widget> prepared;
  @override
  void initState() {
    super.initState();
    prepared = prepare();
  }

  Future<Widget> prepare() async {
    await WidgetsBinding.instance.endOfFrame;
    return widget.prepare();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
      future: prepared,
      builder: (_, state) {
        if (state.hasData) return state.data!;
        return LanguageScope(
            builder: () => MaterialApp(
                locale: Locale(AppLanguage.locale.value),
                supportedLocales: const [Locale('zh'), Locale('en')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                    colorScheme: ColorScheme.fromSeed(
                        seedColor: const Color(0xff456b4e))),
                home: Scaffold(
                    backgroundColor: const Color(0xfff3f6eb),
                    body: Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.grass_rounded,
                                      size: 36, color: Color(0xff456b4e)),
                                  const SizedBox(height: 18),
                                  Text(
                                      AppLanguage.text(state.hasError
                                          ? '暂时无法打开，请重试'
                                          : widget.label),
                                      style: const TextStyle(
                                          color: Color(0xff304b32))),
                                  const SizedBox(height: 18),
                                  if (state.hasError)
                                    OutlinedButton(
                                        onPressed: () => setState(
                                            () => prepared = prepare()),
                                        child: Text(AppLanguage.text('重试')))
                                  else
                                    const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)),
                                ]))))));
      });
}

class FormationApp extends StatelessWidget {
  const FormationApp({super.key});
  @override
  Widget build(BuildContext context) => LanguageScope(
      builder: () => MaterialApp(
          locale: Locale(AppLanguage.locale.value),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          title: AppLanguage.text('植物大战僵尸布阵器'),
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xff456b4e),
                  brightness: Brightness.light),
              scaffoldBackgroundColor: const Color(0xfff4f5f0),
              inputDecorationTheme: const InputDecorationTheme(
                  border: OutlineInputBorder(), isDense: true)),
          home: const LibraryPage()));
}

void message(BuildContext context, Object text) {
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(AppLanguage.text('$text'))));
  }
}

Future<String?> textPrompt(BuildContext context, String title,
    {String initial = '', bool multiline = false}) async {
  final c = TextEditingController(text: initial);
  final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: Text(AppLanguage.text(title)),
              content: SizedBox(
                  width: 560,
                  child: TextField(
                      controller: c,
                      autofocus: true,
                      maxLines: multiline ? 10 : 1,
                      decoration:
                          InputDecoration(labelText: AppLanguage.text('内容')))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(AppLanguage.text('取消'))),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, c.text),
                    child: Text(AppLanguage.text('确定')))
              ]));
  // Controller is retained until dialog removal has completed.
  Future.delayed(const Duration(seconds: 1), c.dispose);
  return result;
}

Future<bool> confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(AppLanguage.text(title)),
                content: Text(AppLanguage.text(body)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(AppLanguage.text('取消'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(AppLanguage.text('确认')))
                ])) ??
    false;

Future<FormationFormat?> formationFormatPrompt(
    BuildContext context, Formation document,
    {FormationFormat initial = FormationFormat.toolkit}) async {
  var choice = initial;
  return showDialog<FormationFormat>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
            final issues =
                FormationExchange.exportIssues(document, format: choice);
            return AlertDialog(
                title: Text(AppLanguage.text('导出阵图')),
                content: SizedBox(
                    width: 430,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final f in FormationFormat.values)
                        RadioListTile<FormationFormat>(
                            value: f,
                            groupValue: choice,
                            title: Text(f.label),
                            subtitle: Text(f.description,
                                style: const TextStyle(fontSize: 11)),
                            dense: true,
                            onChanged: (v) {
                              if (v != null) set(() => choice = v);
                            }),
                      if (issues.isNotEmpty)
                        ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 160),
                            child: SingleChildScrollView(
                                child: Text(
                                    AppLanguage.text(
                                        '该格式无法保存以下内容，请选择其他格式：\n${issues.join('\n')}'),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.deepOrange))))
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(AppLanguage.text('取消'))),
                  FilledButton(
                      onPressed: issues.isEmpty
                          ? () => Navigator.pop(ctx, choice)
                          : null,
                      child: Text(AppLanguage.text('选择保存位置')))
                ]);
          }));
}

class LibraryPage extends StatefulWidget {
  const LibraryPage(
      {super.key,
      this.independent = false,
      this.showTitle = true,
      this.repository,
      this.activeDraftId,
      this.onOpenSession,
      this.onOpenTab,
      this.onDocumentAction});
  final bool independent;
  final bool showTitle;
  final FormationRepository? repository;
  final String? activeDraftId;
  final Future<void> Function(EditorSession)? onOpenSession;
  final Future<void> Function(EditorSession)? onOpenTab;
  final Future<bool> Function(Map<String, dynamic>)? onDocumentAction;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  FormationRepository? repo;
  List<DraftRecord> drafts = [];
  List<ArchiveRecord> archives = [];
  Set<String> favoritePresetIds = {};
  String? error, dataPath;
  String? activeDraftId;
  bool openedEditor = false;
  bool loading = true;
  EditorTabsController? workspace;
  static const libraryChannel = MethodChannel('pvz_formation_editor/library');
  @override
  void initState() {
    super.initState();
    activeDraftId = widget.activeDraftId;
    _open();
  }

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.independent) activeDraftId = widget.activeDraftId;
  }

  Future<void> _open() async {
    try {
      if (widget.independent) {
        libraryChannel.setMethodCallHandler((call) async {
          if (call.method == 'refresh') {
            if (call.arguments is Map) {
              activeDraftId =
                  (call.arguments as Map)['activeDraftId'] as String?;
            }
            if (repo == null) return true;
            await refresh();
            return true;
          }
          throw MissingPluginException();
        });
        final configuration =
            await libraryChannel.invokeMapMethod<String, dynamic>('ready');
        dataPath = configuration?['dataPath'] as String?;
        activeDraftId = configuration?['activeDraftId'] as String?;
        if (dataPath == null) throw StateError('存档库缺少数据位置');
      } else if (widget.repository == null) {
        final dir = await getApplicationSupportDirectory();
        await dir.create(recursive: true);
        dataPath = '${dir.path}/formations.sqlite';
      }
      repo = widget.repository ?? await FormationRepository.open(dataPath!);
      await refresh();
      if (!widget.independent &&
          widget.repository == null &&
          !openedEditor &&
          mounted) {
        openedEditor = true;
        final session = await EditorSession.resume(repo!);
        if (!mounted) {
          session.dispose();
          return;
        }
        await edit(session);
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> refresh() async {
    try {
      final d = await repo!.listDrafts(), a = await repo!.listArchives();
      final favorites = await repo!.listFavoritePresets();
      if (mounted) {
        setState(() {
          drafts = d;
          archives = a;
          favoritePresetIds = favorites;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> edit(EditorSession session, {bool newTab = false}) async {
    if (!session.readOnly) {
      await session.flush();
      if (session.error != null) throw StateError(session.error!);
    }
    if (widget.independent) {
      try {
        // Saved snapshots can cross as in-memory documents; new work has a
        // draft identity even before its first placement.
        final existing = session.readOnly
            ? false
            : (await repo!.listDrafts()).any((d) => d.id == session.id);
        final presetPreview =
            session.readOnly && session.id.startsWith('preview-original-');
        final kind = session.readOnly
            ? (presetPreview ? 'preset-preview' : 'archive')
            : existing
                ? 'draft'
                : session.sourceArchiveId != null
                    ? 'archive-edit'
                    : 'new';
        final opened = await libraryChannel.invokeMethod<bool>('openEditor', {
          'kind': kind,
          'newTab': newTab,
          if (kind == 'new')
            'documentJson': jsonEncode(session.document.toJson()),
          if (kind == 'new') 'name': session.name,
          'id': presetPreview
              ? session.id.substring('preview-'.length)
              : kind == 'archive-edit'
                  ? session.sourceArchiveId
                  : session.id,
          'filePath': session.filePath,
          'fileFormat': session.fileFormat,
        });
        if (opened != true) throw StateError('主编辑器暂时无法打开，请稍后重试');
      } finally {
        session.dispose();
      }
      await refresh();
      return;
    }
    if (newTab && widget.onOpenTab != null) {
      await widget.onOpenTab!(session);
      return;
    }
    if (widget.onOpenSession != null) {
      await widget.onOpenSession!(session);
      return;
    }
    if (workspace != null) {
      await workspace!.open(session, newTab: newTab);
      return;
    }
    if (!mounted) {
      session.dispose();
      return;
    }
    workspace = EditorTabsController(repo!, initial: session);
    final route = MaterialPageRoute<void>(
        builder: (_) => EditorWorkspace(
            controller: workspace!,
            libraryPath: dataPath,
            continueArchive: (a) => continueArchive(a)));
    await Navigator.push<void>(context, route);
    await route.completed;
    await workspace!.flushAll();
    workspace!.dispose();
    workspace = null;
    await refresh();
  }

  Future<void> continueArchive(ArchiveRecord archive,
      {bool newTab = false}) async {
    try {
      await refresh();
      final linked =
          drafts.where((d) => d.sourceArchiveId == archive.id).toList();
      if (!mounted) return;
      if (!newTab && linked.isNotEmpty) {
        await edit(EditorSession.fromDraft(repo!, linked.first));
        return;
      }
      final document = Formation.fromJson(archive.document);
      final session = EditorSession(repo!,
          document: document,
          name: archive.name,
          sourceArchiveId: archive.id,
          savedFingerprint: document.fingerprint);
      await session.markArchived(archive.id, document.fingerprint);
      if (mounted) await edit(session, newTab: newTab);
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  Future<void> importProject() async {
    try {
      final picked = await ProjectFiles.pickWithPath();
      if (picked == null) return;
      final text = utf8.decode(picked.bytes);
      if (ArchiveBundle.recognizes(text)) {
        final result = await ArchiveFiles.importCollection(repo!, text);
        await refresh();
        if (mounted) message(context, '$result');
        return;
      }
      final doc = FormationExchange.decode(text);
      if (await skipExistingImport(doc)) return;
      final fileName = picked.path
          ?.replaceAll('\\', '/')
          .split('/')
          .last
          .replaceFirst(
              RegExp(r'(\.pvzf\.json|\.pvzf|\.json|\.txt)$',
                  caseSensitive: false),
              '')
          .trim();
      final s = EditorSession(repo!,
          document: doc,
          name: await uniqueName(
              fileName == null || fileName.isEmpty ? '导入的阵型' : fileName))
        ..filePath = picked.path
        ..fileFormat = FormationExchange.detectFormat(text).name;
      if (mounted) await edit(s);
    } catch (e) {
      if (mounted) message(context, '导入失败：$e');
    }
  }

  Future<bool> skipExistingImport(Formation document) async {
    final matches = (await repo!.listArchives()).any((archive) =>
        ArchiveBundle.importFingerprint(Formation.fromJson(archive.document)) ==
        ArchiveBundle.importFingerprint(document));
    if (matches && mounted) message(context, '已跳过 1 个内容相同的阵型');
    return matches;
  }

  Future<void> importGameSave() async {
    try {
      final picked = await ProjectFiles.pickWithPath();
      if (picked == null) return;
      final imported = GameSaveCodec.decode(picked.bytes);
      if (!mounted) return;
      final document = imported.formation;
      if (await skipExistingImport(document)) return;
      if (!mounted) return;
      final plantCount =
          document.pieces.where((piece) => piece.spec.category == '植物').length;
      final newTab = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: Text(AppLanguage.text('导入 PC 无尽存档（实验）')),
                content: SizedBox(
                    width: 500,
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(AppLanguage.text(
                              '仅导入布阵，不恢复完整战斗进度。源 .dat 文件不会被修改。')),
                          const SizedBox(height: 12),
                          Text(AppLanguage.text('场地：${document.map.name}\n'
                              '植物：$plantCount，场地物品：${document.pieces.length - plantCount}，'
                              '阳光：${document.sunValue}')),
                          const SizedBox(height: 12),
                          ...imported.warnings.map((warning) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(warning))),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(AppLanguage.text('取消'))),
                  OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(AppLanguage.text('导入当前标签'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(AppLanguage.text('导入新标签'))),
                ],
              ));
      if (newTab == null || !mounted) return;
      // No filePath association: saving this editor document must never replace
      // the original binary game save with project JSON or a placement code.
      final session = EditorSession(repo!,
          document: document,
          name: await uniqueName('PC 无尽存档 · ${document.map.name}'));
      await edit(session, newTab: newTab);
    } catch (e) {
      if (mounted) message(context, 'PC 存档导入失败：$e');
    }
  }

  Future<void> importString() async {
    final value = await textPrompt(context, '导入阵型（Toolkit / 布阵器 / PVZF1）',
        multiline: true);
    if (value == null) return;
    try {
      final document = FormationExchange.decode(value);
      if (await skipExistingImport(document)) return;
      final session = EditorSession(repo!,
          document: document, name: await uniqueName('导入的阵型'));
      if (mounted) await edit(session);
    } catch (e) {
      if (mounted) message(context, '导入失败：$e');
    }
  }

  Future<void> deduplicateLibraryArchives() async {
    final request = <String, dynamic>{'kind': 'archive-dedup'};
    if (widget.independent) {
      final handled = await libraryChannel.invokeMethod<bool>('openEditor', request);
      if (handled != true) throw StateError('主编辑器暂时无法执行去重');
    } else if (widget.onDocumentAction != null) {
      if (!await widget.onDocumentAction!(request)) return;
    } else {
      Set<String> protected() => {
        for (final session in workspace?.allSessions ?? <EditorSession>[])
          if (session.sourceArchiveId != null) session.sourceArchiveId!,
        if (widget.activeDraftId != null) widget.activeDraftId!,
      };
      final result = await showArchiveDedupDialog(context, repo!,
          protectedArchiveIds: protected,
          flushEditors: () async {
            if (workspace != null && !await workspace!.flushAll()) {
              throw StateError(workspace!.error ?? '无法保存打开的存档');
            }
          });
      if (result != null && mounted) {
        message(context, '已清理 ${result.removedCount} 个重复存档，历史版本已保留。');
      }
    }
    await refresh();
  }

  Future<void> archiveAction(String action, ArchiveRecord a) async {
    try {
      if (action == 'copy-image' || action == 'export-image') {
        final document = Formation.fromJson(a.document);
        if (action == 'copy-image') {
          await FormationImages.copy(document);
          if (mounted) message(context, '已复制阵型图片');
        } else {
          await FormationImages.export(document, a.name);
        }
        return;
      }
      if (action == 'edit' ||
          action == 'open-current' ||
          action == 'open-tab') {
        await continueArchive(a, newTab: action == 'open-tab');
        return;
      }
      if (action == 'copy-code') {
        final code = FormationExchange.encode(Formation.fromJson(a.document));
        await Clipboard.setData(ClipboardData(text: code));
        if (mounted) message(context, '已复制 Toolkit 阵型码');
        return;
      }
      if (action == 'preview') {
        await edit(EditorSession(repo!,
            document: Formation.fromJson(a.document),
            name: a.name,
            id: a.id,
            readOnly: true,
            sourceArchiveId: a.id));
        return;
      }
      if (action == 'favorite') {
        await repo!.updateArchiveMetadata(a.id, favorite: !a.favorite);
      }
      if (action == 'copy') {
        await repo!.saveArchive(
            id: newId(),
            name: await uniqueName(a.name),
            document: a.document,
            note: a.note,
            tags: a.tags,
            uniqueName: true);
      }
      if (action == 'rename' && mounted) {
        final requested = await textPrompt(context, '重命名存档', initial: a.name);
        if (requested != null &&
            requested.trim().isNotEmpty &&
            requested.trim() != a.name) {
          final name = await uniqueName(requested);
          final request = <String, dynamic>{
            'kind': 'archive-rename',
            'id': a.id,
            'name': name
          };
          if (widget.independent) {
            if (await libraryChannel.invokeMethod<bool>(
                    'openEditor', request) !=
                true) throw StateError('主窗口未接受修改');
          } else if (widget.onDocumentAction != null) {
            if (!await widget.onDocumentAction!(request)) {
              throw StateError('主窗口未接受修改');
            }
          } else {
            await repo!.saveArchive(
                id: newId(),
                updateId: a.id,
                name: name,
                document: a.document,
                note: a.note,
                tags: a.tags);
          }
        }
      }
      if ((action == 'metadata' || action == 'tags') && mounted) {
        (String, String, List<String>, bool)? metadata;
        if (action == 'tags') {
          final labels = await archiveTagsDialog(context,
              selected: a.tags,
              available: archives.expand((archive) => archive.tags));
          if (!mounted) return;
          metadata = labels == null ? null : (a.name, a.note, labels, false);
        } else {
          metadata = await archiveDialog(context,
              name: a.name, note: a.note, tags: a.tags, metadata: true);
        }
        if (metadata != null) {
          final name =
              metadata.$1 == a.name ? a.name : await uniqueName(metadata.$1);
          final request = <String, dynamic>{
            'kind': 'archive-rename',
            'id': a.id,
            'name': name,
            'note': metadata.$2,
            'tags': metadata.$3
          };
          if (widget.independent) {
            if (await libraryChannel.invokeMethod<bool>(
                    'openEditor', request) !=
                true) throw StateError('主窗口未接受修改');
          } else if (widget.onDocumentAction != null) {
            if (!await widget.onDocumentAction!(request)) {
              throw StateError('主窗口未接受修改');
            }
          } else {
            await repo!.saveArchive(
                id: newId(),
                updateId: a.id,
                name: name,
                note: metadata.$2,
                tags: metadata.$3,
                document: a.document);
          }
        }
      }
      if (action == 'delete' &&
          mounted &&
          await confirm(context, '删除存档？', '将同时删除此存档及其历史版本。')) {
        final request = <String, dynamic>{'kind': 'archive-delete', 'id': a.id};
        if (widget.independent) {
          if (await libraryChannel.invokeMethod<bool>('openEditor', request) !=
              true) throw StateError('主窗口未接受删除');
        } else if (widget.onDocumentAction != null) {
          if (!await widget.onDocumentAction!(request)) {
            throw StateError('主窗口未接受删除');
          }
        } else {
          await repo!.deleteArchive(a.id);
        }
      }
      if (action == 'export' && mounted) {
        final document = Formation.fromJson(a.document);
        final format = await formationFormatPrompt(context, document);
        if (format != null) {
          await ProjectFiles.save(
              '${safeName(a.name)}.${format.fileExtension}',
              Uint8List.fromList(utf8
                  .encode(FormationExchange.encode(document, format: format))),
              format == FormationFormat.project
                  ? 'application/json'
                  : 'text/plain');
        }
      }
      if (action == 'versions' && mounted) {
        final versions = await repo!.listVersions(a.id);
        if (!mounted) return;
        final v = await showDialog<ArchiveVersion>(
            context: context,
            builder: (ctx) => SimpleDialog(
                title: Text(AppLanguage.text('历史版本与回退')),
                children: versions.isEmpty
                    ? [
                        Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(AppLanguage.text('尚无更新历史')))
                      ]
                    : versions
                        .asMap()
                        .entries
                        .map((entry) => SimpleDialogOption(
                            key: ValueKey('archive-version-${entry.value.id}'),
                            onPressed: () => Navigator.pop(ctx, entry.value),
                            child: Text(AppLanguage.text(
                                '回退到第 ${versions.length - entry.key} 版 · ${entry.value.name}\n'
                                '${date(entry.value.createdAt)}:${entry.value.createdAt.second.toString().padLeft(2, '0')}.${entry.value.createdAt.millisecond.toString().padLeft(3, '0')}'))))
                        .toList()));
        if (v != null && mounted) {
          Formation.fromJson(v.document);
          final request = <String, dynamic>{
            'kind': 'archive-rollback',
            'id': a.id,
            'versionId': v.id
          };
          if (widget.independent) {
            if (await libraryChannel.invokeMethod<bool>(
                    'openEditor', request) !=
                true) throw StateError('主窗口未接受回退');
          } else if (widget.onDocumentAction != null) {
            if (!await widget.onDocumentAction!(request)) {
              throw StateError('主窗口未接受回退');
            }
          } else {
            await repo!.saveArchive(
                id: newId(),
                updateId: a.id,
                name: v.name,
                document: v.document,
                note: v.note,
                tags: v.tags);
          }
          if (mounted) message(context, '已回退，回退前的内容已保留为历史版本');
        }
      }
      await refresh();
    } catch (e) {
      if (mounted) message(context, '操作失败：$e');
    }
  }

  final Set<String> addingPresets = {};
  Future<String> uniqueName(String base) => repo!.uniqueDocumentName(base,
      reservedNames: workspace?.sessions.map((s) => s.name) ?? const []);

  Future<void> presetAction(String action, LibraryPreset preset) async {
    try {
      if (action == 'copy-image' || action == 'export-image') {
        if (action == 'copy-image') {
          await FormationImages.copy(preset.document);
          if (mounted) message(context, '已复制阵型图片');
        } else {
          await FormationImages.export(preset.document, preset.name);
        }
        return;
      }
      if (action == 'copy') {
        await addPreset(preset);
        return;
      }
      if (action == 'favorite') {
        await repo!.setPresetFavorite(
            preset.id, !favoritePresetIds.contains(preset.id));
        await refresh();
        return;
      }
      if (action == 'copy-code') {
        await Clipboard.setData(
            ClipboardData(text: FormationExchange.encode(preset.document)));
        if (mounted) message(context, '已复制 Toolkit 阵型码');
        return;
      }
      if (action == 'export' && mounted) {
        final format = await formationFormatPrompt(context, preset.document);
        if (format != null) {
          await ProjectFiles.save(
              '${safeName(preset.name)}.${format.fileExtension}',
              Uint8List.fromList(utf8.encode(
                  FormationExchange.encode(preset.document, format: format))),
              format == FormationFormat.project
                  ? 'application/json'
                  : 'text/plain');
        }
        return;
      }
      if (action == 'preview') {
        await edit(EditorSession(repo!,
            document: preset.document,
            name: preset.name,
            id: 'preview-${preset.id}',
            readOnly: true));
        return;
      }
      if (action == 'open-current' || action == 'open-tab') {
        final session = EditorSession(repo!,
            document: preset.document, name: preset.name,
            deferInitialSave: true);
        if (!mounted) {
          session.dispose();
          return;
        }
        await edit(session, newTab: action == 'open-tab');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> addPreset(LibraryPreset preset) async {
    if (!addingPresets.add(preset.id)) return;
    try {
      final archive = await repo!.saveArchive(
          id: newId(),
          name: await uniqueName(preset.name),
          uniqueName: true,
          document: preset.document.toJson(),
          note: '来自预制名阵，可创建工作副本继续编辑。',
          tags: ['预制名阵', preset.document.map.name]);
      await refresh();
      if (mounted) message(context, '已加入我的存档：${archive.name}');
    } finally {
      addingPresets.remove(preset.id);
    }
  }

  Future<void> draftAction(String action, DraftRecord d) async {
    if (d.id == activeDraftId && (action == 'rename' || action == 'delete')) {
      message(context, '该草稿正在主窗口编辑，请先打开其他阵型再管理它。');
      return;
    }
    try {
      if (action == 'delete' &&
          await confirm(context, '删除草稿？', '不会影响正式存档。删除后不能撤销。')) {
        await repo!.deleteDraft(d.id);
      }
      if (action == 'rename' && mounted) {
        final name = await textPrompt(context, '重命名草稿', initial: d.name);
        if (name != null && name.trim().isNotEmpty) {
          final session = EditorSession.fromDraft(repo!, d)..rename(name);
          await session.flush();
          final failure = session.error;
          session.dispose();
          if (failure != null) throw StateError(failure);
        }
      }
      await refresh();
    } catch (e) {
      if (mounted) message(context, '草稿操作失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (repo == null || loading) {
      return Scaffold(
          body: Center(
              child: error == null
                  ? const CircularProgressIndicator()
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(AppLanguage.text('无法打开存档库：$error')),
                      FilledButton(
                          onPressed: _open, child: Text(AppLanguage.text('重试')))
                    ])));
    }
    return LibraryBrowser(
      showTitle: widget.showTitle,
      onGameTools: Platform.isWindows
          ? (target) async {
              await showDialog<void>(
                  context: context,
                  builder: (ctx) => GamePanel(
                      target: target,
                      onArchive: (document) async {
                        await repo!.saveArchive(
                            id: newId(),
                            uniqueName: true,
                            name: await uniqueName(
                                '游戏现场 · ${date(DateTime.now())}'),
                            document: document.toJson(),
                            tags: ['游戏现场', document.map.name]);
                        await refresh();
                      },
                      onEdit: (document) async {
                        Navigator.pop(ctx);
                        await edit(EditorSession(repo!,
                            document: document,
                            name: await uniqueName('游戏现场')));
                      }));
            }
          : null,
      presets: LibraryPresets.all,
      onPresetAction: presetAction,
      onSettings: () => showExportSettings(context),
      favoritePresetIds: favoritePresetIds,
      onExportArchives: (records) async {
        try {
          final saved = await ArchiveFiles.exportCollection(records);
          if (saved && context.mounted) {
            message(context, '已导出 ${records.length} 个存档');
          }
        } catch (e) {
          if (context.mounted) message(context, '导出失败：$e');
        }
      },
      onAddPreset: addPreset,
      onDeduplicate: deduplicateLibraryArchives,
      drafts: drafts,
      archives: archives,
      error: error,
      onRefresh: refresh,
      onNew: () async =>
          edit(EditorSession(repo!, name: '新建阵型', deferInitialSave: true)),
      onImportProject: importProject,
      onImportGameSave: importGameSave,
      onImportString: importString,
      onOpenDraft: (d) => edit(EditorSession.fromDraft(repo!, d)),
      onOpenDraftTab: (d) =>
          edit(EditorSession.fromDraft(repo!, d), newTab: true),
      onCopyDraft: (d) async {
        try {
          await Clipboard.setData(ClipboardData(
              text: FormationExchange.encode(Formation.fromJson(d.document))));
          if (context.mounted) message(context, '已复制 Toolkit 阵型码');
        } catch (e) {
          if (context.mounted) message(context, e);
        }
      },
      onOpenArchive: (a) => continueArchive(a),
      onOpenArchiveTab: (a) => continueArchive(a, newTab: true),
      onDraftAction: draftAction,
      onArchiveAction: archiveAction,
    );
  }
}

String date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String mapName(String id) {
  try {
    return BoardMap.byId(id).name;
  } catch (_) {
    return id;
  }
}

String safeName(String name) =>
    name.replaceAll(RegExp(r'[^\w\u4e00-\u9fff-]'), '_');

class MiniBoard extends StatelessWidget {
  final Map<String, dynamic> document;
  const MiniBoard({super.key, required this.document});
  @override
  Widget build(BuildContext context) {
    try {
      final f = Formation.fromJson(document);
      return SizedBox(
          width: 90,
          height: 62,
          child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: FittedBox(
                  child: SizedBox.fromSize(
                      size: BoardGeometry(f).size,
                      child: CustomPaint(
                          painter:
                              BoardPainter(document: f, helpers: false))))));
    } catch (_) {
      return const Icon(Icons.broken_image_outlined);
    }
  }
}

Future<(String, String, List<String>, bool)?> archiveDialog(
    BuildContext context,
    {required String name,
    String note = '',
    List<String> tags = const [],
    bool allowUpdate = false,
    bool saveAs = false,
    bool metadata = false}) async {
  final n = TextEditingController(text: name),
      m = TextEditingController(text: note),
      t = TextEditingController(text: tags.join(', '));
  bool update = false;
  final result = await showDialog<(String, String, List<String>, bool)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
                  title: Text(AppLanguage.text(metadata
                      ? '编辑存档信息'
                      : saveAs
                          ? '另存为'
                          : '保存')),
                  content: SizedBox(
                      width: 460,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                            key: const ValueKey('archive-name'),
                            controller: n,
                            decoration: InputDecoration(
                                labelText: AppLanguage.text('名称'))),
                        const SizedBox(height: 12),
                        TextField(
                            controller: m,
                            maxLines: 3,
                            decoration: InputDecoration(
                                labelText: AppLanguage.text('备注'))),
                        const SizedBox(height: 12),
                        TextField(
                            controller: t,
                            decoration: InputDecoration(
                                labelText: AppLanguage.text('标签，以逗号分隔'))),
                        if (allowUpdate) ...[
                          RadioListTile<bool>(
                              title: Text(AppLanguage.text('另存为新存档')),
                              value: false,
                              groupValue: update,
                              onChanged: (v) => set(() => update = false)),
                          RadioListTile<bool>(
                              title: Text(AppLanguage.text('更新原存档（保留旧版本）')),
                              value: true,
                              groupValue: update,
                              onChanged: (v) => set(() => update = true))
                        ]
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(AppLanguage.text('取消'))),
                    FilledButton(
                        key: const ValueKey('archive-confirm'),
                        onPressed: () {
                          if (n.text.trim().isEmpty) return;
                          Navigator.pop(ctx, (
                            n.text.trim(),
                            m.text,
                            t.text
                                .split(RegExp('[,，]'))
                                .map((s) => s.trim())
                                .where((s) => s.isNotEmpty)
                                .toList(),
                            update
                          ));
                        },
                        child: Text(AppLanguage.text(update
                            ? '更新存档'
                            : saveAs
                                ? '另存为'
                                : '保存')))
                  ])));
  Future.delayed(const Duration(seconds: 1), () {
    n.dispose();
    m.dispose();
    t.dispose();
  });
  return result;
}

Formation preset(String kind) {
  final base = Formation(mapId: kind == '泳池练习' ? 'pool' : 'day');
  final pieces = <Piece>[];
  void add(String type, int row, int col) => pieces.add(Piece(
      id: newId(),
      type: type,
      row: row,
      col: col,
      layer: ObjectSpec.byId(type).layer));
  for (var r = 0; r < base.map.rows; r++) {
    if (base.map.waterRows.contains(r)) {
      add('lily', r, 0);
      add('lily', r, 1);
    }
    add('sunflower', r, 0);
    add('pea', r, 1);
    add('wallnut', r, 6);
  }
  return base.copy(pieces: pieces);
}

// Each toolbox tab owns its offset even while the preset picker replaces it.
// Do not depend on a route's PageStorage being present in independent hosts.
class _ToolboxScrollController extends ScrollController {
  _ToolboxScrollController() : super(keepScrollOffset: false);
  double _retainedOffset = 0;

  @override
  double get initialScrollOffset => _retainedOffset;

  @override
  void detach(ScrollPosition position) {
    if (position.hasPixels) _retainedOffset = position.pixels;
    super.detach(position);
  }
}

class EditorWorkspace extends StatefulWidget {
  final EditorTabsController controller;
  final String? libraryPath;
  final Future<void> Function(ArchiveRecord) continueArchive;
  const EditorWorkspace(
      {super.key,
      required this.controller,
      this.libraryPath,
      required this.continueArchive});
  @override
  State<EditorWorkspace> createState() => _EditorWorkspaceState();
}

class _EditorWorkspaceState extends State<EditorWorkspace> {
  final editorKey = GlobalKey<_EditorPageState>();
  late final Future<bool> Function() flushGuard;
  @override
  void initState() {
    super.initState();
    widget.controller.beforeSwitch =
        () async => await editorKey.currentState?.prepareForTabSwitch() ?? true;
    flushGuard = widget.controller.flushAll;
    exitGuards.add(flushGuard);
  }

  @override
  void dispose() {
    exitGuards.remove(flushGuard);
    widget.controller.beforeSwitch = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.controller,
      builder: (_, __) => EditorPage(
          key: editorKey,
          session: widget.controller.active,
          libraryPath: widget.libraryPath,
          continueArchive: widget.continueArchive,
          tabBar: EditorTabStrip(controller: widget.controller),
          openSession: (session, newTab) =>
              widget.controller.open(session, newTab: newTab)));
}

class EditorPage extends StatefulWidget {
  final EditorSession session;
  final bool toolboxOnly;
  final String? libraryPath;
  final Widget? tabBar;
  final Future<void> Function(EditorSession, bool)? openSession;
  final Future<void> Function(ArchiveRecord) continueArchive;
  const EditorPage(
      {super.key,
      required this.session,
      required this.continueArchive,
      this.toolboxOnly = false,
      this.libraryPath,
      this.tabBar,
      this.openSession});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  EditorSession get s => widget.session;
  final transform = TransformationController();
  final canvasFocus = FocusNode(debugLabel: 'canvas-shortcuts');
  final Set<(int, int)> cells = {};
  final Set<int> batchRows = {}, batchColumns = {};
  bool batchSelectionMode = false, batchSelectorsVisible = true;
  String batchShovelFilter = '普通植物';
  String tool = '放置', category = '植物', search = '', selectedType = 'pea';
  String? selectedId;
  String shovelFilter = '智能';
  int classicTab = 2;
  final toolboxScrollControllers =
      List.generate(6, (_) => _ToolboxScrollController());
  String? pickingPresetGroup;
  int presetPickerRows = 5;
  String presetPickerLayoutGroup = '炮位';
  bool presetChangeMap = true;
  final inputFormation = TextEditingController(),
      outputFormation = TextEditingController();
  bool exportBackground = true;
  bool pokerWidth = true;
  String? pendingMapId;
  final keepPlantsOnMapChangeNotifier = ValueNotifier<bool>(false);
  bool get keepPlantsOnMapChange => keepPlantsOnMapChangeNotifier.value;
  set keepPlantsOnMapChange(bool value) =>
      keepPlantsOnMapChangeNotifier.value = value;
  int musicLevel = (OriginalAudio.musicVolume * 4).round(),
      soundLevel = (OriginalAudio.soundVolume * 4).round(), windowStyle = 1;
  final sunEditor = TextEditingController(text: '9990');
  final documentNameEditor = TextEditingController();
  final documentNameFocus = FocusNode(debugLabel: 'document-name');
  bool editingDocumentName = false;
  EditorSession? documentNameSession;
  Future<void>? pendingDocumentRename;
  double exportRatio = 1;
  Uint8List? generatedPng;
  String? generatedPngName;
  bool generatingPng = false;
  final Map<String, int> selectedPresets = {'阵型': 61, '炮位': 0, '无炮': 0};
  final Set<String> plantingEffects = {};
  bool plantingFlip = false, plantingVertical = false;
  String plantingAppearance = '默认';
  int plantingFrameRow = 0, plantingFrameCol = 0;
  int growMode = 1;
  bool autoLily = PlantingPreferences.current.autoLily;
  String autoPotMode = PlantingPreferences.current.potMode;
  Offset? plantingPointer;
  final plantingBoardKey = GlobalKey();
  final frameRandom = math.Random();
  static const growModeLabels = [
    '每次手动选择',
    '使用默认选择',
    '第一行内随机',
    '第一行第一个',
    '第二行内随机',
    '第二行第一个',
    '第三行随机',
    '第三行第一个'
  ];
  final List<Formation> mirrors = [];
  final List<double> mirrorScales = [];
  final List<bool> mirrorBackgrounds = [];
  final List<bool> mirrorPokerWidths = [];
  final List<Offset> mirrorPositions = [];
  Offset toolboxPosition = const Offset(812, 0);
  Offset windowPosition(Offset offset, Offset delta, double width) => Offset(
      (offset.dx + delta.dx).clamp(0, 1224 - width),
      (offset.dy + delta.dy).clamp(0, 570));
  List<String> get seedSlots => s.document.seedSlots;
  (int, int)? hover;
  Formation? snapshot, gestureBefore;
  final Set<(int, int)> visited = {};
  List<Piece> gesturePieces = [];
  bool gesture = false, fitted = false, savingArchive = false;
  final Stopwatch plantingClock = Stopwatch()..start();
  final Map<(int, int), int> plantingBirths = {};
  Timer? growthTimer;
  Timer? libraryRefreshTimer;
  String? growthMapId;
  List<GrowthEffect> get growthEffects => [
        for (final entry in plantingBirths.entries)
          if (plantingClock.elapsedMilliseconds - entry.value < 650)
            GrowthEffect(
                row: entry.key.$1,
                col: entry.key.$2,
                water: OriginalTerrain.at(
                        s.document.map, entry.key.$1, entry.key.$2) ==
                    2,
                frame:
                    ((plantingClock.elapsedMilliseconds - entry.value) ~/ 100)
                        .clamp(0, 5))
      ];

  void clearPlantingFeedback() {
    growthTimer?.cancel();
    growthTimer = null;
    plantingBirths.clear();
    growthMapId = null;
  }

  void plantingFeedback(Piece piece) {
    final terrain = OriginalTerrain.at(s.document.map, piece.row, piece.col);
    if (terrain == 0) return;
    final name = OriginalAssets.names[piece.type] ?? piece.type;
    if (OriginalAssets.kinds[name] == 'Prop' ||
        ['Lawnmower', 'Poolcleaner', 'Roofcleaner'].contains(name)) return;
    unawaited(OriginalAudio.playPlantingSound(water: terrain == 2));
    if (s.document.display['泥土'] != true || widget.toolboxOnly) return;
    growthMapId = s.document.mapId;
    plantingBirths[(piece.row, piece.col)] = plantingClock.elapsedMilliseconds;
    growthTimer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) {
        clearPlantingFeedback();
        return;
      }
      plantingBirths.removeWhere(
          (_, birth) => plantingClock.elapsedMilliseconds - birth >= 650);
      if (plantingBirths.isEmpty) clearPlantingFeedback();
      // Transient pixels never enter autosave, history or cross-engine state.
      super.setState(() {});
    });
  }

  int? editingPointer;
  double? scalePreview;
  late final Future<bool> Function() exitGuard;
  Size? viewport;
  Piece? get selected {
    for (final p in s.document.pieces) {
      if (p.id == selectedId) return p;
    }
    return null;
  }

  FormationFormat exportFormat = FormationFormat.toolkit;
  Formation? encodedOutputDocument;
  FormationFormat? encodedOutputFormat;
  String? outputEncodingError;

  void refreshFormationOutput() {
    if (identical(encodedOutputDocument, s.document) &&
        encodedOutputFormat == FormationFormat.toolkit) return;
    encodedOutputDocument = s.document;
    encodedOutputFormat = FormationFormat.toolkit;
    String text;
    try {
      final issues = FormationExchange.exportIssues(s.document);
      if (issues.isEmpty) {
        text = FormationExchange.encode(s.document);
        outputEncodingError = null;
      } else {
        text = '';
        outputEncodingError = '当前格式不支持：\n${issues.take(3).join('\n')}'
            '${issues.length > 3 ? '\n另有 ${issues.length - 3} 项。' : ''}';
      }
    } catch (e) {
      text = '';
      outputEncodingError = '当前阵型无法用此格式表示：$e';
    }
    if (outputFormation.text != text) outputFormation.text = text;
  }

  bool toolboxVisible = true;
  bool seedChooserOpen = false;
  String sidebarMode = 'toolbox';
  bool sharedSidebarProtocol = false;
  final fallbackLibraryKey = GlobalKey<_LibraryPageState>();
  bool nativeWindows = false,
      receivingWindowState = false,
      windowPublishQueued = false;
  String? remoteBaseFingerprint, windowInFlightFingerprint;
  int documentEpoch = 0;
  String? remoteDocumentToken;
  String? get documentToken =>
      widget.toolboxOnly ? remoteDocumentToken : '${s.id}:$documentEpoch';
  bool fileOperationBusy = false;
  bool formationNavigationInProgress = false;
  bool windowPublishInFlight = false, windowStateDirty = false;
  String? windowError;

  @override
  void setState(VoidCallback fn) {
    super.setState(() {
      fn();
      refreshFormationOutput();
    });
    if (tool == '铲除' || tool == '选择') {
      unawaited(
          OriginalAssets.ensureHitMasks(s.document.pieces.map((p) => p.type)));
    }
    if (!receivingWindowState) queueWindowState();
  }

  void queueWindowState() {
    if (!nativeWindows || !mounted) return;
    if (windowPublishInFlight) {
      windowStateDirty = true;
      return;
    }
    if (windowPublishQueued) return;
    windowPublishQueued = true;
    scheduleMicrotask(() async {
      windowPublishQueued = false;
      if (!mounted || !nativeWindows) return;
      windowPublishInFlight = true;
      windowStateDirty = false;
      final state = windowState();
      windowInFlightFingerprint = s.document.fingerprint;
      try {
        final accepted = await WindowBridge.publish(state);
        if (widget.toolboxOnly &&
            accepted == true &&
            state['documentToken'] == documentToken) {
          remoteBaseFingerprint = Formation.fromJson(Map<String, dynamic>.from(
                  jsonDecode(state['documentJson'] as String) as Map))
              .fingerprint;
        }
      } catch (e) {
        if (mounted) super.setState(() => windowError = '$e');
      } finally {
        windowPublishInFlight = false;
        windowInFlightFingerprint = null;
        if (windowStateDirty) queueWindowState();
      }
    });
  }

  Map<String, dynamic> windowState() => {
        'documentToken': documentToken,
        'document': s.document.toJson(),
        'documentJson': jsonEncode(s.document.toJson()),
        'baseFingerprint':
            widget.toolboxOnly ? remoteBaseFingerprint : s.document.fingerprint,
        'activeDraftId': s.readOnly ? null : s.id,
        'exportFormat': exportFormat.name,
        'name': s.name,
        'readOnly': s.readOnly,
        'seedChooserOpen': seedChooserOpen,
        'tool': tool,
        'category': category,
        'selectedType': selectedType,
        'selectedId': selectedId,
        'cells': cells.map((c) => [c.$1, c.$2]).toList(),
        'batchRows': batchRows.toList(),
        'batchColumns': batchColumns.toList(),
        'batchSelectionMode': batchSelectionMode,
        'batchSelectorsVisible': batchSelectorsVisible,
        'batchShovelFilter': batchShovelFilter,
        'effects': plantingEffects.toList(),
        'flip': plantingFlip,
        'vertical': plantingVertical,
        'frameRow': plantingFrameRow,
        'frameCol': plantingFrameCol,
        'growMode': growMode,
        'autoLily': autoLily,
        'autoPotMode': autoPotMode,
        'shovelFilter': shovelFilter,
        'windowStyle': windowStyle,
        'pendingMapId': pendingMapId,
        'keepPlantsOnMapChange': keepPlantsOnMapChange,
        'presetChangeMap': presetChangeMap,
        'musicLevel': musicLevel,
        'soundLevel': soundLevel,
        'mirrors': mirrors.map((m) => m.toJson()).toList(),
        'mirrorScales': mirrorScales,
        'mirrorBackgrounds': mirrorBackgrounds,
        'mirrorPokerWidths': mirrorPokerWidths,
        'mirrorPositions': mirrorPositions.map((p) => [p.dx, p.dy]).toList(),
      };

  Future<void> initializeWindows() async {
    try {
      final supported = await WindowBridge.initialize(
          toolbox: widget.toolboxOnly,
          dataPath: widget.toolboxOnly ? null : widget.libraryPath,
          activeDraftId: s.readOnly ? null : s.id,
          onEvent: (method, arguments) async {
            if (!mounted) return null;
            if (method == 'editorPointerMoved') {
              updateNativePlantingPointer(arguments);
              return null;
            }
            if (method == 'receiveState' || method == 'applyToolboxState') {
              return receiveWindowState(
                  Map<String, dynamic>.from(arguments as Map));
            }
            if (method == 'toolboxVisibilityChanged') {
              if (!sharedSidebarProtocol) {
                super.setState(() => toolboxVisible = arguments as bool);
              }
              return null;
            }
            if (method == 'sidebarStateChanged') {
              final state = Map<String, dynamic>.from(arguments as Map);
              super.setState(() {
                sharedSidebarProtocol = true;
                toolboxVisible = state['visible'] == true;
                sidebarMode =
                    state['mode'] == 'library' ? 'library' : 'toolbox';
              });
              return null;
            }
            if (method == 'libraryOpen') {
              return openLibraryItem(
                  Map<String, dynamic>.from(arguments as Map));
            }
            if (method == 'showHistory') {
              unawaited(showCurrentArchiveHistory());
              return true;
            }
            if (method == 'mainAction') {
              if (historyRestoring) {
                queueWindowState();
                return false;
              }
              if ((arguments as Map)['documentToken'] != documentToken) {
                queueWindowState();
                return false;
              }
              final action = arguments['action'];
              if (action == 'saveArchive') await saveArchive();
              if (action == 'saveArchiveAs') await saveArchive(saveAs: true);
              if (action is String && action.startsWith('transfer:')) {
                await transfer(action.substring(9));
              }
              if (action == 'navigateFormation') {
                final payload = arguments['payload'] as Map;
                if (payload['baseFingerprint'] != s.document.fingerprint) {
                  queueWindowState();
                  throw StateError('主画面已更新，请重新执行布局操作');
                }
                await navigateFormation(
                    Formation.fromJson(
                        Map<String, dynamic>.from(payload['document'] as Map)),
                    name: payload['name'] as String?,
                    filePath: payload['filePath'] as String?,
                    fileFormat: payload['fileFormat'] as String?,
                    lastFileBackup: payload['lastFileBackup'] as String?);
              }
              if (action == 'changeMap') {
                final payload = arguments['payload'] as Map;
                if (payload['baseFingerprint'] != s.document.fingerprint) {
                  queueWindowState();
                  throw StateError('主画面已更新，请重新选择地图');
                }
                final mapId = payload['mapId'];
                if (mapId is! String ||
                    !BoardMap.all.any((map) => map.id == mapId) ||
                    payload['keepPlants'] is! bool) {
                  throw const FormatException('无效地图选择');
                }
                await applyMapSelection(mapId, payload['keepPlants'] as bool);
              }
              if (action == 'usePreset') {
                final payload = arguments['payload'] as Map;
                await useFormationPreset(payload['group'] as String,
                    (payload['index'] as num).toInt(),
                    changeMap: payload['changeMap'] as bool?);
              }
              if (action == 'library') await leave();
              if (action == 'seedChooser:open') await toggleSeedChooser(true);
              if (action == 'seedChooser:close') await toggleSeedChooser(false);
              if (action == 'seedChooser:toggle') {
                await toggleSeedChooser(!seedChooserOpen);
              }
              if (action == 'undo') await undoEditing();
              if (action == 'clearFormation') await clearFormation();
              if (action == 'formatForOutput') await formatForOutput();
              if (action == 'redo') await redoEditing();
            }
            return null;
          });
      if (!mounted) return;
      super.setState(() => nativeWindows = supported);
      if (supported && !widget.toolboxOnly) {
        await WindowBridge.publish(windowState());
        await WindowBridge.setVisible(true);
      }
    } catch (e) {
      if (mounted) super.setState(() => windowError = '$e');
    }
  }

  bool receiveWindowState(Map<String, dynamic> value) {
    final incomingToken = value['documentToken'] as String?;
    if (!widget.toolboxOnly && incomingToken != documentToken) {
      queueWindowState();
      return false;
    }
    final changedDocument =
        widget.toolboxOnly && incomingToken != remoteDocumentToken;
    if (changedDocument) {
      generatedPng = null;
      generatedPngName = null;
      remoteDocumentToken = incomingToken;
      remoteBaseFingerprint = null;
      windowStateDirty = false;
    }
    final document = Formation.fromJson(value['documentJson'] is String
        ? Map<String, dynamic>.from(
            jsonDecode(value['documentJson'] as String) as Map)
        : Map<String, dynamic>.from(value['document'] as Map));
    if (!widget.toolboxOnly &&
        historyRestoring &&
        document.fingerprint != s.document.fingerprint) {
      queueWindowState();
      return false;
    }
    if (widget.toolboxOnly &&
        !changedDocument &&
        windowPublishInFlight &&
        windowStateDirty &&
        document.fingerprint == windowInFlightFingerprint) {
      // This acknowledges our previous edit; preserve the next local edit until
      // it is sent against the newly acknowledged document.
      remoteBaseFingerprint = document.fingerprint;
      return true;
    }
    if (!widget.toolboxOnly &&
        (s.readOnly || s.deleted) &&
        document.fingerprint != s.document.fingerprint) {
      queueWindowState();
      return false;
    }
    if (!widget.toolboxOnly &&
        document.fingerprint != s.document.fingerprint &&
        value['baseFingerprint'] != s.document.fingerprint) {
      super.setState(() => windowError = '主画面已更新，请重新执行工具箱操作');
      queueWindowState();
      return false;
    }
    final changedPlantingPreferences =
        autoLily != (value['autoLily'] as bool? ?? true) ||
            autoPotMode != (value['autoPotMode'] as String? ?? 'roof');
    receivingWindowState = true;
    try {
      if (widget.toolboxOnly) {
        s.document = document;
        s.name = value['name'] as String;
        s.readOnly = value['readOnly'] as bool;
        remoteBaseFingerprint = document.fingerprint;
      } else if (document.fingerprint != s.document.fingerprint) {
        s.execute('工具箱操作', document);
      }
      super.setState(() {
        if (widget.toolboxOnly) {
          seedChooserOpen = value['seedChooserOpen'] == true;
        }
        tool = value['tool'] == '批选' ? '选择' : value['tool'] as String;
        batchSelectionMode = value['batchSelectionMode'] == true;
        batchSelectorsVisible = value['batchSelectorsVisible'] != false;
        batchRows..clear()..addAll((value['batchRows'] as List? ?? []).cast<int>());
        batchColumns..clear()..addAll((value['batchColumns'] as List? ?? []).cast<int>());
        batchShovelFilter = value['batchShovelFilter'] as String? ?? '普通植物';
        category = value['category'] as String;
        selectedType = value['selectedType'] as String;
        selectedId = value['selectedId'] as String?;
        cells
          ..clear()
          ..addAll((value['cells'] as List)
              .map((c) => ((c[0] as num).toInt(), (c[1] as num).toInt())));
        plantingEffects
          ..clear()
          ..addAll((value['effects'] as List).cast<String>());
        plantingFlip = value['flip'] as bool;
        plantingVertical = value['vertical'] as bool;
        plantingFrameRow = (value['frameRow'] as num).toInt();
        plantingFrameCol = (value['frameCol'] as num).toInt();
        growMode = (value['growMode'] as num).toInt();
        autoLily = value['autoLily'] as bool? ?? true;
        autoPotMode = PlantingSupport.potModes.contains(value['autoPotMode'])
            ? value['autoPotMode'] as String
            : 'roof';
        shovelFilter = value['shovelFilter'] == '最上层'
            ? '智能'
            : value['shovelFilter'] as String;
        windowStyle = (value['windowStyle'] as num).toInt();
        pendingMapId = value['pendingMapId'] as String?;
        keepPlantsOnMapChange = value['keepPlantsOnMapChange'] == true;
        presetChangeMap = value['presetChangeMap'] != false;
        exportFormat = FormationFormat.values.firstWhere(
            (f) => f.name == value['exportFormat'],
            orElse: () => FormationFormat.toolkit);
        musicLevel = (value['musicLevel'] as num).toInt();
        soundLevel = (value['soundLevel'] as num).toInt();
        mirrors
          ..clear()
          ..addAll((value['mirrors'] as List).map(
              (m) => Formation.fromJson(Map<String, dynamic>.from(m as Map))));
        mirrorScales
          ..clear()
          ..addAll((value['mirrorScales'] as List)
              .map((n) => (n as num).toDouble()));
        mirrorBackgrounds
          ..clear()
          ..addAll((value['mirrorBackgrounds'] as List).cast<bool>());
        mirrorPokerWidths
          ..clear()
          ..addAll((value['mirrorPokerWidths'] as List).cast<bool>());
        mirrorPositions
          ..clear()
          ..addAll((value['mirrorPositions'] as List).map((p) =>
              Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())));
      });
    } finally {
      receivingWindowState = false;
    }
    if (changedPlantingPreferences && !widget.toolboxOnly) {
      persistPlantingPreferences();
    }
    refreshFormationOutput();
    if (OriginalAudio.musicVolume != musicLevel / 4) {
      unawaited(OriginalAudio.setMusicVolume(musicLevel / 4));
    }
    if (OriginalAudio.soundVolume != soundLevel / 4) {
      unawaited(OriginalAudio.setSoundVolume(soundLevel / 4));
    }
    if (!widget.toolboxOnly) queueWindowState();
    return true;
  }

  void selectToolboxTab(int index) {
    if (index == 0) {
      unawaited(toggleSeedChooserFromTab());
      return;
    }
    if (index == classicTab && pickingPresetGroup == null) return;
    // Tab navigation is local UI state; it must not publish an editor command.
    super.setState(() {
      classicTab = index;
      pickingPresetGroup = null;
    });
  }

  Widget classicToolboxContents() => ScrollConfiguration(
      behavior: ScrollConfiguration.of(context)
          .copyWith(physics: const ClampingScrollPhysics(), overscroll: false),
      child: Theme(
          data: Theme.of(context).copyWith(
              colorScheme:
                  ColorScheme.fromSeed(seedColor: const Color(0xff426f45)),
              dividerColor: const Color(0xffdce5d3)),
          child: DecoratedBox(
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xfff7f8ee), Color(0xffedf3e5)])),
              child: Column(children: [
                SizedBox(
                    height: 34,
                    child: Row(children: [
                      for (var i = 1; i < 6; i++)
                        Expanded(
                            child: InkWell(
                                key: ValueKey('toolbox-tab-$i'),
                                onTap: () => selectToolboxTab(i),
                                child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                        color: (i == 0 ? seedChooserOpen : classicTab == i)
                                            ? const Color(0xffe1ecd6)
                                            : const Color(0xfff4f5e9),
                                        border: Border(
                                            bottom: BorderSide(
                                                color: (i == 0
                                                        ? seedChooserOpen
                                                        : classicTab == i)
                                                    ? const Color(0xff628655)
                                                    : const Color(0xffdce5d3),
                                                width: (i == 0
                                                        ? seedChooserOpen
                                                        : classicTab == i)
                                                    ? 3
                                                    : 1))),
                                    child: Text(AppLanguage.text(['卡槽选卡', '懒人布局', '图鉴选卡', '镜像窗口', '载入导出', '选项设置'][i]),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: const Color(0xff304b32),
                                            fontWeight: (i == 0
                                                    ? seedChooserOpen
                                                    : classicTab == i)
                                                ? FontWeight.w600
                                                : FontWeight.normal)))))
                    ])),
                Expanded(
                    child: pickingPresetGroup != null
                        ? presetPickerContents()
                        : SingleChildScrollView(
                            key: PageStorageKey('toolbox-scroll-$classicTab'),
                            controller: toolboxScrollControllers[classicTab],
                            primary: false,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            child: classicContents())),
              ]))));

  Widget sidebarModeButton(String mode) {
    final active = toolboxVisible && sidebarMode == mode;
    const green = Color(0xff315e45);
    return Semantics(
        key: ValueKey('main-sidebar-selection-$mode'),
        selected: active,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            child: SizedBox(
                height: 26,
                child: OutlinedButton.icon(
                    key: ValueKey('main-sidebar-$mode'),
                    onPressed: () => toggleSidebarMode(mode),
                    style: OutlinedButton.styleFrom(
                        foregroundColor:
                            active ? green : const Color(0xff53626b),
                        backgroundColor: active
                            ? const Color(0xffdceade)
                            : const Color(0xffedf1f3),
                        side: BorderSide(
                            color: active
                                ? const Color(0xffa6c3ad)
                                : const Color(0xffc7d1d6)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                active ? FontWeight.w600 : FontWeight.w400)),
                    icon: Icon(
                        mode == 'toolbox' ? Icons.tune : Icons.folder_outlined,
                        size: 14),
                    label: Text(AppLanguage.text(
                        mode == 'toolbox' ? '工具箱' : '存档库'))))));
  }

  Widget fallbackSidebar() => ClassicWindow(
      key: const ValueKey('fallback-sidebar-window'),
      title: AppLanguage.text(sidebarMode == 'library' ? '存档库' : '布阵器工具箱'),
      width: 410,
      height: 635,
      dragKey: const ValueKey('toolbox-drag'),
      onDrag: (delta) => setState(
          () => toolboxPosition = windowPosition(toolboxPosition, delta, 410)),
      onClose: toggleSidebar,
      child: IndexedStack(
          index: sidebarMode == 'library' ? 1 : 0,
          sizing: StackFit.expand,
          children: [
            Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                    width: 410,
                    child: ExcludeFocus(
                        excluding: !toolboxVisible || sidebarMode != 'toolbox',
                        child: classicToolboxContents()))),
            OverflowBox(
                minWidth: 410,
                maxWidth: 410,
                alignment: Alignment.topLeft,
                child: ExcludeFocus(
                    excluding: !toolboxVisible || sidebarMode != 'library',
                    child: LibraryPage(
                        key: fallbackLibraryKey,
                        showTitle: false,
                        repository: s.repository,
                        activeDraftId: s.readOnly ? null : s.id,
                        onDocumentAction: openLibraryItem,
                        onOpenSession: (next) =>
                            openFallbackSession(next, false),
                        onOpenTab: widget.openSession == null
                            ? null
                            : (next) => openFallbackSession(next, true))))
          ]));

  Widget documentHeading({bool showWindowError = false}) {
    final canRename =
        !s.readOnly && !savingArchive && pendingDocumentRename == null;
    final nameSize = TextPainter(
        text: TextSpan(text: s.name, style: const TextStyle(fontSize: 12)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context))
      ..layout();
    final nameWidth = (nameSize.width + 20).clamp(80.0, 220.0);
    nameSize.dispose();
    return TextFieldTapRegion(
        child: Row(children: [
      Flexible(
          child: editingDocumentName
              ? CallbackShortcuts(
                  bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape): () =>
                          unawaited(finishDocumentRename(cancel: true)),
                    },
                  child: SizedBox(
                      width: nameWidth,
                      height: 22,
                      child: DefaultTextEditingShortcuts(
                          child: TextField(
                              key: const ValueKey('document-name-input'),
                              controller: documentNameEditor,
                              focusNode: documentNameFocus,
                              style: const TextStyle(fontSize: 12),
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 3),
                                  border: OutlineInputBorder()),
                              onSubmitted: (_) => unawaited(finishDocumentRename()),
                              onTapOutside: (_) =>
                                  unawaited(finishDocumentRename())))))
              : Tooltip(
                  message: showWindowError && windowError != null
                      ? windowError!
                      : canRename
                          ? '点击重命名存档'
                          : '',
                  child: InkWell(
                      key: const ValueKey('document-title'),
                      onTap: canRename ? renameDocument : null,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                          width: nameWidth,
                          height: 22,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                              color: s.readOnly
                                  ? const Color(0xffe5e9e4)
                                  : const Color(0xfff8fbf5),
                              border:
                                  Border.all(color: const Color(0xffa6b4a3)),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(s.name,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis))))),
      IconButton(
          key: const ValueKey('document-rename'),
          tooltip: AppLanguage.text(editingDocumentName ? '保存名称' : '重命名存档'),
          icon: Icon(editingDocumentName ? Icons.check : Icons.edit_outlined,
              size: 14),
          constraints: const BoxConstraints.tightFor(width: 24, height: 26),
          padding: EdgeInsets.zero,
          onPressed: editingDocumentName
              ? () => unawaited(finishDocumentRename())
              : canRename
                  ? renameDocument
                  : null),
    ]));
  }

  Widget seedChooserButton() => classicButton('卡槽选卡',
      () => unawaited(toggleSeedChooserFromTab()),
      active: seedChooserOpen, key: const ValueKey('board-picker-toggle'));

  bool renameDialogOpen = false;
  bool historyDialogOpen = false;
  bool historyRestoring = false;

  Widget workspaceMenuLabel(IconData icon, String label) => Row(children: [
    Icon(icon, size: 18),
    const SizedBox(width: 10),
    Text(AppLanguage.text(label)),
  ]);

  Widget workspaceMoreMenu() => PopupMenuButton<String>(
      key: const ValueKey('workspace-more'),
      tooltip: AppLanguage.text('更多'),
      padding: EdgeInsets.zero,
      iconSize: 18,
      enabled: !savingArchive && !renameDialogOpen && !historyDialogOpen,
      icon: const Icon(Icons.more_vert),
      onSelected: (action) {
        if (action == 'undo') {
          undoEditing();
        } else if (action == 'redo') {
          redoEditing();
        } else if (action == 'history') {
          unawaited(showCurrentArchiveHistory());
        } else if (action == 'rename') {
          unawaited(renameFromMenu());
        } else {
          unawaited(saveArchive(saveAs: action == 'saveAs'));
        }
      },
      itemBuilder: (_) => [
            PopupMenuItem(
                value: 'undo',
                key: const ValueKey('workspace-undo'),
                enabled: canUndoEditing,
                child: workspaceMenuLabel(Icons.undo, '撤销')),
            PopupMenuItem(
                value: 'redo',
                key: const ValueKey('workspace-redo'),
                enabled: canRedoEditing,
                child: workspaceMenuLabel(Icons.redo, '恢复')),
            const PopupMenuDivider(),
            PopupMenuItem(
                value: 'save',
                key: const ValueKey('archive-save'),
                enabled: !s.readOnly,
                child: workspaceMenuLabel(Icons.save_outlined, '保存')),
            PopupMenuItem(
                value: 'saveAs',
                key: const ValueKey('archive-save-as'),
                child: workspaceMenuLabel(Icons.save_as_outlined, '另存为')),
            PopupMenuItem(
                value: 'rename',
                key: const ValueKey('workspace-rename'),
                enabled: !s.readOnly && pendingDocumentRename == null,
                child: workspaceMenuLabel(Icons.drive_file_rename_outline, '重命名')),
            PopupMenuItem(
                value: 'history',
                key: const ValueKey('workspace-history'),
                enabled: s.sourceArchiveId != null,
                child: workspaceMenuLabel(Icons.history, '历史版本')),
          ]);

  Widget workspaceTabBar() => Material(
      color: const Color(0xffe5e9e0),
      child: SizedBox(
          height: 28,
          child: Row(children: [
            Expanded(child: widget.tabBar!),
            SizedBox(width: 32, height: 28, child: workspaceMoreMenu())
          ])));

  Widget nativeMainPage() => Scaffold(
      backgroundColor: const Color(0xff748899),
      body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
              width: 810,
              height: 667 + (widget.tabBar == null ? 0 : 28),
              child: Column(children: [
                if (widget.tabBar != null) workspaceTabBar(),
                Container(
                    height: 32,
                    color: const Color(0xffd9e1e7),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(children: [
                      Expanded(child: documentHeading(showWindowError: true)),
                      historyButton(redo: false),
                      historyButton(redo: true),
                      seedChooserButton(),
                      sidebarModeButton('toolbox'),
                      sidebarModeButton('library'),
                      if (widget.tabBar == null) workspaceMoreMenu(),
                    ])),
                SizedBox(
                    width: 810,
                    height: 635,
                    child: Stack(clipBehavior: Clip.hardEdge, children: [
                      Positioned(
                          left: 0,
                          top: 0,
                          width: 810,
                          height: 635,
                          child: RawImage(
                              image: OriginalAssets.image(
                                  'image/window$windowStyle.png'),
                              key: ValueKey(
                                  'original-window-background-$windowStyle'),
                              fit: BoxFit.none,
                              alignment: Alignment.topLeft)),
                      Positioned(
                          left: 3,
                          top: 27,
                          width: 800,
                          height: 600,
                          child: board()),
                      for (var i = 0; i < mirrors.length; i++) mirrorWindow(i),
                      if (seedChooserOpen) seedChooserOverlay(),
                    ])),
              ]))));

  @override
  void initState() {
    super.initState();
    sunEditor.text = '${s.document.sunValue}';
    s.thumbnailGenerator ??=
        (document) async => base64Encode(await exportPng(document));
    documentNameFocus.addListener(() {
      if (!documentNameFocus.hasFocus && editingDocumentName) {
        unawaited(finishDocumentRename());
      }
    });
    refreshFormationOutput();
    unawaited(initializeWindows());
    if (!widget.toolboxOnly) {
      unawaited(OriginalAudio.setMusicVolume(musicLevel / 4));
      unawaited(OriginalAudio.setSoundVolume(soundLevel / 4));
    }
    s.addListener(update);
    OriginalAssets.revision.addListener(update);
    unawaited(OriginalAssets.ensureLoaded());
    unawaited(
        OriginalAssets.ensureHitMasks(s.document.pieces.map((p) => p.type)));
    exitGuard = () async {
      await finishDocumentRename();
      finishGesture();
      await s.flush();
      return s.error == null;
    };
    exitGuards.add(exitGuard);
    WidgetsBinding.instance.addObserver(this);
  }

  Future<bool> prepareForTabSwitch() async {
    if (savingArchive ||
        (fileOperationBusy && !formationNavigationInProgress) ||
        ModalRoute.of(context)?.isCurrent != true) return false;
    await finishDocumentRename();
    finishGesture();
    final current = s;
    await current.flush();
    return current.error == null;
  }

  @override
  void didUpdateWidget(covariant EditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.session, widget.session)) return;
    editingDocumentName = false;
    documentNameSession = null;
    documentNameFocus.unfocus();
    oldWidget.session.removeListener(update);
    s.addListener(update);
    s.thumbnailGenerator ??=
        (document) async => base64Encode(await exportPng(document));
    documentEpoch++;
    seedChooserOpen = false;
    clearPlantingFeedback();
    gesture = false;
    gestureBefore = null;
    gesturePieces = [];
    visited.clear();
    editingPointer = null;
    selectedId = null;
    clearBatchSelection();
    hover = null;
    snapshot = null;
    mirrors.clear();
    mirrorScales.clear();
    mirrorBackgrounds.clear();
    mirrorPokerWidths.clear();
    mirrorPositions.clear();
    pendingMapId = null;
    generatedPng = null;
    generatedPngName = null;
    keepPlantsOnMapChange = false;
    windowError = null;
    sunEditor.text = '${s.document.sunValue}';
    transform.value = Matrix4.identity();
    encodedOutputDocument = null;
    refreshFormationOutput();
    fit();
    queueWindowState();
  }

  void update() {
    if (growthMapId != null && growthMapId != s.document.mapId) {
      clearPlantingFeedback();
    }
    if (mounted) setState(() {});
    if (!widget.toolboxOnly &&
        toolboxVisible &&
        sidebarMode == 'library' &&
        s.error == null) {
      libraryRefreshTimer?.cancel();
      libraryRefreshTimer = Timer(const Duration(milliseconds: 180), () async {
        await s.flush();
        if (mounted && s.error == null) await refreshLibraryView();
      });
    }
  }

  @override
  void dispose() {
    editingDocumentName = false;
    documentNameSession = null;
    documentNameFocus.dispose();
    documentNameEditor.dispose();
    keepPlantsOnMapChangeNotifier.dispose();
    libraryRefreshTimer?.cancel();
    clearPlantingFeedback();
    if (!widget.toolboxOnly && nativeWindows) {
      unawaited(WindowBridge.deactivate());
    }
    WindowBridge.dispose();
    WidgetsBinding.instance.removeObserver(this);
    exitGuards.remove(exitGuard);
    s.removeListener(update);
    OriginalAssets.revision.removeListener(update);
    sunEditor.dispose();
    canvasFocus.dispose();
    inputFormation.dispose();
    outputFormation.dispose();
    for (final controller in toolboxScrollControllers) {
      controller.dispose();
    }
    transform.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(finishDocumentRename());
      finishGesture();
      unawaited(s.flush());
    }
  }

  void fit() {
    if (viewport == null) return;
    final size = BoardGeometry(s.document).size;
    final z = (viewport!.width / size.width < viewport!.height / size.height
            ? viewport!.width / size.width
            : viewport!.height / size.height) *
        1.0;
    transform.value = Matrix4.identity()
      ..translate((viewport!.width - size.width * z) / 2,
          (viewport!.height - size.height * z) / 2)
      ..scale(z);
  }

  void zoom(double factor) {
    transform.value = transform.value.clone()..scale(factor);
    setState(() {});
  }

  bool switchingLibraryItem = false;

  Future<void> toggleSeedChooserFromTab() async {
    try {
      if (widget.toolboxOnly) {
        await WindowBridge.mainAction('seedChooser:toggle');
      } else {
        await toggleSeedChooser(!seedChooserOpen);
      }
    } catch (error) {
      if (mounted) message(context, '无法切换选卡面板：$error');
    }
  }

  Future<void> toggleSeedChooser(bool open) async {
    if (widget.toolboxOnly) {
      await WindowBridge.mainAction('seedChooser:${open ? 'open' : 'close'}');
      return;
    }
    finishGesture();
    if (open) cancelPlanting();
    if (mounted) setState(() => seedChooserOpen = open);
  }

  Widget seedChooserOverlay() => Positioned(
      left: 13,
      top: 38,
      width: OriginalSeedChooser.width,
      height: OriginalSeedChooser.height,
      child: OriginalSeedChooser(
          document: s.document,
          readOnly: s.readOnly,
          onChanged: (document) => s.execute('卡槽选卡', document),
          onClose: () => toggleSeedChooser(false)));

  void removeSeedSlot(int index) {
    if (s.readOnly) return;
    final removedType = seedSlots[index];
    final cards = [...seedSlots]..removeAt(index);
    s.execute(
        '移除卡槽',
        s.document.copy(seedSlots: cards, imitaterSeedSlots: {
          for (final i in s.document.imitaterSeedSlots)
            if (i != index) i > index ? i - 1 : i,
        }));
    if (selectedType == removedType) cancelPlanting();
  }

  Future<void> sidebarActions = Future.value();

  Future<void> toggleSidebar() => toggleSidebarMode(sidebarMode);

  Future<void> toggleSidebarMode(String mode) {
    final operation = sidebarActions.then((_) async {
      if (!mounted) return;
      final hide = toolboxVisible && sidebarMode == mode;
      try {
        if (nativeWindows) {
          if (hide) {
            await WindowBridge.setVisible(false);
          } else {
            await WindowBridge.selectMode(mode,
                dataPath: widget.libraryPath,
                activeDraftId: s.readOnly ? null : s.id);
          }
        } else if (hide) {
          setState(() => toolboxVisible = false);
          canvasFocus.requestFocus();
        } else {
          await selectFallbackSidebarMode(mode);
        }
      } catch (e) {
        if (mounted) {
          final reason = e is PlatformException ? e.message ?? '请稍后重试' : '$e';
          message(context, '无法切换面板：$reason');
        }
      }
    });
    sidebarActions = operation;
    return operation;
  }

  Future<void> selectFallbackSidebarMode(String mode) async {
    if (mode == sidebarMode && toolboxVisible) return;
    finishGesture();
    await s.flush();
    if (!mounted) return;
    if (s.error != null) {
      message(context, '存档尚未保存：${s.error}');
      return;
    }
    setState(() {
      sidebarMode = mode;
      toolboxVisible = true;
    });
    if (mode == 'toolbox') canvasFocus.requestFocus();
    if (mode == 'library') await fallbackLibraryKey.currentState?.refresh();
  }

  Future<void> openFallbackSession(EditorSession session, bool newTab) async {
    try {
      if (widget.openSession != null) {
        await widget.openSession!(session, newTab);
        if (mounted) setState(() => sidebarMode = 'toolbox');
      } else {
        Navigator.pop(context, session);
      }
    } catch (e) {
      session.dispose();
      if (mounted) message(context, '打开失败：$e');
    }
  }

  Future<bool> openLibraryItem(Map<String, dynamic> request) async {
    if (switchingLibraryItem) throw StateError('正在切换阵型，请稍后重试');
    if (ModalRoute.of(context)?.isCurrent != true) {
      throw StateError('请先完成或关闭主窗口中的对话框');
    }
    switchingLibraryItem = true;
    try {
      finishGesture();
      await s.flush();
      if (!mounted) return false;
      if (s.error != null) throw StateError('当前存档保存失败：${s.error}');
      if (request['kind'] == 'archive-dedup') {
        final controller = context.findAncestorWidgetOfExactType<EditorWorkspace>()?.controller;
        Set<String> protected() => {
          for (final session in controller?.allSessions ?? <EditorSession>[s])
            if (session.sourceArchiveId != null) session.sourceArchiveId!,
        };
        final result = await showArchiveDedupDialog(context, s.repository,
            protectedArchiveIds: protected,
            flushEditors: () async {
              if (controller != null) {
                if (!await controller.flushAll()) {
                  throw StateError(controller.error ?? '无法保存打开的存档');
                }
              } else {
                await s.flush();
                if (s.error != null) throw StateError(s.error!);
              }
            });
        await refreshLibraryView();
        if (result != null && mounted) {
          message(context, '已清理 ${result.removedCount} 个重复存档，历史版本已保留。');
        }
        return true;
      }
      EditorSession next;
      final id = request['id'];
      if (request['kind'] == 'archive-rename' ||
          request['kind'] == 'archive-rollback' ||
          request['kind'] == 'archive-delete') {
        final controller = context
            .findAncestorWidgetOfExactType<EditorWorkspace>()
            ?.controller;
        if (controller != null && !await controller.flushAll()) {
          throw StateError(controller.error ?? '无法保存其他标签页');
        }
        final source = (await s.repository.listArchives())
            .where((a) => a.id == id)
            .firstOrNull;
        if (source == null) throw StateError('存档已不存在');
        if (request['kind'] == 'archive-delete') {
          if (controller == null && s.sourceArchiveId == source.id) {
            throw StateError('请先关闭此存档的编辑窗口再删除');
          }
          if (controller != null) {
            await controller.removeArchive(source.id);
          }
          await s.repository.deleteArchive(source.id);
          await refreshLibraryView();
          return true;
        }
        if (request['kind'] == 'archive-rename') {
          final name = request['name'] as String;
          final updated = await s.repository.saveArchive(
              id: newId(),
              updateId: source.id,
              name: name,
              document: source.document,
              note: request['note'] as String? ?? source.note,
              tags: request['tags'] is List
                  ? (request['tags'] as List).cast<String>()
                  : source.tags);
          for (final session in controller?.allSessions ?? <EditorSession>[s]) {
            if (!session.readOnly &&
                session.sourceArchiveId == source.id &&
                session.document.fingerprint ==
                    Formation.fromJson(updated.document).fingerprint) {
              await session.markArchived(
                  updated.id, session.document.fingerprint,
                  name: updated.name);
            }
          }
          await refreshLibraryView();
          return true;
        }
        final version = (await s.repository.listVersions(source.id))
            .where((v) => v.id == request['versionId'])
            .firstOrNull;
        if (version == null) throw StateError('历史版本已不存在');
        Formation.fromJson(version.document);
        final name = version.name == source.name
            ? source.name
            : await s.repository.uniqueDocumentName(version.name);
        final restored = await s.repository.saveArchive(
            id: newId(),
            updateId: source.id,
            name: name,
            document: version.document,
            note: version.note,
            tags: version.tags);
        next = EditorSession(s.repository,
            document: Formation.fromJson(restored.document),
            name: restored.name,
            sourceArchiveId: restored.id,
            savedFingerprint:
                Formation.fromJson(restored.document).fingerprint);
        await next.markArchived(restored.id, next.document.fingerprint,
            name: restored.name);
      } else if (request['kind'] == 'new') {
        final document = Formation.fromJson(Map<String, dynamic>.from(
            jsonDecode(request['documentJson'] as String) as Map));
        next = EditorSession(s.repository,
            document: document, name: request['name'] as String? ?? '未命名阵型',
            deferInitialSave: true);
      } else if (request['kind'] == 'draft') {
        final matches =
            (await s.repository.listDrafts()).where((d) => d.id == id);
        if (matches.isEmpty) throw StateError('旧工作记录已不存在，请刷新存档库');
        if (id == s.id && !s.readOnly) return true;
        next = EditorSession.fromDraft(s.repository, matches.first);
      } else if (request['kind'] == 'preset-preview') {
        final matches = LibraryPresets.all.where((p) => p.id == id);
        if (matches.isEmpty) throw StateError('预制名阵已不存在');
        final p = matches.first;
        next = EditorSession(s.repository,
            document: p.document,
            id: 'preview-${p.id}',
            name: p.name,
            readOnly: true);
      } else if (request['kind'] == 'archive' ||
          request['kind'] == 'archive-edit') {
        final matches =
            (await s.repository.listArchives()).where((a) => a.id == id);
        if (matches.isEmpty) throw StateError('存档已不存在，请刷新存档库');
        final a = matches.first;
        next = EditorSession(s.repository,
            document: Formation.fromJson(a.document),
            id: a.id,
            name: a.name,
            readOnly: request['kind'] == 'archive',
            sourceArchiveId: a.id,
            savedFingerprint: request['kind'] == 'archive-edit'
                ? Formation.fromJson(a.document).fingerprint
                : null);
        if (!next.readOnly) {
          await next.markArchived(a.id, next.document.fingerprint,
              name: a.name);
        }
      } else {
        throw const FormatException('未知存档类型');
      }
      if (!mounted) {
        next.dispose();
        return false;
      }
      if (!next.readOnly && request['filePath'] is String) {
        next.filePath = request['filePath'] as String;
        next.fileFormat = request['fileFormat'] as String?;
      }
      if (widget.openSession != null) {
        try {
          final controller = context
              .findAncestorWidgetOfExactType<EditorWorkspace>()
              ?.controller;
          if (request['kind'] == 'archive-rollback' && controller != null) {
            await controller.open(next, forceNavigation: true);
          } else {
            await widget.openSession!(next, request['newTab'] == true);
          }
        } catch (_) {
          next.dispose();
          rethrow;
        }
      } else {
        Navigator.pop(context, next);
      }
      return true;
    } finally {
      switchingLibraryItem = false;
    }
  }

  Future<void> leave() async {
    if (widget.toolboxOnly) {
      await WindowBridge.mainAction('library');
      return;
    }
    finishGesture();
    await s.flush();
    if (!mounted) return;
    if (s.error != null) {
      message(context, '存档尚未保存：${s.error}');
      return;
    }
    if (nativeWindows && widget.libraryPath != null) {
      try {
        await WindowBridge.channel.invokeMethod('showLibrary', {
          'dataPath': widget.libraryPath,
          'activeDraftId': s.readOnly ? null : s.id
        });
      } catch (e) {
        if (mounted) message(context, '无法打开存档库：$e');
      }
      return;
    }
    await selectFallbackSidebarMode('library');
  }

  EditorTabsController? get editingTabs =>
      context.findAncestorWidgetOfExactType<EditorWorkspace>()?.controller;
  bool get canUndoEditing => editingTabs == null
      ? s.canUndo
      : !editingTabs!.busy && editingTabs!.canUndo;
  bool get canRedoEditing => editingTabs == null
      ? s.canRedo
      : !editingTabs!.busy && editingTabs!.canRedo;

  Future<void> undoEditing() async {
    finishGesture();
    try {
      if (editingTabs == null) {
        s.undo();
      } else {
        await editingTabs!.undo();
      }
    } catch (e) {
      if (mounted) message(context, '无法撤销：$e');
    }
  }

  Future<void> redoEditing() async {
    finishGesture();
    try {
      if (editingTabs == null) {
        s.redo();
      } else {
        await editingTabs!.redo();
      }
    } catch (e) {
      if (mounted) message(context, '无法恢复刚撤销的操作：$e');
    }
  }

  Future<void> formatForOutput() async {
    if (widget.toolboxOnly) {
      await WindowBridge.mainAction('formatForOutput');
      return;
    }
    finishGesture();
    try {
      final formatted = FormationFormatter.format(s.document);
      if (s.readOnly) {
        await navigateFormation(formatted, name: s.name);
      } else {
        s.execute('一键格式化', formatted);
      }
      if (mounted) {
        setState(() {
          clearBatchSelection();
          selectedId = null;
        });
      }
    } catch (e) {
      if (mounted) message(context, '无法格式化：$e');
    }
  }

  Future<void> clearFormation() async {
    if (widget.toolboxOnly) {
      await WindowBridge.mainAction('clearFormation');
      return;
    }
    if (s.readOnly) return;
    finishGesture();
    s.execute('清空阵型', s.document.copy(pieces: []));
    setState(() {
      selectedId = null;
      clearBatchSelection();
      clearPlantingFeedback();
    });
  }

  void removeSelected() {
    if (selected == null || s.readOnly) return;
    final removed = selected!;
    s.execute(
        '删除对象',
        s.document.copy(
            pieces: s.document.pieces
                .where((p) =>
                    p.id != removed.id &&
                    !(removed.type == 'pumpkin' &&
                        p.type == 'ladder' &&
                        p.row == removed.row &&
                        p.col == removed.col))
                .toList()));
    setState(() => selectedId = null);
  }

  void changePiece(Piece p) {
    s.execute(
        '修改属性',
        s.document.copy(
            pieces: s.document.pieces
                .map((old) => old.id == p.id ? p : old)
                .toList()));
  }

  List<Piece> at((int, int) cell) {
    final indexed = s.document.pieces
        .asMap()
        .entries
        .where((e) =>
            e.value.row == cell.$1 &&
            cell.$2 >= e.value.col &&
            cell.$2 < e.value.col + e.value.spec.width)
        .toList()
      ..sort((a, b) {
        final layer = b.value.layer.compareTo(a.value.layer);
        return layer == 0 ? b.key.compareTo(a.key) : layer;
      });
    return indexed.map((e) => e.value).toList();
  }

  void resetPlantState(Offset position) {
    if (s.readOnly) return;
    finishGesture();
    final stack = piecesAtPointer(position);
    final plants = stack.where((p) => p.spec.category == '植物');
    if (plants.isEmpty) return;
    final piece = plants.first;
    s.execute(
        '恢复植物初始状态',
        s.document.copy(
            pieces: s.document.pieces
                .map((p) =>
                    p.id == piece.id ? p.copy(frameRow: 0, frameCol: 0) : p)
                .toList()));
  }

  List<Piece> piecesAtPointer(Offset position) {
    final geometry = BoardGeometry(s.document);
    // Cactus height is a visual state; use its short silhouette for interaction
    // so an extended stalk cannot steal the plant behind it.
    final pieces = geometry.hitPieces(position)
        .where((p) => geometry.spriteContains(
            p.type == 'cactus' ? p.copy(frameRow: 0, frameCol: 0) : p, position)).toList();
    final cell = geometry.hit(position);
    if (pieces.isEmpty && cell != null) pieces.addAll(at(cell));
    return pieces;
  }

  bool hasPlantStates(Piece piece) {
    if (piece.spec.category != '植物') return false;
    final data = OriginalAssets.sprites[OriginalAssets.names[piece.type] ?? piece.type];
    final images = (data?['images'] as List? ?? [])
        .where((image) => !(image['path'] as String).contains('shadow')).toList();
    return images.isNotEmpty &&
        (images.last['rows'] as num) * (images.last['cols'] as num) > 1;
  }

  bool cyclePlantState(Piece piece) {
    if (piece.spec.category != '植物') return false;
    final data =
        OriginalAssets.sprites[OriginalAssets.names[piece.type] ?? piece.type];
    final layers = (data?['images'] as List? ?? [])
        .where((image) => !(image['path'] as String).contains('shadow'))
        .toList();
    if (layers.isEmpty) return false;
    final rows = (layers.last['rows'] as num).toInt();
    final cols = (layers.last['cols'] as num).toInt();
    if (rows < 1 || cols < 1) return false;
    final index = ((piece.frameRow % rows) * cols + piece.frameCol % cols + 1) %
        (rows * cols);
    final next = piece.copy(frameRow: index ~/ cols, frameCol: index % cols);
    gesturePieces =
        gesturePieces.map((old) => old.id == piece.id ? next : old).toList();
    return true;
  }

  Set<String> shovelTargets(Offset position) {
    // Resolve against the press-time stack so a removed foreground object
    // cannot expose a different row to the same click/drag.
    final document = gesture && shovelFilter == '智能'
        ? gestureBefore ?? s.document
        : s.document;
    final ids = ShovelTargets.at(document, position, shovelFilter);
    if (gesture) {
      ids.retainAll(gesturePieces.map((p) => p.id));
    }
    return ids;
  }

  void touch(Offset position) {
    final geometry = BoardGeometry(s.document);
    final cell = geometry.hit(position);
    if (tool == '模仿') {
      if (s.readOnly || cell == null || !visited.add(cell)) return;
      final stack = geometry.hitPieces(position);
      if (stack.isEmpty) stack.addAll(at(cell));
      final plants = stack.where((p) => p.spec.category == '植物');
      if (plants.isEmpty) return;
      final id = plants.first.id;
      gesturePieces = gesturePieces
          .map((p) => p.id == id
              ? p.copy(effects: {
                  ...p.effects.difference({'阴影', '我是僵尸', '灰烬'}),
                  '模仿者'
                })
              : p)
          .toList();
      setState(() {});
      return;
    }
    if (tool == '选择') {
      final stack = piecesAtPointer(position);
      if (stack.isEmpty) {
        setState(() => selectedId = null);
        return;
      }
      final plants = stack.where((p) => p.spec.category == '植物');
      if (!s.readOnly && plants.isNotEmpty) {
        final plant = plants.first;
        // A roof sprite may extend above its sloping cell or into another row.
        // Visit the actual plant's cell, not the ground under the pointer.
        if (visited.add((plant.row, plant.col))) cyclePlantState(plant);
      }
      final current = stack.indexWhere((p) => p.id == selectedId);
      setState(() {
        selectedId = stack[(current + 1) % stack.length].id;
        hover = cell;
      });
      return;
    }
    if (tool == '铲除' && shovelFilter == '智能') {
      if (s.readOnly) return;
      final ids = shovelTargets(position);
      if (ids.isEmpty) return;
      final target = gesturePieces.firstWhere((p) => ids.contains(p.id));
      if (!visited.add((target.row, target.col))) return;
      gesturePieces.removeWhere((p) => ids.contains(p.id));
      setState(() {});
      return;
    }
    if (cell == null) return;
    hover = cell;
    if (s.readOnly || !visited.add(cell)) return;
    if (tool == '铲除') {
      final ids = shovelTargets(position);
      gesturePieces.removeWhere((p) => ids.contains(p.id));
    } else if (tool == '放置') {
      final existing = gesturePieces
          .where((p) =>
              p.type == selectedType &&
              p.row == cell.$1 &&
              p.col == cell.$2 &&
              p.effects.contains('模仿者') == plantingEffects.contains('模仿者'))
          .toList()
        ..sort((a, b) => b.layer.compareTo(a.layer));
      if (existing.isNotEmpty && cyclePlantState(existing.first)) {
        PlantingSupport.removeConflicts(gesturePieces, existing.first);
        PlantingSupport.removeIncompatibleBases(
            gesturePieces, existing.first, s.document.map);
        setState(() {});
        return;
      }
      final spec = ObjectSpec.byId(selectedType);
      if (cell.$2 + spec.width > s.document.map.columns) return;
      final piece = plantingPiece(cell.$1, cell.$2);
      final next = List<Piece>.of(gesturePieces);
      replacePlanting(next, piece);
      if (next.length > 5000) {
        message(context, '最多支持 5000 个对象');
        return;
      }
      gesturePieces = next;
      plantingFeedback(piece);
    }
    setState(() {});
  }

  void beginGesture(Offset p) {
    if (tool == '平移' || batchSelectionMode) return;
    canvasFocus.requestFocus();
    visited.clear();
    gestureBefore = s.document;
    gesturePieces = List.of(s.document.pieces);
    gesture = true;
    touch(p);
  }

  void finishGesture() {
    if (!gesture) return;
    gesture = false;
    if (!s.readOnly &&
        (tool == '放置' || tool == '铲除' || tool == '选择' || tool == '模仿')) {
      s.execute(
          tool == '选择'
              ? '切换植物状态'
              : tool == '模仿'
                  ? '设置模仿者'
                  : '连续$tool',
          s.document.copy(pieces: gesturePieces));
    }
    gestureBefore = null;
    if (mounted) setState(() {});
  }

  Piece plantingPiece(int row, int col, {bool preview = false}) {
    final spec = ObjectSpec.byId(selectedType);
    var frameRow = plantingFrameRow, frameCol = plantingFrameCol;
    if (growMode == 1 && (selectedType == 'fume' || selectedType == 'gloom')) {
      frameRow = 1;
      frameCol = 0;
    }
    final data = OriginalAssets
        .sprites[OriginalAssets.names[selectedType] ?? selectedType];
    final layers = (data?['images'] as List? ?? [])
        .where((p) => !(p['path'] as String).contains('shadow'))
        .toList();
    if (layers.isNotEmpty && growMode >= 2) {
      final rows = (layers.last['rows'] as num).toInt();
      final cols = (layers.last['cols'] as num).toInt();
      frameRow = ((growMode - 2) ~/ 2).clamp(0, rows - 1);
      frameCol = growMode.isEven && !preview ? frameRandom.nextInt(cols) : 0;
    }
    return Piece(
        id: preview ? 'planting-preview' : newId(),
        type: selectedType,
        row: row,
        col: col,
        layer: spec.layer,
        effects: {...plantingEffects},
        flipped: plantingFlip,
        flippedVertical: plantingVertical,
        appearance: plantingAppearance,
        frameRow: frameRow,
        frameCol: frameCol);
  }

  void replacePlanting(List<Piece> pieces, Piece replacement) {
    PlantingSupport.removeConflicts(pieces, replacement);
    pieces.add(replacement);
    PlantingSupport.addMissing(pieces, replacement, s.document.map,
        autoLily: autoLily, potMode: autoPotMode);
  }

  void batchPlace() {
    if (s.readOnly || cells.isEmpty) return;
    final spec = ObjectSpec.byId(selectedType);
    final ordered = cells.toList()
      ..sort(
          (a, b) => a.$1 == b.$1 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
    final occupied = <(int, int)>{};
    final next = List<Piece>.of(s.document.pieces);
    for (final cell in ordered) {
      if (cell.$2 + spec.width > s.document.map.columns ||
          occupied.contains(cell)) continue;
      replacePlanting(next, plantingPiece(cell.$1, cell.$2));
      for (var offset = 0; offset < spec.width; offset++) {
        occupied.add((cell.$1, cell.$2 + offset));
      }
    }
    if (next.length > 5000) {
      message(context, '对象数量不能超过 5000');
      return;
    }
    s.execute('批量放置', s.document.copy(pieces: next));
  }

  void deleteSelection() {
    if (cells.isNotEmpty) {
      batchDelete('全部');
    } else {
      removeSelected();
    }
  }

  void batchDelete(String kind) {
    if (s.readOnly || cells.isEmpty) return;
    finishGesture();
    final ids = s.document.pieces
        .where((p) =>
            cells.any((c) =>
                c.$1 == p.row &&
                c.$2 >= p.col &&
                c.$2 < p.col + p.spec.width) &&
            ObjectFilter.matches(p, kind))
        .map((p) => p.id)
        .toSet();
    final shells = s.document.pieces
        .where((p) => p.type == 'pumpkin' && ids.contains(p.id));
    for (final shell in shells) {
      ids.addAll(s.document.pieces
          .where((p) =>
              p.type == 'ladder' && p.row == shell.row && p.col == shell.col)
          .map((p) => p.id));
    }
    s.execute(
        '批量删除',
        s.document.copy(
            pieces:
                s.document.pieces.where((p) => !ids.contains(p.id)).toList()));
  }

  void finishBatchOperations() {
    finishGesture();
    setState(() {
      clearBatchSelection();
      batchSelectionMode = false;
      tool = '选择';
    });
  }

  void clearBatchSelection() {
    cells.clear();
    batchRows.clear();
    batchColumns.clear();
  }

  void setSelectionMode(bool batch) {
    finishGesture();
    setState(() {
      batchSelectionMode = batch;
      batchSelectorsVisible = true;
      cells.clear();
      if (batch) {
        cells.addAll({for (final r in batchRows) for (final c in batchColumns) (r, c)});
      }
      plantingPointer = null;
      selectedId = null;
    });
  }

  void updateBatchSelection(Set<int> rows, Set<int> columns) {
    setState(() {
      batchRows..clear()..addAll(rows.where((r) => r >= 0 && r < s.document.map.rows));
      batchColumns..clear()..addAll(columns.where((c) => c >= 0 && c < s.document.map.columns));
      cells..clear()..addAll({for (final r in batchRows) for (final c in batchColumns) (r, c)});
    });
  }

  void quickSelect(String label) {
    setSelectionMode(true);
    final selected = label == '重置批量选择'
        ? <(int, int)>{}
        : OriginalSelection.cells(s.document.map, label);
    updateBatchSelection(selected.map((c) => c.$1).toSet(),
        selected.map((c) => c.$2).toSet());
  }

  Future<void> changeMap(BoardMap map) async {
    if (s.readOnly || map.id == s.document.mapId) return;
    await navigateFormation(s.document.copy(
        mapId: map.id,
        pieces:
            s.document.pieces.where((p) => s.document.fits(p, map)).toList()));
    setState(() {
      clearBatchSelection();
      selectedId = null;
      hover = null;
    });
    fit();
  }

  Future<void> refreshLibraryView() async {
    if (nativeWindows) {
      await WindowBridge.refreshLibrary();
    } else {
      await fallbackLibraryKey.currentState?.refresh();
    }
  }

  Future<void> showCurrentArchiveHistory() async {
    if (historyDialogOpen ||
        renameDialogOpen ||
        savingArchive ||
        fileOperationBusy ||
        ModalRoute.of(context)?.isCurrent != true) return;
    final target = s;
    final token = documentToken;
    setState(() => historyDialogOpen = true);
    try {
      await finishDocumentRename();
      finishGesture();
      await target.flush();
      if (!mounted || !identical(s, target) || documentToken != token) return;
      if (target.error != null) throw StateError(target.error!);
      final archiveId = target.sourceArchiveId;
      if (archiveId == null) {
        message(context, '当前存档还没有历史版本');
        return;
      }
      Future<ArchiveHistorySnapshot> load() async {
        final current = (await target.repository.listArchives())
            .where((archive) => archive.id == archiveId)
            .firstOrNull;
        if (current == null) throw StateError('存档已不存在');
        return (
          current: current,
          versions: await target.repository.listVersions(archiveId)
        );
      }

      var snapshot = await load();
      var editingFingerprint = target.document.fingerprint;
      var editingName = target.name;
      if (!mounted || !identical(s, target) || documentToken != token) return;
      await showArchiveHistoryDialog(context,
          snapshot: snapshot,
          onRestore: target.readOnly
              ? null
              : (version) async {
                  if (!mounted ||
                      !identical(s, target) ||
                      documentToken != token ||
                      target.readOnly ||
                      target.sourceArchiveId != archiveId ||
                      version.archiveId != archiveId) {
                    throw StateError('当前存档已切换，请重新打开历史版本');
                  }
                  Formation.fromJson(version.document);
                  if (historyRestoring) throw StateError('正在恢复历史版本');
                  historyRestoring = true;
                  try {
                    final controller = editingTabs;
                    if (controller != null && !await controller.flushAll()) {
                      throw StateError(controller.error ?? '无法保存其他标签页');
                    }
                    await target.flush();
                    if (target.error != null) throw StateError(target.error!);
                    if (!mounted ||
                        !identical(s, target) ||
                        documentToken != token ||
                        target.readOnly ||
                        target.document.fingerprint != editingFingerprint ||
                        target.name != editingName ||
                        Formation.fromJson(snapshot.current.document)
                                .fingerprint !=
                            editingFingerprint ||
                        snapshot.current.name != editingName) {
                      throw StateError('存档已更新，请重新打开历史版本');
                    }
                    final linked = controller?.allSessions
                            .where((session) =>
                                session != target &&
                                !session.readOnly &&
                                session.sourceArchiveId == archiveId &&
                                session.document.fingerprint ==
                                    editingFingerprint &&
                                session.name == editingName)
                            .toList() ??
                        <EditorSession>[];
                    final restored = await target.repository
                        .restoreArchiveVersion(
                            archiveId: archiveId,
                            versionId: version.id,
                            expectedFingerprint:
                                Formation.fromJson(snapshot.current.document)
                                    .fingerprint,
                            expectedName: snapshot.current.name);
                    await target.reloadSavedArchive(restored, forceUndo: true);
                    for (final session in linked) {
                      await session.reloadSavedArchive(restored,
                          forceUndo: true);
                    }
                    if (mounted && identical(s, target)) {
                      cancelPlanting();
                      sunEditor.text = '${target.document.sunValue}';
                      fit();
                    }
                    snapshot = (
                      current: restored,
                      versions: await target.repository.listVersions(archiveId)
                    );
                    editingFingerprint = target.document.fingerprint;
                    editingName = target.name;
                    await refreshLibraryView();
                    return snapshot;
                  } finally {
                    historyRestoring = false;
                    queueWindowState();
                  }
                });
    } catch (error) {
      if (mounted) message(context, '无法打开历史版本：$error');
    } finally {
      if (mounted) setState(() => historyDialogOpen = false);
    }
  }

  Future<void> renameFromMenu() async {
    if (s.readOnly || savingArchive || renameDialogOpen) return;
    final target = s;
    await finishDocumentRename();
    if (!mounted || !identical(s, target) || target.readOnly) return;
    setState(() => renameDialogOpen = true);
    try {
      final requested = await showRenameDialog(context, target.name);
      if (!mounted ||
          !identical(s, target) ||
          target.readOnly ||
          requested == null ||
          requested == target.name) return;
      final operation = persistDocumentName(target, requested);
      pendingDocumentRename = operation;
      try {
        await operation;
      } finally {
        if (identical(pendingDocumentRename, operation)) {
          pendingDocumentRename = null;
        }
      }
    } catch (error) {
      if (mounted) message(context, '重命名失败：$error');
    } finally {
      if (mounted) setState(() => renameDialogOpen = false);
    }
  }

  Future<void> renameDocument() async {
    if (s.readOnly ||
        savingArchive ||
        pendingDocumentRename != null ||
        editingDocumentName) return;
    documentNameEditor.value = TextEditingValue(
        text: s.name,
        selection: TextSelection(baseOffset: 0, extentOffset: s.name.length));
    setState(() {
      documentNameSession = s;
      editingDocumentName = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && editingDocumentName) documentNameFocus.requestFocus();
    });
  }

  Future<void> finishDocumentRename({bool cancel = false}) async {
    if (!editingDocumentName) {
      await pendingDocumentRename;
      return;
    }
    final target = documentNameSession;
    final requested = documentNameEditor.text.trim();
    setState(() {
      editingDocumentName = false;
      documentNameSession = null;
    });
    documentNameFocus.unfocus();
    if (cancel ||
        target == null ||
        target.readOnly ||
        requested.isEmpty ||
        requested == target.name) return;
    final operation = persistDocumentName(target, requested);
    pendingDocumentRename = operation;
    try {
      await operation;
    } catch (error) {
      if (mounted) message(context, '重命名失败：$error');
    } finally {
      if (identical(pendingDocumentRename, operation)) {
        pendingDocumentRename = null;
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> persistDocumentName(
      EditorSession target, String requested) async {
    final controller =
        context.findAncestorWidgetOfExactType<EditorWorkspace>()?.controller;
    final name = await target.repository.uniqueDocumentName(requested,
        reservedNames: controller?.sessions
                .where((item) => item != target)
                .map((item) => item.name) ??
            const []);
    target.rename(name);
    await target.flush();
    if (target.error != null) {
      if (mounted) message(context, '重命名失败：${target.error}');
      return;
    }
    for (final session in controller?.allSessions ?? <EditorSession>[target]) {
      if (session != target &&
          !session.readOnly &&
          session.sourceArchiveId == target.sourceArchiveId &&
          session.document.fingerprint == target.document.fingerprint) {
        await session.markArchived(
            target.sourceArchiveId!, target.document.fingerprint,
            name: target.name);
      }
    }
    await refreshLibraryView();
  }

  Future<void> saveArchive({bool saveAs = false}) async {
    if (widget.toolboxOnly) {
      await WindowBridge.mainAction(saveAs ? 'saveArchiveAs' : 'saveArchive');
      return;
    }
    if ((s.readOnly && !saveAs) || savingArchive) return;
    await finishDocumentRename();
    finishGesture();
    setState(() => savingArchive = true);
    try {
      await s.flush(forceSave: !saveAs);
      if (s.error != null) throw StateError(s.error!);
      if (!saveAs) {
        finishBatchOperations();
        await refreshLibraryView();
        if (mounted) message(context, '已保存');
        return;
      }
      final source = (await s.repository.listArchives())
          .where((a) => a.id == s.sourceArchiveId)
          .firstOrNull;
      if (!mounted) return;
      final controller =
          context.findAncestorWidgetOfExactType<EditorWorkspace>()?.controller;
      final reserved = controller?.sessions.map((item) => item.name).toList() ??
          <String>[s.name];
      final suggested = await s.repository
          .uniqueDocumentName(s.name, reservedNames: reserved);
      if (!mounted) return;
      final data = await archiveDialog(context,
          name: suggested,
          note: source?.note ?? '',
          tags: source?.tags ?? [],
          saveAs: true);
      if (data == null) return;
      final name = await s.repository
          .uniqueDocumentName(data.$1, reservedNames: reserved);
      final document = s.document;
      final archive = await s.repository.saveArchive(
          id: newId(),
          uniqueName: true,
          name: name,
          note: data.$2,
          tags: data.$3,
          document: document.toJson());
      if (!s.readOnly) {
        await s.markArchived(archive.id, document.fingerprint,
            name: archive.name);
      }
      finishBatchOperations();
      await refreshLibraryView();
      if (mounted) message(context, '已另存为：${archive.name}');
    } catch (e) {
      if (mounted) message(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => savingArchive = false);
    }
  }

  Future<FormationFormat?> chooseExportFormat() =>
      formationFormatPrompt(context, s.document, initial: exportFormat);

  Future<void> exportFormationFile({required bool saveAs}) async {
    FormationFormat format;
    String? path;
    if (!saveAs && s.filePath != null) {
      path = s.filePath;
      format = FormationFormat.values.firstWhere((f) => f.name == s.fileFormat,
          orElse: () => FormationFormat.toolkit);
    } else {
      final selected = await chooseExportFormat();
      if (selected == null) return;
      format = selected;
    }
    final text = FormationExchange.encode(s.document, format: format);
    final bytes = Uint8List.fromList(utf8.encode(text));
    if (path != null) {
      s.lastFileBackup = await ProjectFiles.saveToPath(path, bytes);
    } else {
      final saved = await ProjectFiles.saveWithBackup(
          '${safeName(s.name)}.${format.fileExtension}',
          bytes,
          format == FormationFormat.project
              ? 'application/json'
              : 'text/plain');
      if (saved == null) return;
      path = saved.path;
      s.lastFileBackup = saved.backupPath;
    }
    s.filePath = path;
    s.fileFormat = format.name;
    finishBatchOperations();
    if (mounted) {
      setState(() => exportFormat = format);
      message(
          context, '阵图已保存：$path${s.lastFileBackup == null ? '' : '（原文件已备份）'}');
    }
  }

  Future<void> transfer(String action) async {
    if (widget.toolboxOnly &&
        const ['project', 'saveAs', 'saveFile', 'restoreFile', 'import']
            .contains(action)) {
      await WindowBridge.mainAction('transfer:$action');
      return;
    }
    final fileAction = const [
      'project',
      'saveAs',
      'saveFile',
      'restoreFile',
      'import'
    ].contains(action);
    if (fileAction && fileOperationBusy) return;
    if (fileAction) fileOperationBusy = true;
    finishGesture();
    if (!mounted) {
      if (fileAction) fileOperationBusy = false;
      return;
    }
    try {
      if (action == 'restoreFile') {
        if (s.lastFileBackup == null || s.filePath == null) {
          message(context, '当前文件没有可撤销的覆盖');
          return;
        }
        final redo =
            await FileBackups.restoreBackup(s.lastFileBackup!, s.filePath!);
        final restored =
            FormationExchange.decode(await File(s.filePath!).readAsString());
        await navigateFormation(restored,
            name: s.name,
            filePath: s.filePath,
            fileFormat: s.fileFormat,
            lastFileBackup: redo);
        if (mounted) message(context, '已恢复覆盖前的阵图文件');
        return;
      }
      if (const ['project', 'saveAs', 'saveFile'].contains(action)) {
        await exportFormationFile(saveAs: action != 'saveFile');
        return;
      }
      if (action == 'png' && mounted) {
        var factor = 2.0;
        var background = true;
        final result = await showDialog<(double, bool)>(
            context: context,
            builder: (ctx) => StatefulBuilder(
                builder: (ctx, set) => AlertDialog(
                        title: Text(AppLanguage.text('导出棋盘 PNG')),
                        content:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          AppDropdown<double>(
                              value: factor,
                              items: [1.0, 2.0, 3.0, 4.0]
                                  .map((v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(
                                          AppLanguage.text('${v.toInt()} 倍'))))
                                  .toList(),
                              onChanged: (v) => set(() => factor = v!)),
                          SwitchListTile(
                              title: Text(AppLanguage.text('包含棋盘背景')),
                              value: background,
                              onChanged: (v) => set(() => background = v))
                        ]),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(AppLanguage.text('取消'))),
                          FilledButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, (factor, background)),
                              child: Text(AppLanguage.text('导出')))
                        ])));
        if (result == null) return;
        final bytes = await exportPng(s.document,
            multiplier: result.$1, background: result.$2);
        final path = await ProjectFiles.save(
            '${safeName(s.name)}.png', bytes, 'image/png');
        if (path != null && mounted) message(context, 'PNG 已导出：$path');
      }
      if (action == 'toolkit' && mounted) {
        final issues = FormationExchange.exportIssues(s.document);
        if (issues.isNotEmpty) {
          await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                      title: Text(AppLanguage.text('当前阵型不支持 Toolkit 格式')),
                      content: SizedBox(
                          width: 520,
                          child: SingleChildScrollView(
                              child: Text(issues.join('\n')))),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(AppLanguage.text('关闭')))
                      ]));
          return;
        }
        final text = FormationExchange.encode(s.document);
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          await textPrompt(context, 'Toolkit 阵型码（已复制）',
              initial: text, multiline: true);
        }
      }
      if (action == 'importWebsite' && mounted) {
        final text =
            await textPrompt(context, '导入阵型码（Toolkit / 布阵器）', multiline: true);
        if (text == null) return;
        final doc = FormationExchange.decode(text);
        await navigateFormation(doc, name: '导入阵型');
        clearBatchSelection();
        selectedId = null;
        hover = null;
        fit();
      }
      if (action == 'string') {
        final text = FormationExchange.encode(s.document);
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          await textPrompt(context, 'Toolkit 阵型码（已复制）',
              initial: text, multiline: true);
        }
      }
      if (action == 'importString' && mounted) {
        final value =
            await textPrompt(context, '导入阵型码（自动识别格式）', multiline: true);
        if (value == null) return;
        final doc = FormationExchange.decode(value);
        await navigateFormation(doc, name: '导入阵型');
        clearBatchSelection();
        selectedId = null;
        hover = null;
        fit();
      }
      if (action == 'import' && mounted) {
        final picked = await ProjectFiles.pickWithPath();
        if (picked == null) return;
        final text = utf8.decode(picked.bytes);
        final doc = FormationExchange.decode(text);
        await navigateFormation(doc,
            name: picked.path?.split('/').last.split('.').first ?? '导入阵图',
            filePath: picked.path,
            fileFormat: FormationExchange.detectFormat(text).name);
        clearBatchSelection();
        selectedId = null;
        hover = null;
        fit();
      }
      if (action == 'snapshot' && mounted) {
        setState(() => snapshot = Formation.fromJson(s.document.toJson()));
        message(context, '已创建独立只读快照，后续编辑不会改变它');
      }
      if (action == 'compare' && mounted) showComparison();
    } catch (e) {
      if (mounted) message(context, '操作失败：$e');
    } finally {
      if (fileAction) fileOperationBusy = false;
    }
  }

  void showComparison() {
    if (snapshot == null) {
      message(context, '先创建对比快照');
      return;
    }
    final current = Formation.fromJson(s.document.toJson());
    final old = snapshot!;
    showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child:
                            Text(AppLanguage.text('只读对比 · 左：创建时快照 / 右：当前阵型'))),
                    IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close))
                  ]),
                  Expanded(
                      child: LayoutBuilder(
                          builder: (ctx, c) => Flex(
                                  direction: c.maxWidth > 700
                                      ? Axis.horizontal
                                      : Axis.vertical,
                                  children: [
                                    for (final f in [old, current])
                                      Expanded(
                                          child: FittedBox(
                                              child: SizedBox.fromSize(
                                                  size: BoardGeometry(f).size,
                                                  child: CustomPaint(
                                                      painter: BoardPainter(
                                                          document: f,
                                                          helpers: false)))))
                                  ])))
                ]))));
  }

  void shortcut(void Function() action) {
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return;
    }
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return;
    }
    action();
  }

  void cancelPlanting() {
    finishGesture();
    editingPointer = null;
    setState(() {
      if (tool == '模仿') plantingEffects.remove('模仿者');
      clearBatchSelection();
      selectedId = null;
      plantingPointer = null;
      tool = '选择';
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
      onPointerDown: (event) {
        if (event.buttons == 2) cancelPlanting();
      },
      child: buildEditor(context));

  Widget buildEditor(BuildContext context) {
    if (widget.toolboxOnly) {
      return Scaffold(
          backgroundColor: const Color(0xfff3f6eb),
          body: classicToolboxContents());
    }
    if (nativeWindows) {
      return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
                shortcut(() => unawaited(undoEditing())),
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
                shortcut(() => unawaited(undoEditing())),
            const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
                shortcut(() => unawaited(redoEditing())),
            const SingleActivator(LogicalKeyboardKey.keyY, meta: true): () =>
                shortcut(() => unawaited(redoEditing())),
            const SingleActivator(LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true): () => shortcut(() => unawaited(redoEditing())),
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
                shortcut(saveArchive),
            const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
                shortcut(saveArchive),
            const SingleActivator(LogicalKeyboardKey.delete): () =>
                shortcut(deleteSelection),
            const SingleActivator(LogicalKeyboardKey.backspace): () =>
                shortcut(deleteSelection),
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                shortcut(cancelPlanting),
          },
          child: Focus(
              focusNode: canvasFocus,
              autofocus: true,
              child: nativeMainPage()));
    }
    return PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (!didPop) unawaited(leave());
        },
        child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                  () => shortcut(() => unawaited(undoEditing())),
              const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
                  shortcut(() => unawaited(undoEditing())),
              const SingleActivator(LogicalKeyboardKey.keyY, control: true):
                  () => shortcut(() => unawaited(redoEditing())),
              const SingleActivator(LogicalKeyboardKey.keyY, meta: true): () =>
                  shortcut(() => unawaited(redoEditing())),
              const SingleActivator(LogicalKeyboardKey.keyZ,
                  meta: true,
                  shift: true): () => shortcut(() => unawaited(redoEditing())),
              const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  () => shortcut(saveArchive),
              const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
                  shortcut(saveArchive),
              const SingleActivator(LogicalKeyboardKey.delete): () =>
                  shortcut(deleteSelection),
              const SingleActivator(LogicalKeyboardKey.backspace): () =>
                  shortcut(deleteSelection),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  shortcut(cancelPlanting),
            },
            child: Focus(
                focusNode: canvasFocus,
                autofocus: true,
                child: Scaffold(
                    backgroundColor: const Color(0xff748899),
                    body: SafeArea(
                        child: SingleChildScrollView(
                            child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                    width: math.max(
                                        1224, toolboxPosition.dx + 410),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (widget.tabBar != null)
                                            SizedBox(
                                                height: 28,
                                                width: 810,
                                                child: workspaceTabBar()),
                                          Container(
                                              height: 32,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                              color: const Color(0xffd9e1e7),
                                              child: Row(children: [
                                                Text(
                                                    AppLanguage.text(
                                                        '植物大战僵尸布阵器'),
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                    child: documentHeading()),
                                                historyButton(redo: false),
                                                historyButton(redo: true),
                                                seedChooserButton(),
                                                if (widget.tabBar == null)
                                                  workspaceMoreMenu(),
                                                if (cells.isNotEmpty ||
                                                    batchSelectionMode)
                                                  classicButton('取消批量选择',
                                                      finishBatchOperations,
                                                      key: const ValueKey(
                                                          'finish-batch-toolbar')),
                                                classicButton(
                                                    '窗口复位',
                                                    () => setState(() {
                                                          toolboxPosition =
                                                              const Offset(
                                                                  808, 0);
                                                          for (var i = 0;
                                                              i <
                                                                  mirrors
                                                                      .length;
                                                              i++) {
                                                            mirrorPositions[i] =
                                                                Offset(
                                                                    30.0 +
                                                                        i * 32,
                                                                    30.0 +
                                                                        i * 32);
                                                          }
                                                        })),
                                                sidebarModeButton('toolbox'),
                                                sidebarModeButton('library')
                                              ])),
                                          SizedBox(
                                              height: 680,
                                              child: Stack(
                                                  clipBehavior: Clip.hardEdge,
                                                  children: [
                                                    Positioned(
                                                        left: 0,
                                                        top: 0,
                                                        width: 810,
                                                        height: 635,
                                                        child: RawImage(
                                                            image: OriginalAssets
                                                                .image(
                                                                    'image/window$windowStyle.png'),
                                                            key: ValueKey(
                                                                'original-window-background-$windowStyle'),
                                                            fit: BoxFit.none,
                                                            alignment: Alignment
                                                                .topLeft)),
                                                    Positioned(
                                                        left: 3,
                                                        top: 27,
                                                        width: 800,
                                                        height: 600,
                                                        child: board()),
                                                    Positioned(
                                                        left:
                                                            toolboxPosition.dx,
                                                        top: toolboxPosition.dy,
                                                        child: Offstage(
                                                            offstage:
                                                                !toolboxVisible,
                                                            child:
                                                                fallbackSidebar())),
                                                    for (var i = 0;
                                                        i < mirrors.length;
                                                        i++)
                                                      mirrorWindow(i),
                                                    if (seedChooserOpen)
                                                      seedChooserOverlay(),
                                                  ])),
                                          SizedBox(
                                              width: 800, child: statusBar()),
                                        ])))))))));
  }

  String get saveShortcutHint => Platform.isMacOS ? '保存（⌘S）' : '保存（Ctrl+S）';

  Widget historyButton({required bool redo}) => classicButton(
      redo ? '恢复' : '撤销',
      redo
          ? (canRedoEditing ? redoEditing : null)
          : (canUndoEditing ? undoEditing : null),
      icon: redo ? Icons.redo : Icons.undo,
      iconOnly: true,
      tooltip: redo
          ? (Platform.isMacOS ? '恢复刚撤销的操作（⌘Y / ⇧⌘Z）' : '恢复刚撤销的操作（Ctrl+Y）')
          : (Platform.isMacOS ? '撤销上一步操作（⌘Z）' : '撤销上一步操作（Ctrl+Z）'));

  Widget classicButton(String label, VoidCallback? action,
      {bool active = false, Key? key, IconData? icon, bool iconOnly = false, String? tooltip}) {
    final button = Padding(
        padding: const EdgeInsets.all(2),
        child: SizedBox(
            height: 25,
            child: OutlinedButton(
                key: key,
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    minimumSize: Size.zero,
                    foregroundColor: const Color(0xff304f36),
                    side: BorderSide(
                        color: active
                            ? const Color(0xff70945d)
                            : const Color(0xffccd9c2)),
                    backgroundColor: active
                        ? const Color(0xffe1edcf)
                        : const Color(0xfffbfcf7),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7)),
                    textStyle: const TextStyle(fontSize: 12)),
                onPressed: action,
                child: icon == null
                    ? Text(AppLanguage.text(label))
                    : iconOnly
                        ? Semantics(label: AppLanguage.text(label), child: Icon(icon, size: 16))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 16),
                        const SizedBox(width: 3),
                        Text(AppLanguage.text(label)),
                      ]))));
    return tooltip == null
        ? button
        : Tooltip(message: AppLanguage.text(tooltip), child: button);
  }

  Widget mirrorWindow(int i) {
    final boardSize = BoardGeometry(mirrors[i]).size;
    final size = Size(
        mirrorPokerWidths[i] ? boardSize.width * 917 / 800 : boardSize.width,
        boardSize.height);
    final scale = mirrorScales[i];
    final width = (size.width * scale + 2).clamp(420.0, 1000.0);
    final height = (size.height * scale + 65).clamp(180.0, 570.0);
    return Positioned(
        left: mirrorPositions[i].dx,
        top: mirrorPositions[i].dy,
        child: ClassicWindow(
            title: '${AppLanguage.text('镜像')} ${i + 1}',
            width: width,
            height: height,
            dragKey: ValueKey('mirror-drag-$i'),
            onDrag: (delta) => setState(() => mirrorPositions[i] =
                windowPosition(mirrorPositions[i], delta, width)),
            onClose: () => setState(() {
                  mirrors.removeAt(i);
                  mirrorScales.removeAt(i);
                  mirrorBackgrounds.removeAt(i);
                  mirrorPokerWidths.removeAt(i);
                  mirrorPositions.removeAt(i);
                }),
            child: Column(children: [
              SizedBox(
                  height: 34,
                  child: Row(children: [
                    const SizedBox(width: 6),
                    Text(AppLanguage.text('比例 '),
                        style: const TextStyle(fontSize: 12)),
                    AppDropdown<double>(
                        key: ValueKey('mirror-scale-$i'),
                        value: scale,
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1/1×')),
                          DropdownMenuItem(value: .75, child: Text('3/4×')),
                          DropdownMenuItem(value: 2 / 3, child: Text('2/3×')),
                          DropdownMenuItem(value: .5, child: Text('1/2×')),
                          DropdownMenuItem(value: 1.5, child: Text('3/2×')),
                          DropdownMenuItem(value: 2, child: Text('2/1×'))
                        ],
                        onChanged: (v) => setState(() {
                              mirrorScales[i] = v!;
                              mirrorPositions[i] = windowPosition(
                                  mirrorPositions[i],
                                  Offset.zero,
                                  (size.width * v + 2).clamp(420.0, 1000.0));
                            })),
                    Checkbox(
                        key: ValueKey('mirror-background-$i'),
                        value: mirrorBackgrounds[i],
                        onChanged: (v) =>
                            setState(() => mirrorBackgrounds[i] = v!)),
                    Text(AppLanguage.text('背景'),
                        style: const TextStyle(fontSize: 12)),
                    classicButton('导出镜像 ${i + 1}', () async {
                      try {
                        final bytes = await exportPng(mirrors[i],
                            multiplier: scale,
                            background: mirrorBackgrounds[i],
                            pokerWidth: mirrorPokerWidths[i]);
                        await ProjectFiles.save(
                            '镜像${i + 1}.png', bytes, 'image/png');
                      } catch (e) {
                        if (mounted) message(context, e);
                      }
                    }),
                  ])),
              Expanded(
                  child: SingleChildScrollView(
                      child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                              width: size.width * scale,
                              height: size.height * scale,
                              child: FittedBox(
                                  fit: BoxFit.fill,
                                  child: SizedBox.fromSize(
                                      size: boardSize,
                                      child: CustomPaint(
                                          painter: BoardPainter(
                                              document: mirrors[i],
                                              background: mirrorBackgrounds[i],
                                              helpers: false)))))))),
            ])));
  }

  void persistPlantingPreferences() {
    if (widget.toolboxOnly) return;
    unawaited(PlantingPreferences(autoLily: autoLily, potMode: autoPotMode)
        .save()
        .catchError((Object error) {
      if (mounted) message(context, '种植设置保存失败：$error');
    }));
  }

  Widget plantingSupportOptions() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(AppLanguage.text('自动垫荷叶 '),
              style: const TextStyle(fontSize: 12)),
          originalCheck('autoLily', '水面', autoLily, (value) {
            setState(() => autoLily = value);
            persistPlantingPreferences();
          }),
        ]),
        Row(children: [
          Text(AppLanguage.text('自动垫花盆 '),
              style: const TextStyle(fontSize: 12)),
          originalCheck('auto-pot-roof', '屋顶',
              autoPotMode == 'roof' || autoPotMode == 'land', (value) {
            final land = autoPotMode == 'ground' || autoPotMode == 'land';
            setState(() => autoPotMode =
                value ? (land ? 'land' : 'roof') : (land ? 'ground' : 'off'));
            persistPlantingPreferences();
          }),
          const SizedBox(width: 8),
          originalCheck('auto-pot-land', '陆地',
              autoPotMode == 'ground' || autoPotMode == 'land', (value) {
            final roof = autoPotMode == 'roof' || autoPotMode == 'land';
            setState(() => autoPotMode =
                value ? (roof ? 'land' : 'ground') : (roof ? 'roof' : 'off'));
            persistPlantingPreferences();
          }),
        ]),
      ]);

  Widget originalCheck(
          String id, String label, bool checked, ValueChanged<bool>? change) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
            width: 22,
            height: 24,
            child: Checkbox(
                key: ValueKey('original-$id'),
                value: checked,
                onChanged: change == null ? null : (v) => change(v!),
                visualDensity: VisualDensity.compact)),
        Text(AppLanguage.text(label), style: const TextStyle(fontSize: 12)),
      ]);

  Widget originalVolume(
          String prefix, String label, int level, ValueChanged<int> change) =>
      Row(children: [
        Text(AppLanguage.text(label), style: const TextStyle(fontSize: 12)),
        for (var i = 0; i < 5; i++)
          InkWell(
              key: ValueKey('original-$prefix$i'),
              onTap: () => change(i),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: 20,
                    height: 24,
                    child: Radio<int>(
                        value: i,
                        groupValue: level,
                        onChanged: (v) => change(v!),
                        visualDensity: VisualDensity.compact)),
                Text(AppLanguage.text(['静音', '25%', '50%', '75%', '正常'][i]),
                    style: const TextStyle(fontSize: 12)),
              ])),
      ]);

  Widget mapChangeControls(Key buttonKey, {String label = '更换地图'}) =>
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        classicButton(label, () => unawaited(chooseMapFromCatalog()),
            key: buttonKey),
        originalCheck(
            'map-keep-plants',
            '更换时保留植物',
            keepPlantsOnMapChange,
            s.readOnly
                ? null
                : (value) => setState(() => keepPlantsOnMapChange = value)),
      ]);

  Future<void> chooseMapFromCatalog() async {
    final target = s;
    final token = documentToken;
    final fingerprint = s.document.fingerprint;
    try {
      final result = await showMapPickerDialog(context,
          currentMapId: target.document.mapId,
          currentFormation: target.document,
          keepPlants: keepPlantsOnMapChange,
          keepPlantsListenable: keepPlantsOnMapChangeNotifier,
          onKeepPlantsChanged: (value) =>
              setState(() => keepPlantsOnMapChange = value),
          readOnly: target.readOnly);
      if (result == null || !mounted || target.readOnly) return;
      if (!identical(s, target) ||
          token != documentToken ||
          fingerprint != s.document.fingerprint) {
        throw StateError('主画面已更新，请重新选择地图');
      }
      await applyMapSelection(result.mapId, result.keepPlants);
    } catch (error) {
      if (mounted) message(context, error);
    }
  }

  Future<void> applySelectedMap(bool keep) =>
      applyMapSelection(pendingMapId ?? s.document.mapId, keep);

  Future<void> applyMapSelection(String mapId, bool keep) async {
    if (s.readOnly) return;
    if (widget.toolboxOnly) {
      await WindowBridge.mainAction('changeMap', payload: {
        'mapId': mapId,
        'keepPlants': keep,
        'baseFingerprint': remoteBaseFingerprint,
      });
      return;
    }
    finishGesture();
    final map = BoardMap.byId(mapId);
    final retained =
        s.document.pieces.where((p) => s.document.fits(p, map)).toList();
    s.execute(
        '更换地图', s.document.copy(mapId: map.id, pieces: keep ? retained : []));
    cancelPlanting();
    setState(() {
      pendingMapId = map.id;
      hover = null;
    });
    fit();
  }

  Widget classicSettings() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const LanguageSelector(),
        const SizedBox(height: 8),
        mapChangeControls(const ValueKey('settings-change-map')),
        Row(children: [
          Expanded(
              child: Text(AppLanguage.text(s.document.map.name),
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis)),
          classicButton('下载地图', () async {
            try {
              final map = s.document.map;
              final path = 'image/${map.background}';
              final bytes = await rootBundle.load('assets/original/$path');
              await ProjectFiles.save(
                  path.split('/').last,
                  bytes.buffer
                      .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
                  path.endsWith('.png') ? 'image/png' : 'image/jpeg');
            } catch (e) {
              if (mounted) message(context, '下载地图失败：$e');
            }
          }, key: const ValueKey('original-imgBack')),
        ]),
        const SizedBox(height: 14),
        originalVolume('cMusic', '音乐音量 ', musicLevel, (i) {
          setState(() => musicLevel = i);
          unawaited(OriginalAudio.setMusicVolume(i / 4).then((_) => update()));
        }),
        originalVolume('cAudio', '音效音量 ', soundLevel, (i) {
          setState(() => soundLevel = i);
          unawaited(OriginalAudio.setSoundVolume(i / 4).then((_) => update()));
        }),
        Text(AppLanguage.text('背景音乐与种植音效'),
            style: const TextStyle(fontSize: 12)),
        if (OriginalAudio.soundStatus.value == 'missingAsset' && soundLevel > 0)
          Text(AppLanguage.text('种植音效暂不可用'),
              style: const TextStyle(fontSize: 11, color: Colors.brown)),
        const SizedBox(height: 12),
        Row(children: [
          Text(AppLanguage.text('显示迷雾 '), style: const TextStyle(fontSize: 12)),
          AppDropdown<int>(
              key: const ValueKey('original-lFog'),
              isDense: true,
              value: s.document.fogColumns,
              style: const TextStyle(fontSize: 12, color: Colors.black),
              items: List.generate(
                  11,
                  (i) => DropdownMenuItem(
                      value: i,
                      child:
                          Text(AppLanguage.text(i == 0 ? '默认不显示' : '$i列雾')))),
              onChanged: s.readOnly
                  ? null
                  : (v) => s.execute(
                      '显示迷雾',
                      s.document.copy(
                          fogColumns: v,
                          display: {...s.document.display, '迷雾': v! > 0}))),
          Expanded(
              child: Text(AppLanguage.text('(建议布好阵之后再选择显示)'),
                  style: const TextStyle(fontSize: 11))),
        ]),
        const SizedBox(height: 10),
        originalCheck(
            'cSoil',
            '显示土壤水花(配置不好可能会有点卡)',
            s.document.display['泥土'] == true,
            s.readOnly
                ? null
                : (v) => s.execute(
                    '显示土壤水花',
                    s.document
                        .copy(display: {...s.document.display, '泥土': v}))),
        const SizedBox(height: 12),
        Row(children: [
          originalCheck(
              'rSeed',
              '显示阳光、卡片槽',
              s.document.display['卡槽'] == true,
              s.readOnly
                  ? null
                  : (v) => s.execute(
                      '显示阳光卡片槽',
                      s.document.copy(
                          display: {...s.document.display, '阳光': v, '卡槽': v}))),
          SizedBox(
              width: 56,
              height: 23,
              child: TextField(
                  key: const ValueKey('original-tSun'),
                  controller: sunEditor,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                      isDense: true))),
          classicButton(
              '改阳光',
              s.readOnly
                  ? null
                  : () {
                      final n = int.tryParse(sunEditor.text);
                      if (n == null || n < 0 || n > 99999999) {
                        message(context, '请输入范围内的整数');
                        return;
                      }
                      s.execute('改阳光', s.document.copy(sunValue: n));
                    },
              key: const ValueKey('original-bSun')),
        ]),
        const SizedBox(height: 12),
        Wrap(children: [
          originalCheck(
              'rClear',
              '显示小推车',
              s.document.display['小推车'] == true,
              s.readOnly
                  ? null
                  : (v) => s.execute(
                      '显示小推车',
                      s.document
                          .copy(display: {...s.document.display, '小推车': v}))),
          originalCheck(
              'rBrain',
              '显示脑子',
              s.document.display['脑子'] == true,
              s.readOnly
                  ? null
                  : (v) => s.execute(
                      '显示脑子',
                      s.document
                          .copy(display: {...s.document.display, '脑子': v})))
        ]),
        const SizedBox(height: 10),
        originalCheck(
            'rCtc',
            '显示click to continue',
            s.document.display['继续标识'] == true,
            s.readOnly
                ? null
                : (v) => s.execute(
                    '显示继续标识',
                    s.document
                        .copy(display: {...s.document.display, '继续标识': v}))),
        const SizedBox(height: 12),
        Wrap(children: [
          for (var i = 1; i <= 3; i++)
            InkWell(
                key: ValueKey('original-rWindow$i'),
                onTap: () => setState(() => windowStyle = i),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                      width: 22,
                      height: 24,
                      child: Radio<int>(
                          value: i,
                          groupValue: windowStyle,
                          onChanged: (v) => setState(() => windowStyle = v!))),
                  Text(AppLanguage.text('窗口样式$i'),
                      style: const TextStyle(fontSize: 12))
                ]))
        ]),
      ]);

  Widget pokerWidthOption() => Row(children: [
        SizedBox(width: 24, height: 32,
            child: Checkbox(key: const ValueKey('original-cPokerBack'),
                value: pokerWidth,
                onChanged: (value) => setState(() => pokerWidth = value!))),
        Semantics(link: true, child: InkWell(
            key: const ValueKey('original-link-poker'),
            onTap: () => unawaited(ProjectFiles.openExternal(
                Uri.parse('https://tieba.baidu.com/p/5272254427'))),
            child: Text(AppLanguage.text('植吧扑克'),
                style: const TextStyle(fontSize: 12, color: Color(0xff1565c0),
                    decoration: TextDecoration.underline)))),
        Flexible(child: InkWell(
            onTap: () => setState(() => pokerWidth = !pokerWidth),
            child: Text(AppLanguage.text('等宽，否则游戏等宽'),
                style: const TextStyle(fontSize: 12)))),
      ]);

  void createMirror(double scale) => setState(() {
        mirrors.add(Formation.fromJson(s.document.toJson()));
        mirrorScales.add(scale);
        mirrorBackgrounds.add(exportBackground);
        mirrorPokerWidths.add(pokerWidth);
        mirrorPositions.add(Offset(30.0 + (mirrors.length - 1) * 32,
            30.0 + (mirrors.length - 1) * 32));
      });

  Widget classicContents() {
    if (classicTab == 3) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(AppLanguage.text('创建当前阵型的镜像窗口'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(AppLanguage.text('创建与主窗口当前阵型一样的不同比例镜像，最多同时创建三个。镜像内容只读，主窗口的修改不会影响已创建的镜像；关闭后不保存。可拖动标题移动窗口，并导出 PNG 图片。'),
            style: const TextStyle(fontSize: 12)),
        originalCheck('cMirrorBack', '显示游戏背景，否则背景透明', exportBackground,
            (v) => setState(() => exportBackground = v)),
        pokerWidthOption(),
        Wrap(children: [
          for (var i = 0; i < 6; i++)
            classicButton(
                ['创建一个1/1比例的镜像窗口', '创建一个3/4比例的镜像窗口', '创建一个2/3比例的镜像窗口', '创建一个1/2比例的镜像窗口', '创建一个3/2比例的镜像窗口', '创建一个2/1比例的镜像窗口'][i],
                mirrors.length >= 3
                    ? null
                    : () => createMirror([1.0, .75, 2 / 3, .5, 1.5, 2.0][i]),
                key: ValueKey('original-clone-$i')),
        ]),
      ]);
    }
    if (classicTab == 4) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(AppLanguage.text('1.载入和导出布阵字符串')),
        Text(AppLanguage.text('“载入”仅在本布阵器上生效，游戏布阵请使用：'),
            style: const TextStyle(fontSize: 12)),
        classicButton('PvZ Toolkit', () async {
          await ProjectFiles.openExternal(
              Uri.parse('https://pvz.lmintlcx.com/'));
        }, key: const ValueKey('original-link-toolkit')),
        const SizedBox(height: 4),
        TextField(
            controller: inputFormation,
            minLines: 4,
            maxLines: 6,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
                hintText: AppLanguage.text('粘贴 Toolkit 或网页布阵器阵型码'))),
        Wrap(children: [
          classicButton('载入', () async {
            try {
              final value = inputFormation.text.trim();
              final document = FormationExchange.decode(value);
              await navigateFormation(document, name: '载入阵型');
              clearBatchSelection();
              selectedId = null;
              fit();
            } catch (e) {
              if (mounted) message(context, '载入失败：$e');
            }
          }),
          classicButton('清空输入', inputFormation.clear)
        ]),
        const SizedBox(height: 10),
        Text(AppLanguage.text('当前阵型码（随阵图实时更新）'),
            style: const TextStyle(fontSize: 12)),
        Text(AppLanguage.text('PvZ Toolkit 阵型字符串'),
            style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        TextField(
            key: const ValueKey('formation-live-output'),
            controller: outputFormation,
            readOnly: true,
            minLines: 4,
            maxLines: 6,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
                hintText: AppLanguage.text('当前阵型暂不能生成 Toolkit 阵型码'))),
        if (outputEncodingError != null) ...[
          classicButton('一键格式化', formatForOutput,
              key: const ValueKey('formation-format')),
          Text(AppLanguage.text('后放置优先，清理冲突和不支持的内容；可撤销。'),
              style: const TextStyle(fontSize: 11, color: Color(0xff63755f))),
          Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(outputEncodingError!,
                  key: const ValueKey('formation-output-error'),
                  style:
                      const TextStyle(fontSize: 11, color: Colors.deepOrange))),
        ],
        classicButton(
            '复制',
            outputEncodingError != null
                ? null
                : () async {
                    await Clipboard.setData(
                        ClipboardData(text: outputFormation.text));
                  },
            key: const ValueKey('formation-copy')),
        const Divider(),
        Row(children: [
          Text(AppLanguage.text('输出倍率：'), style: const TextStyle(fontSize: 12)),
          AppDropdown<double>(
              value: exportRatio,
              items: const [
                DropdownMenuItem(value: 1, child: Text('1/1×')),
                DropdownMenuItem(value: .75, child: Text('3/4×')),
                DropdownMenuItem(value: 2 / 3, child: Text('2/3×')),
                DropdownMenuItem(value: .5, child: Text('1/2×'))
              ],
              onChanged: (v) => setState(() => exportRatio = v!)),
        ]),
        originalCheck('exportBackground', '显示游戏背景，否则背景透明', exportBackground,
            (v) => setState(() => exportBackground = v)),
        pokerWidthOption(),
        classicButton(generatingPng ? '正在生成…' : '生成图片',
            generatingPng ? null : generateExportPreview,
            key: const ValueKey('formation-generate-image')),
        if (generatedPng != null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300, maxHeight: 225),
              child: Image.memory(generatedPng!,
                  key: const ValueKey('formation-image-preview'),
                  fit: BoxFit.contain, gaplessPlayback: true)),
          classicButton('导出图片', () async {
            try {
              await ProjectFiles.save('${generatedPngName ?? safeName(s.name)}.png',
                  generatedPng!, 'image/png');
            } catch (e) {
              if (mounted) message(context, e);
            }
          }, key: const ValueKey('formation-export-image')),
        ],
      ]);
    }
    if (classicTab == 5) return classicSettings();
    if (classicTab == 1) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(AppLanguage.text('懒人布局')),
          classicButton(
              '?',
              () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                          content: Text(AppLanguage.text(
                              '使用带参数的网址可以直接显示阵型\n比如http://jspvz.com/ArrayDesign/?66显示3C8P阵 ')),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(AppLanguage.text('确定')))
                          ])),
              key: const ValueKey('original-help')),
        ]),
        const SizedBox(height: 6),
        mapChangeControls(const ValueKey('lazy-change-map'), label: '更换底图'),
        const SizedBox(height: 6),
        presetSelector('阵型', OriginalCatalog.formations),
        presetSelector('炮位', OriginalCatalog.cobLayouts),
        presetSelector('无炮', OriginalCatalog.gloomLayouts),
        const Divider(),
        Text(AppLanguage.text('一键布局'), style: const TextStyle(fontSize: 12)),
        Wrap(children: [
          for (final label in OriginalActions.labels)
            classicButton(label, () async {
              try {
                await navigateFormation(
                    OriginalActions.apply(s.document, label));
              } catch (e) {
                if (mounted) message(context, e);
              }
            })
        ]),
        const Divider(),
        Text(AppLanguage.text('一键模仿'), style: const TextStyle(fontSize: 12)),
        Wrap(children: [
          for (final scope in ['南瓜', '荷叶', '花盆', '非紫卡植物', '全部植物'])
            classicButton(scope, () async {
              try {
                await navigateFormation(
                    OriginalActions.imitate(s.document, scope));
              } catch (e) {
                if (mounted) message(context, e);
              }
            })
        ]),
      ]);
    }
    const plantOrder = [
      'pea',
      'sunflower',
      'cherry',
      'wallnut',
      'potato',
      'snow',
      'chomper',
      'repeater',
      'puff',
      'sunshroom',
      'fume',
      'gravebuster',
      'hypno',
      'scaredy',
      'ice',
      'doom',
      'lily',
      'squash',
      'threepea',
      'tangle',
      'jalapeno',
      'spikeweed',
      'torch',
      'tallnut',
      'seashroom',
      'plantern',
      'cactus',
      'blover',
      'splitpea',
      'starfruit',
      'pumpkin',
      'magnet',
      'cabbage',
      'pot',
      'kernel',
      'coffee',
      'garlic',
      'umbrella',
      'marigold',
      'melon',
      'gatling',
      'doubleSun',
      'gloom',
      'cattail',
      'winter',
      'goldmagnet',
      'spike',
      'cob'
    ];
    const zombieOrder = ['zombie', 'flag', 'cone', 'pole', 'bucket',
      'newspaper', 'screen', 'football', 'dancer', 'backup', 'ducky',
      'snorkel', 'zomboni', 'dolphin', 'jack', 'balloon', 'digger', 'pogo',
      'yeti', 'bungee', 'ladderZombie', 'catapult', 'gargantuar',
      'Redeyed_Gargantuar', 'imp'];
    const propOrder = ['ladder', 'grave', 'rake', 'Stripe', 'crater',
      'ScaryPot', 'SnowFlakes', 'BungeeTarget', 'Ice'];
    final ids = category == '植物' ? plantOrder
        : category == '僵尸' ? zombieOrder
        : category == '物品效果' ? propOrder : const <String>[];
    final specs = ids.map(ObjectSpec.byId).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final batch in [false, true])
            Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 24, height: 28, child: Radio<bool>(
                  key: ValueKey(batch ? 'original-rHowGrow1' : 'original-rHowGrow0'),
                  value: batch, groupValue: batchSelectionMode,
                  onChanged: (value) => setSelectionMode(value!))),
              InkWell(onTap: () => setSelectionMode(batch),
                  child: Text(AppLanguage.text(batch ? '批量选择' : '单个选择'),
                      style: const TextStyle(fontSize: 12))),
            ]),
        ])),
        if (batchSelectionMode)
          TextButton(
              key: const ValueKey('batch-toggle-selectors'),
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12)),
              onPressed: () => setState(() => batchSelectorsVisible = !batchSelectorsVisible),
              child: Text(AppLanguage.text(batchSelectorsVisible ? '隐藏行列' : '显示行列'))),
      ]),
      if (batchSelectionMode) webBatchControls(),
      if (!batchSelectionMode)
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(AppLanguage.text('铲除范围：'), style: const TextStyle(fontSize: 12)),
        AppDropdown<String>(
            value: shovelFilter,
            isDense: true,
            style: const TextStyle(fontSize: 12, color: Colors.black),
            items: ['智能', ...ObjectFilter.options]
                .map((f) => DropdownMenuItem(
                    value: f,
                    child: Text(AppLanguage.text(f == '全部' ? '本格全部' : f))))
                .toList(),
            onChanged: (v) => setState(() => shovelFilter = v!)),
        classicButton(
            '铲子', s.readOnly ? null : () => setState(() => tool = '铲除'),
            active: tool == '铲除'),
        classicButton('清空', s.readOnly ? null : clearFormation,
            key: const ValueKey('clear-formation'))
      ]),
      if (!batchSelectionMode)
        mapChangeControls(const ValueKey('original-change-map')),
      const SizedBox(height: 5),
      plantingSupportOptions(),
      const SizedBox(height: 8),
      Text(
          AppLanguage.text(
              '选卡特效：点击特效和卡片在场上进行种植，特效可多选\n模仿者/冰冻/魅惑/高亮/我是僵尸/灰烬/半透明'),
          style: const TextStyle(fontSize: 12)),
      SizedBox(
          width: 254,
          child: Row(children: [
            for (final entry in <String, String>{
              '模仿者': 'Imitater',
              '冰冻': 'Frozen',
              '魅惑': 'Charm',
              '高亮': 'Highlights',
              '阴影': 'Dropshadow',
              '灰烬': 'Ashes',
              '半透明': 'translucent'
            }.entries)
              Expanded(
                  child: Tooltip(
                      key: ValueKey('original-effect-${entry.key}'),
                      message: entry.key,
                      child: InkWell(
                          onTap: s.readOnly
                              ? null
                              : () => setState(() {
                                    if (plantingEffects.contains(entry.key)) {
                                      plantingEffects.remove(entry.key);
                                    } else {
                                      if (const {'模仿者', '阴影', '我是僵尸', '灰烬'}
                                          .contains(entry.key)) {
                                        plantingEffects.removeAll(
                                            const {'模仿者', '阴影', '我是僵尸', '灰烬'});
                                      }
                                      plantingEffects.add(entry.key);
                                    }
                                    if (entry.key == '模仿者' && tool != '放置') {
                                      selectedId = null;
                                      clearBatchSelection();
                                      tool = plantingEffects.contains('模仿者')
                                          ? '模仿'
                                          : '选择';
                                    } else if (selected != null) {
                                      changePiece(selected!
                                          .copy(effects: {...plantingEffects}));
                                    }
                                  }),
                          child: Container(
                              height: 50,
                              decoration: BoxDecoration(
                                  border: Border.all(
                                      color: plantingEffects.contains(entry.key)
                                          ? Colors.red
                                          : Colors.transparent,
                                      width: 2)),
                              child: RawImage(
                                  image: OriginalAssets.image(
                                      'image/Card/${entry.value}.png'),
                                  fit: BoxFit.fill)))))
          ])),
      Wrap(children: [
        for (final entry in const {'植物': '植物选卡', '僵尸': '僵尸选卡', '物品效果': '物品效果选卡'}.entries)
          InkWell(
              key: ValueKey('catalog-category-${entry.key}'),
              onTap: () => setState(() => category = category == entry.key ? '' : entry.key),
              child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                      color: entry.key == '植物' ? const Color(0xff008080)
                          : entry.key == '僵尸' ? const Color(0xff4b4174) : const Color(0xff755800),
                      border: Border.all(color: category == entry.key ? Colors.black54 : Colors.white70)),
                  child: Text(AppLanguage.text(entry.value),
                      style: const TextStyle(color: Colors.white, fontSize: 12))))
      ]),
      Row(children: [
        Text(AppLanguage.text('选择种植时的默认外表 '),
            style: const TextStyle(fontSize: 12)),
        SizedBox(width: 144,
            child: AppDropdown<int>(
          key: const ValueKey('original-sGrowSelect'),
          value: growMode,
          isDense: true,
          isExpanded: true,
          style: const TextStyle(fontSize: 12, color: Colors.black),
          items: List.generate(
              8,
              (i) =>
                  DropdownMenuItem(value: i, child: Text(growModeLabels[i]))),
          onChanged: s.readOnly ? null : (v) => setState(() => growMode = v!),
        )),
      ]),
      Wrap(children: [
        originalCheck('flip-horizontal', '左右翻转', plantingFlip,
            s.readOnly ? null : (value) => setState(() {
              plantingFlip = value;
              if (selected != null) changePiece(selected!.copy(flipped: value));
            })),
        originalCheck('flip-vertical', '上下翻转', plantingVertical,
            s.readOnly ? null : (value) => setState(() {
              plantingVertical = value;
              if (selected != null) changePiece(selected!.copy(flippedVertical: value));
            }))
      ]),
      if (category.isNotEmpty)
      SizedBox(height: 360, width: 300,
          child: Align(alignment: Alignment.topLeft, child: SizedBox(
              width: 290.25,
              child: GridView.count(
                  crossAxisCount: 8,
                  childAspectRatio: 36.28125 / 50,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 0,
                  crossAxisSpacing: 0,
                  children: specs.map(classicCard).toList())))),
      if (selected != null)
        classicButton('删除选中对象', s.readOnly ? null : removeSelected),
    ]);
  }

  Future<void> generateExportPreview() async {
    if (generatingPng) return;
    final target = s;
    final token = documentToken;
    final document = target.document;
    final name = safeName(target.name);
    final ratio = exportRatio, background = exportBackground, poker = pokerWidth;
    setState(() => generatingPng = true);
    try {
      final bytes = await exportPng(document,
          multiplier: ratio, background: background, pokerWidth: poker);
      if (!mounted || !identical(s, target) || documentToken != token) return;
      setState(() {
        generatedPng = bytes;
        generatedPngName = name;
      });
    } catch (e) {
      if (mounted) message(context, '生成图片失败：$e');
    } finally {
      if (mounted) setState(() => generatingPng = false);
    }
  }

  bool choosingBatchClear = false;

  Future<void> chooseBatchClear() async {
    if (s.readOnly || cells.isEmpty || choosingBatchClear) return;
    final target = s;
    final token = documentToken;
    final fingerprint = s.document.fingerprint;
    final selection = Set<(int, int)>.of(cells);
    setState(() => choosingBatchClear = true);
    try {
      final kind = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
              key: const ValueKey('batch-clear-picker'),
              title: Text(AppLanguage.text('清除指定植物')),
              content: SizedBox(width: 300,
                  child: SingleChildScrollView(child: Column(
                      mainAxisSize: MainAxisSize.min, children: [
                    for (final option in ['普通植物', '南瓜', '容器', '梯子',
                      '咖啡豆', '钉耙', '墓碑', '物品及特效', '僵尸'])
                      RadioListTile<String>(
                          key: ValueKey('batch-clear-kind-$option'),
                          value: option, groupValue: null,
                          dense: true,
                          title: Text(AppLanguage.text(option)),
                          onChanged: (value) => Navigator.pop(context, value)),
                  ]))),
              actions: [TextButton(
                  key: const ValueKey('batch-clear-cancel'),
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLanguage.text('取消')))]));
      if (kind == null || !mounted) return;
      if (!identical(s, target) || documentToken != token || target.readOnly ||
          s.document.fingerprint != fingerprint || cells.length != selection.length ||
          !selection.containsAll(cells)) {
        message(context, '主画面或选区已更新，请重新选择清除范围');
        return;
      }
      setState(() => batchShovelFilter = kind);
      batchDelete(kind);
    } finally {
      if (mounted) setState(() => choosingBatchClear = false);
    }
  }

  Widget webBatchControls() => Column(
      key: const ValueKey('web-batch-controls'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(AppLanguage.text('一键预选'), style: const TextStyle(fontSize: 12)),
          for (final label in ['陆路', '水路', '后置炮', '前置炮', '超前置炮',
            '底线炮', '水路前场', '水路56列', '重置批量选择'])
            classicButton(label, () => quickSelect(label)),
        ]),
        const SizedBox(height: 4),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(AppLanguage.text('铲除'), style: const TextStyle(fontSize: 12)),
          classicButton('清除指定植物',
              s.readOnly || cells.isEmpty || choosingBatchClear ? null : chooseBatchClear,
              key: const ValueKey('batch-clear-type')),
          classicButton('清空选中区域', s.readOnly || cells.isEmpty ? null : () => batchDelete('全部'),
              key: const ValueKey('batch-clear-selection')),
          classicButton('清空地图', s.readOnly ? null : clearFormation,
              key: const ValueKey('batch-clear-map')),
        ]),
      ]);

  Future<void> chooseAppearance({bool plantBatch = false}) async {
    final target = s;
    final token = documentToken;
    final fingerprint = target.document.fingerprint;
    final typeAtOpen = selectedType;
    bool stillCurrent() => mounted && identical(s, target) &&
        documentToken == token && s.document.fingerprint == fingerprint &&
        selectedType == typeAtOpen;
    await Future.wait([OriginalAssets.ensureLoaded(), AppLanguage.load()]);
    if (!stillCurrent()) return;
    final piece = selected;
    final type = piece?.type ?? selectedType;
    final sprite =
        OriginalAssets.sprites[OriginalAssets.names[type] ?? type] as Map?;
    final layers = (sprite?['images'] as List? ?? [])
        .whereType<Map>()
        .where((image) => !(image['path'] as String).contains('shadow'))
        .toList();
    if (layers.isEmpty) {
      if (mounted) message(context, '此对象没有可选外表');
      return;
    }
    final layer = layers.last;
    final image = OriginalAssets.image(layer['path'] as String);
    if (image == null || !mounted) return;
    final rows = (layer['rows'] as num).toInt().clamp(1, 100),
        cols = (layer['cols'] as num).toInt().clamp(1, 100);
    final value = await showDialog<(int, int)>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(
                    AppLanguage.text('${ObjectSpec.byId(type).name} · 手动选择外表')),
                content: SizedBox(
                    width: 480,
                    height: 320,
                    child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 5),
                        itemCount: rows * cols,
                        itemBuilder: (ctx, i) {
                          final row = i ~/ cols, col = i % cols;
                          return InkWell(
                              onTap: () => Navigator.pop(ctx, (row, col)),
                              child: Container(
                                  margin: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                      border: Border.all(
                                          color: (piece?.frameRow ??
                                                          plantingFrameRow) ==
                                                      row &&
                                                  (piece?.frameCol ??
                                                          plantingFrameCol) ==
                                                      col
                                              ? Colors.red
                                              : Colors.blueGrey)),
                                  child: Column(children: [
                                    Expanded(
                                        child: CustomPaint(
                                            size: const Size(76, 60),
                                            painter: _SpriteFramePainter(
                                                image,
                                                row,
                                                col,
                                                (layer['rw'] as num).toDouble(),
                                                (layer['rh'] as num)
                                                    .toDouble()))),
                                    Text('${row + 1}-${col + 1}',
                                        style: const TextStyle(fontSize: 11))
                                  ])));
                        })),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(AppLanguage.text('取消'))),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, (0, 0)),
                      child: Text(AppLanguage.text('默认外表')))
                ]));
    if (value == null || !stillCurrent()) return;
    setState(() {
      plantingFrameRow = value.$1;
      plantingFrameCol = value.$2;
    });
    if (piece != null) {
      changePiece(piece.copy(frameRow: value.$1, frameCol: value.$2));
    }
    if (plantBatch && batchSelectionMode) batchPlace();
  }

  Future<void> navigateFormation(Formation document,
      {String? name,
      String? filePath,
      String? fileFormat,
      String? lastFileBackup}) async {
    finishGesture();
    if (widget.toolboxOnly) {
      await WindowBridge.mainAction('navigateFormation', payload: {
        'document': document.toJson(),
        'name': name ?? s.name,
        'filePath': filePath,
        'fileFormat': fileFormat,
        'lastFileBackup': lastFileBackup,
        'baseFingerprint': remoteBaseFingerprint,
      });
      return;
    }
    if (widget.openSession == null) {
      // Standalone embedders retain ordinary document undo.
      s.execute('更换阵型', document, name: name);
      s.filePath = filePath;
      s.fileFormat = fileFormat;
      s.lastFileBackup = lastFileBackup;
      return;
    }
    final next =
        EditorSession(s.repository, document: document, name: name ?? s.name,
            deferInitialSave: true)
          ..filePath = filePath
          ..fileFormat = fileFormat
          ..lastFileBackup = lastFileBackup;
    try {
      formationNavigationInProgress = true;
      await widget.openSession!(next, false);
    } catch (_) {
      next.dispose();
      rethrow;
    } finally {
      formationNavigationInProgress = false;
    }
  }

  Future<void> chooseFormationPreset(String group) async {
    super.setState(() {
      classicTab = 1;
      pickingPresetGroup = group;
      if (group != '阵型') presetPickerLayoutGroup = group;
      presetPickerRows = group == '阵型'
          ? 0
          : s.document.map.rows == 6
              ? 6
              : 5;
    });
  }

  List<OriginalPreset> presetSources(String group) => group == '炮位'
      ? OriginalCatalog.cobLayouts
      : group == '无炮'
          ? OriginalCatalog.gloomLayouts
          : OriginalCatalog.formations;

  Future<void> useFormationPreset(String group, int index,
      {bool? changeMap}) async {
    final replaceMap = changeMap ?? presetChangeMap;
    try {
      if (widget.toolboxOnly) {
        await WindowBridge.mainAction('usePreset',
            payload: {'group': group, 'index': index, 'changeMap': replaceMap});
      } else {
        final source = presetSources(group).firstWhere((p) => p.index == index);
        final decoded = group == '阵型'
            ? LibraryPresets.all
                .firstWhere((p) => p.sourceIndex == index)
                .document
            : source.decode(mapId: s.document.mapId);
        final document = source.partial
            ? s.document.copy(pieces: [...s.document.pieces, ...decoded.pieces])
            : replaceMap
                ? decoded
                : decoded.copy(
                    mapId: s.document.mapId,
                    pieces: decoded.pieces
                        .where((piece) => decoded.fits(piece, s.document.map))
                        .toList());
        await navigateFormation(document, name: source.name);
      }
      if (mounted) {
        super.setState(() {
          pickingPresetGroup = null;
          classicTab = 1;
        });
      }
    } catch (e) {
      if (mounted) message(context, '打开阵型失败：$e');
    }
  }

  Widget presetPickerContents() {
    final group = presetPickerRows == 0 ? '阵型' : presetPickerLayoutGroup;
    final choices = group == '阵型'
        ? LibraryPresets.all
        : presetSources(group)
            .map((p) => LibraryPreset.layout(p, group))
            .where((p) => p.document.map.rows == presetPickerRows)
            .toList();
    return Column(key: const ValueKey('formation-preset-picker'), children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
          child: Row(children: [
            IconButton(
                key: const ValueKey('preset-picker-back'),
                tooltip: AppLanguage.text('返回布局'),
                onPressed: () =>
                    super.setState(() => pickingPresetGroup = null),
                icon: const Icon(Icons.arrow_back,
                    size: 19, color: Color(0xff376b50))),
            Expanded(
                child: Text(
                    AppLanguage.text(
                        group == '阵型' ? '预制名阵' : presetLayoutLabel(group)),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xff304b32)))),
          ])),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            for (final rows in [0, 6, 5])
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ChoiceChip(
                          key: ValueKey('preset-rows-$rows'),
                          label: Center(
                              child: Text(AppLanguage.text(rows == 0
                                  ? '阵型选择'
                                  : rows == 5
                                      ? '五行'
                                      : '六行'))),
                          selected: presetPickerRows == rows,
                          onSelected: (_) => super.setState(
                              () => presetPickerRows = rows)))),
          ])),
      Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(height: 32, child: group == '阵型' ? originalCheck(
                'preset-change-map',
                '布阵时更换地图',
                presetChangeMap,
                (value) => setState(() => presetChangeMap = value))
              : Align(alignment: Alignment.centerLeft,
                  child: Text(AppLanguage.text('局部布局'),
                      style: const TextStyle(fontSize: 12, color: Color(0xff63755f)))))),
      Expanded(
          child: LibraryBrowser(
        key: ValueKey('toolbox-preset-list-$group-$presetPickerRows'),
        drafts: const [],
        archives: const [],
        presets: choices,
        showTitle: false,
        onPresetPick: (p) =>
            unawaited(useFormationPreset(group, p.sourceIndex)),
        onRefresh: () async {},
        onNew: () {},
        onImportProject: () {},
        onImportString: () {},
        onOpenDraft: (_) {},
        onOpenArchive: (_) {},
        onDraftAction: (_, __) {},
        onArchiveAction: (_, __) {},
      )),
    ]);
  }

  String presetLayoutLabel(String group) => switch (group) {
        '炮位' => '春哥布局',
        '无炮' => '曾哥布局',
        _ => '$group布局',
      };

  Widget presetSelector(String label, List<OriginalPreset> presets) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xffdce5d5))),
          child: ListTile(
              key: ValueKey('preset-selector-$label'),
              dense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              leading: Icon(
                  label == '阵型'
                      ? Icons.grass_outlined
                      : Icons.grid_view_rounded,
                  color: const Color(0xff376b50)),
              title: Text(
                  AppLanguage.text(
                      label == '阵型' ? '阵型选择' : presetLayoutLabel(label)),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(
                  AppLanguage.text(
                      '${presets.length} 个${label == '阵型' ? '名阵，与存档库共用' : '局部布局'}'),
                  style: const TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => chooseFormationPreset(label))));

  Widget classicCard(ObjectSpec p) => Tooltip(
      key: ValueKey('original-card-${p.id}'),
      message: p.name,
      child: InkWell(
          onTap: s.readOnly
              ? null
              : () async {
                  if (!batchSelectionMode && selectedType == p.id &&
                      (tool == '放置' || tool == '模仿' && p.id == 'Imitater')) {
                    cancelPlanting();
                    return;
                  }
                  setState(() {
                    selectedId = null;
                    selectedType = p.id;
                    tool = p.id == 'Imitater' ? '模仿' : '放置';
                  });
                  if (growMode == 0) {
                    await chooseAppearance(plantBatch: batchSelectionMode);
                  } else if (batchSelectionMode) {
                    batchPlace();
                  }
                },
          child: Container(
              decoration: BoxDecoration(
                  color: (selectedType == p.id &&
                          (tool == '放置' || tool == '模仿' && p.id == 'Imitater'))
                      ? const Color(0xffffe98a)
                      : const Color(0xffd4c59c),
                  border: Border.all(
                      color: (selectedType == p.id &&
                              (tool == '放置' ||
                                  tool == '模仿' && p.id == 'Imitater'))
                          ? Colors.red
                          : const Color(0xff6b7452),
                      width: (selectedType == p.id &&
                              (tool == '放置' ||
                                  tool == '模仿' && p.id == 'Imitater'))
                          ? 2
                          : 1)),
              child: RawImage(
                  image:
                      OriginalAssets.image(OriginalAssets.cardPath(p.id).replaceFirst('assets/original/', '')),
                  fit: BoxFit.fill))));

  void panel(String title, Widget content) {
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, set) => SizedBox(
                height: MediaQuery.sizeOf(context).height * .75,
                child: Column(children: [
                  Text(AppLanguage.text(title)),
                  Expanded(
                      child: AnimatedBuilder(
                          animation: s, builder: (_, __) => content))
                ]))));
  }

  Widget toolBar(bool medium) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            for (final t in ['放置', '选择', '铲除', '批选', '平移'])
              Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                      label: Text(AppLanguage.text(t)),
                      selected: t == '批选' ? batchSelectionMode : !batchSelectionMode && tool == t,
                      onSelected: (v) {
                        if (t == '批选') { setSelectionMode(true); }
                        else { setSelectionMode(false); setState(() => tool = t); }
                      })),
            IconButton(
                onPressed: fit,
                tooltip: AppLanguage.text('适应窗口'),
                icon: const Icon(Icons.fit_screen)),
            IconButton(
                onPressed: () => zoom(.8),
                tooltip: AppLanguage.text('缩小'),
                icon: const Icon(Icons.remove)),
            IconButton(
                onPressed: () => zoom(1.25),
                tooltip: AppLanguage.text('放大'),
                icon: const Icon(Icons.add)),
            if (tool == '铲除')
              AppDropdown<String>(
                  value: shovelFilter,
                  items: ['智能', ...ObjectFilter.options]
                      .map((f) => DropdownMenuItem(
                          value: f, child: Text(AppLanguage.text('铲除：$f'))))
                      .toList(),
                  onChanged: (f) => setState(() => shovelFilter = f!)),
            if (medium) Text(AppLanguage.text('${cells.length} 格已选')),
          ])));
  Widget statusBar() => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      color: const Color(0xffe7ebe2),
      child: Text(
          AppLanguage.text(
              '${s.document.map.name} · ${s.document.pieces.length} 对象 · ${hover == null ? '点击格子' : '行 ${hover!.$1 + 1} / 列 ${hover!.$2 + 1}'} · $tool · ${cells.length} 格\n${tool == '选择' ? '点击植物切换状态；属性面板可精确选层' : tool == '平移' ? '拖动平移，双指缩放' : '单指编辑；切换“平移”后拖动画布'}'),
          style: const TextStyle(fontSize: 11)));
  void updateNativePlantingPointer(dynamic arguments) {
    final box = plantingBoardKey.currentContext?.findRenderObject();
    Offset? position;
    if (arguments is Map && box is RenderBox && box.hasSize) {
      final local = box.globalToLocal(Offset((arguments['x'] as num).toDouble(),
          (arguments['y'] as num).toDouble()));
      if ((Offset.zero & box.size).contains(local)) position = local;
    }
    updatePlantingPointer(position);
  }

  void updatePlantingPointer(Offset? position) {
    if (plantingPointer == position) return;
    super.setState(() {
      plantingPointer = position;
      hover = position == null ? null : BoardGeometry(s.document).hit(position);
    });
  }

  void toggleBoardShovel() {
    if (s.readOnly) return;
    final cancel = tool == '铲除';
    final pointer = plantingPointer;
    cancelPlanting();
    if (!cancel) {
      setState(() {
        tool = '铲除';
        plantingPointer = pointer;
      });
    }
  }

  Widget boardShovelBank() => Positioned.fromRect(
      rect: BoardPainter.shovelBankBounds,
      child: Tooltip(
          message: s.readOnly
              ? '只读阵型'
              : tool == '铲除'
                  ? '放回铲子'
                  : '使用铲子',
          child: Semantics(
              button: true,
              enabled: !s.readOnly,
              selected: tool == '铲除',
              label: '铲子',
              child: GestureDetector(
                  key: const ValueKey('board-shovel-bank'),
                  behavior: HitTestBehavior.opaque,
                  onTap: s.readOnly ? null : toggleBoardShovel,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(
                        child: RawImage(
                            image: OriginalAssets.image('image/ShovelBank.png'),
                            fit: BoxFit.fill)),
                    if (tool != '铲除' || s.readOnly)
                      Positioned(
                          left: -7,
                          top: -3,
                          width: 80,
                          height: 80,
                          child: RawImage(
                              image: OriginalAssets.image('image/Shovel.png'),
                              fit: BoxFit.fill)),
                  ])))));

  Widget boardSeedSlot(int index) => Positioned.fromRect(
      rect: BoardPainter.seedSlotBounds(index),
      child: Semantics(
          button: true,
          label: '${AppLanguage.text('返回')} ${AppLanguage.text(ObjectSpec.byId(seedSlots[index]).name)}',
          child: GestureDetector(
              key: ValueKey('board-seed-return-$index'),
              behavior: HitTestBehavior.opaque,
              onTap: s.readOnly ? null : () => removeSeedSlot(index),
              child: const SizedBox.expand())));

  Widget board() {
    final targetSession = s;
    final doc = gesture &&
            (tool == '放置' || tool == '铲除' || tool == '选择' || tool == '模仿')
        ? s.document.copy(pieces: gesturePieces)
        : s.document;
    final rendered = scalePreview == null || selectedId == null
        ? doc
        : doc.copy(
            pieces: doc.pieces
                .map(
                    (p) => p.id == selectedId ? p.copy(scale: scalePreview) : p)
                .toList());
    final size = BoardGeometry(rendered).size;
    final previewCell = plantingPointer == null
        ? null
        : BoardGeometry(rendered).hit(plantingPointer!);
    final preview = !batchSelectionMode && !s.readOnly &&
            tool == '放置' &&
            previewCell != null &&
            ObjectSpec.byId(selectedType).category == '植物' &&
            previewCell.$2 + ObjectSpec.byId(selectedType).width <=
                rendered.map.columns
        ? plantingPiece(previewCell.$1, previewCell.$2, preview: true)
        : null;
    Piece? stateHover;
    if (!s.readOnly && !batchSelectionMode && !seedChooserOpen &&
        tool == '选择' && plantingPointer != null) {
      final plants = piecesAtPointer(plantingPointer!)
          .where((p) => p.spec.category == '植物');
      if (plants.isNotEmpty && hasPlantStates(plants.first)) stateHover = plants.first;
    }
    final supportPreviews = <Piece>[];
    if (preview != null) {
      // Simulate the actual placement on a copy: previews must follow the
      // same conflicts, aquatic exclusions and per-cell base settings.
      final simulated = [...rendered.pieces];
      PlantingSupport.removeConflicts(simulated, preview);
      simulated.add(preview);
      PlantingSupport.addMissing(simulated, preview, rendered.map,
          autoLily: autoLily, potMode: autoPotMode);
      final existingIds = rendered.pieces.map((p) => p.id).toSet();
      supportPreviews.addAll(simulated.where((p) =>
          p.id != preview.id &&
          PlantingSupport.isBase(p) &&
          !existingIds.contains(p.id)));
    }
    return LayoutBuilder(builder: (ctx, c) {
      viewport = Size(c.maxWidth, c.maxHeight);
      if (!fitted) {
        fitted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => fit());
      }
      return ClipRect(
          child: ColoredBox(
              color: const Color(0xffdce3d7),
              child: InteractiveViewer(
                  transformationController: transform,
                  constrained: false,
                  minScale: .15,
                  maxScale: 5,
                  boundaryMargin: const EdgeInsets.all(1000),
                  panEnabled: tool == '平移',
                  scaleEnabled: tool == '平移',
                  child: MouseRegion(
                      cursor: stateHover != null ? SystemMouseCursors.click : MouseCursor.defer,
                      onEnter: (e) => updatePlantingPointer(e.localPosition),
                      onExit: (_) => updatePlantingPointer(null),
                      onHover: (e) => updatePlantingPointer(e.localPosition),
                      child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (d) {
                            updatePlantingPointer(d.localPosition);
                            if (seedChooserOpen) return;
                            if (rendered.display['阳光'] == true &&
                                BoardPainter.sunValueBounds
                                    .contains(d.localPosition)) return;
                            canvasFocus.requestFocus();
                            if (rendered.display['卡槽'] == true &&
                                (BoardPainter.shovelBankBounds
                                        .contains(d.localPosition) ||
                                    List.generate(
                                            10, BoardPainter.seedSlotBounds)
                                        .any((rect) =>
                                            rect.contains(d.localPosition)))) {
                              return;
                            }
                            if (batchSelectionMode) return;
                            if (d.buttons == 2) {
                              resetPlantState(d.localPosition);
                              return;
                            }
                            if (tool != '平移' &&
                                editingPointer == null &&
                                d.buttons == 1) {
                              editingPointer = d.pointer;
                              beginGesture(d.localPosition);
                            }
                          },
                          onPointerMove: (d) {
                            updatePlantingPointer(d.localPosition);
                            if (editingPointer == d.pointer) {
                              touch(d.localPosition);
                            }
                          },
                          onPointerUp: (d) {
                            if (editingPointer == d.pointer) {
                              editingPointer = null;
                              finishGesture();
                            }
                          },
                          onPointerCancel: (d) {
                            if (editingPointer == d.pointer) {
                              editingPointer = null;
                              finishGesture();
                            }
                          },
                          child: SizedBox.fromSize(
                              size: size,
                              child: Stack(clipBehavior: Clip.none, children: [
                                Positioned.fill(
                                    child: CustomPaint(
                                        key: plantingBoardKey,
                                        painter: BoardPainter(
                                            document: rendered,
                                            paintSunValue: false,
                                            plantingPreview: preview,
                                            plantingSupportPreviews:
                                                supportPreviews,
                                            plantingPosition: plantingPointer,
                                            shovelTargetIds: !s.readOnly &&
                                                    tool == '铲除' &&
                                                    plantingPointer != null
                                                ? shovelTargets(
                                                    plantingPointer!)
                                                : const {},
                                            growthEffects: growthEffects,
                                            selectedCells: batchSelectionMode ? const {} : cells,
                                            selectedId: selectedId,
                                            stateHoverId: stateHover?.id))),
                                if (rendered.display['卡槽'] == true)
                                  boardShovelBank(),
                                if (rendered.display['阳光'] == true)
                                  Positioned.fromRect(
                                      rect: BoardPainter.sunValueBounds,
                                      child: BoardSunEditor(
                                          key: ValueKey('board-sun-${s.id}'),
                                          value: rendered.sunValue,
                                          readOnly: s.readOnly,
                                          onChanged: (value) {
                                            if (!identical(s, targetSession) ||
                                                targetSession.readOnly) return;
                                            finishGesture();
                                            targetSession.execute(
                                                '修改阳光',
                                                targetSession.document
                                                    .copy(sunValue: value));
                                          })),
                                if (rendered.display['卡槽'] == true && seedChooserOpen)
                                  for (var i = 0; i < seedSlots.length; i++) boardSeedSlot(i),
                                if (batchSelectionMode && batchSelectorsVisible)
                                  Positioned.fill(child: BatchSelectionOverlay(
                                      document: rendered,
                                      selectedRows: batchRows,
                                      selectedColumns: batchColumns,
                                      onRowsChanged: (rows) => updateBatchSelection(rows, {...batchColumns}),
                                      onColumnsChanged: (columns) => updateBatchSelection({...batchRows}, columns))),
                                // Transient cursor feedback must paint above
                                // both the board and its interactive HUD.
                                if (!s.readOnly &&
                                    tool == '铲除' &&
                                    plantingPointer != null)
                                  Positioned(
                                      left: (plantingPointer!.dx - 12)
                                          .clamp(0.0, size.width - 64),
                                      top: (plantingPointer!.dy - 55)
                                          .clamp(0.0, size.height - 64),
                                      width: 64,
                                      height: 64,
                                      child: IgnorePointer(
                                          child: RawImage(
                                              key: const ValueKey(
                                                  'board-shovel-cursor'),
                                              image: OriginalAssets.image(
                                                  'image/Shovel.png'),
                                              fit: BoxFit.fill,
                                              filterQuality:
                                                  FilterQuality.medium))),
                              ])))))));
    });
  }

  Widget palette() => StatefulBuilder(
      builder: (ctx, set) => Container(
          color: Colors.white,
          child: Column(children: [
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(AppLanguage.text('对象素材'),
                    style: const TextStyle(fontWeight: FontWeight.bold))),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextField(
                    decoration: InputDecoration(
                        labelText: AppLanguage.text('搜索对象'),
                        prefixIcon: const Icon(Icons.search)),
                    onChanged: (v) {
                      setState(() => search = v);
                      set(() {});
                    })),
            Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(spacing: 4, children: [
                  for (final c in ['植物', '僵尸', '物品', '特效'])
                    ChoiceChip(
                        label: Text(AppLanguage.text(c)),
                        selected: category == c,
                        onSelected: (_) {
                          setState(() => category = c);
                          set(() {});
                        })
                ])),
            Expanded(
                child: ListView(
                    children: ObjectSpec.all
                        .where((p) =>
                            p.category == category && p.name.contains(search))
                        .map((p) => ListTile(
                            dense: true,
                            selected: (selectedType == p.id &&
                                (tool == '放置' ||
                                    tool == '模仿' && p.id == 'Imitater')),
                            leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: Color(p.color),
                                child: Text(p.name.substring(0, 1),
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.black87))),
                            title: Text(AppLanguage.text(p.name)),
                            subtitle: p.width > 1
                                ? Text(AppLanguage.text('占 ${p.width} 格'))
                                : null,
                            onTap: s.readOnly
                                ? null
                                : () {
                                    setState(() {
                                      selectedType = p.id;
                                      tool = p.id == 'Imitater' ? '模仿' : '放置';
                                    });
                                    set(() {});
                                  }))
                        .toList())),
            Padding(
                padding: const EdgeInsets.all(8),
                child: Text(AppLanguage.text('可自由叠放；没有强制游戏种植限制。'),
                    style:
                        const TextStyle(fontSize: 11, color: Colors.black54)))
          ])));
  Widget properties() => StatefulBuilder(
      builder: (ctx, set) =>
          ListView(padding: const EdgeInsets.all(12), children: [
            Text(AppLanguage.text('地图与显示'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            AppDropdown<String>(
                value: s.document.mapId,
                isExpanded: true,
                items: BoardMap.all
                    .map((m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(
                            '${AppLanguage.text(m.name)} ${m.rows}×${m.columns}')))
                    .toList(),
                onChanged: s.readOnly
                    ? null
                    : (v) async {
                        await changeMap(BoardMap.byId(v!));
                        set(() {});
                      }),
            Row(children: [
              Text(AppLanguage.text('迷雾列数：')),
              AppDropdown<int>(
                  value: s.document.fogColumns,
                  items: List.generate(
                      11, (i) => DropdownMenuItem(value: i, child: Text('$i'))),
                  onChanged: s.readOnly
                      ? null
                      : (v) {
                          s.execute('设置迷雾', s.document.copy(fogColumns: v));
                          set(() {});
                        })
            ]),
            for (final entry in s.document.display.entries)
              SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.key),
                  value: entry.value,
                  onChanged: s.readOnly
                      ? null
                      : (v) {
                          s.execute(
                              '显示设置',
                              s.document.copy(display: {
                                ...s.document.display,
                                entry.key: v
                              }));
                          set(() {});
                        }),
            TextButton(
                onPressed: s.readOnly
                    ? null
                    : () async {
                        final text = await textPrompt(
                            context, '阳光数值（0–99999999）',
                            initial: '${s.document.sunValue}');
                        if (text == null) return;
                        final value = int.tryParse(text);
                        if (value == null || value < 0 || value > 99999999) {
                          if (mounted) message(context, '请输入范围内的整数');
                          return;
                        }
                        s.execute('修改阳光', s.document.copy(sunValue: value));
                        set(() {});
                      },
                child: Text(AppLanguage.text('阳光数值：${s.document.sunValue}'))),
            const Divider(),
            Text(AppLanguage.text('选中对象与图层'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            if (selected == null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(AppLanguage.text('使用“选择”点击对象；同格可逐层选择。'))),
            if (selected != null) ...pieceProperties(selected!, set),
            if (hover != null)
              ...at(hover!).map((p) => ListTile(
                  dense: true,
                  selected: p.id == selectedId,
                  title: Text(AppLanguage.text(p.spec.name)),
                  subtitle: Text(AppLanguage.text(
                      '层 ${p.layer} · 行 ${p.row + 1} 列 ${p.col + 1}')),
                  onTap: () {
                    setState(() => selectedId = p.id);
                    set(() {});
                  })),
            const Divider(),
            Text(AppLanguage.text('本地示例（新增设计）')),
            for (final name in LocalLayouts.stamps.keys)
              TextButton(
                  onPressed: s.readOnly
                      ? null
                      : () {
                          try {
                            s.execute(
                                '局部布局',
                                LocalLayouts.apply(s.document, name,
                                    hover?.$1 ?? 0, hover?.$2 ?? 0));
                            set(() {});
                          } catch (e) {
                            message(context, e);
                          }
                        },
                  child: Text(AppLanguage.text('在当前格插入$name'))),
            for (final p in ['泳池练习', '草地练习'])
              TextButton(
                  onPressed: s.readOnly
                      ? null
                      : () async {
                          {
                            await navigateFormation(preset(p), name: p);
                            clearBatchSelection();
                            selectedId = null;
                            fit();
                            set(() {});
                          }
                        },
                  child: Text(p)),
            TextButton(
                onPressed: s.readOnly
                    ? null
                    : () {
                        final spec = ObjectSpec.byId(selectedType);
                        final out = List<Piece>.of(s.document.pieces);
                        for (var r = 0; r < s.document.map.rows; r++) {
                          for (var c = 0;
                              c + spec.width <= s.document.map.columns;
                              c += spec.width) {
                            out.add(Piece(
                                id: newId(),
                                type: spec.id,
                                row: r,
                                col: c,
                                layer: spec.layer));
                          }
                        }
                        if (out.length <= 5000) {
                          s.execute('一键填充', s.document.copy(pieces: out));
                        }
                      },
                child: Text(AppLanguage.text('当前对象填满棋盘'))),
            Text(AppLanguage.text('效果、外表与卡槽自动保存到当前存档。'),
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ]));
  List<Widget> pieceProperties(Piece p, StateSetter set) => [
        Text(AppLanguage.text('${p.spec.name} · 占 ${p.spec.width} 格')),
        SwitchListTile(
            title: Text(AppLanguage.text('水平翻转')),
            value: p.flipped,
            onChanged: s.readOnly
                ? null
                : (v) {
                    changePiece(p.copy(flipped: v));
                    set(() {});
                  }),
        SwitchListTile(
            title: Text(AppLanguage.text('上下翻转')),
            value: p.flippedVertical,
            onChanged: s.readOnly
                ? null
                : (v) {
                    changePiece(p.copy(flippedVertical: v));
                    set(() {});
                  }),
        Text(AppLanguage.text(
            '缩放 ${(scalePreview ?? p.scale).toStringAsFixed(2)}')),
        Slider(
            value: scalePreview ?? p.scale,
            min: .25,
            max: 3,
            divisions: 11,
            onChanged: s.readOnly
                ? null
                : (v) {
                    setState(() => scalePreview = v);
                    set(() {});
                  },
            onChangeEnd: s.readOnly
                ? null
                : (v) {
                    changePiece(p.copy(scale: v));
                    setState(() => scalePreview = null);
                    set(() {});
                  }),
        AppDropdown<String>(
            value: p.appearance,
            items: ['默认', '轮廓']
                .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                .toList(),
            onChanged: s.readOnly
                ? null
                : (v) {
                    changePiece(p.copy(appearance: v));
                    set(() {});
                  }),
        Wrap(
            spacing: 4,
            children: Piece.allowedEffects
                .map((e) => FilterChip(
                    label: Text(AppLanguage.text(e)),
                    selected: p.effects.contains(e),
                    onSelected: s.readOnly
                        ? null
                        : (v) {
                            final effects = {...p.effects};
                            v ? effects.add(e) : effects.remove(e);
                            changePiece(p.copy(effects: effects));
                            set(() {});
                          }))
                .toList()),
        Row(children: [
          IconButton(
              onPressed: s.readOnly || p.layer <= -1000
                  ? null
                  : () {
                      changePiece(p.copy(layer: p.layer - 1));
                      set(() {});
                    },
              icon: const Icon(Icons.arrow_downward)),
          Text(AppLanguage.text('层 ${p.layer}')),
          IconButton(
              onPressed: s.readOnly || p.layer >= 1000
                  ? null
                  : () {
                      changePiece(p.copy(layer: p.layer + 1));
                      set(() {});
                    },
              icon: const Icon(Icons.arrow_upward)),
          IconButton(
              onPressed: s.readOnly
                  ? null
                  : () {
                      removeSelected();
                      set(() {});
                    },
              tooltip: AppLanguage.text('删除这一层'),
              icon: const Icon(Icons.delete_outline))
        ]),
      ];
}

class _SpriteFramePainter extends CustomPainter {
  final ui.Image image;
  final int row, col;
  final double frameWidth, frameHeight;
  _SpriteFramePainter(
      this.image, this.row, this.col, this.frameWidth, this.frameHeight);
  @override
  void paint(Canvas canvas, Size size) {
    final source = Rect.fromLTWH(
        col * frameWidth, row * frameHeight, frameWidth, frameHeight);
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    canvas.drawImageRect(
        image,
        source,
        Alignment.center.inscribe(fitted.destination, Offset.zero & size),
        Paint());
  }

  @override
  bool shouldRepaint(covariant _SpriteFramePainter old) =>
      old.image != image || old.row != row || old.col != col;
}
