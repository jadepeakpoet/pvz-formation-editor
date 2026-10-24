// Real flutter_tester UI harness; native windows are verified separately.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'parity_support.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/main.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/library/library_browser.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

Size desktopSize = const Size(900, 600);

class DesktopBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      ParityMessenger(super.createBinaryMessenger());
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(logicalConstraints: BoxConstraints.tight(desktopSize), physicalConstraints: BoxConstraints.tight(desktopSize), devicePixelRatio: 1);
}

void walk(Element e, void Function(Element) f) {
  f(e);
  e.visitChildren((c) => walk(c, f));
}

Element? keyed(String key) {
  Element? found;
  walk(WidgetsBinding.instance.rootElement!, (e) {
    if (e.widget.key == ValueKey(key)) found = e;
  });
  return found;
}

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 350));
Future<void> rawTap(String key) async {
  final element = keyed(key);
  check(element != null, 'Missing $key');
  await Scrollable.ensureVisible(element!,
      duration: Duration.zero, alignment: .5);
  await settle();
  final box = keyed(key)?.renderObject as RenderBox?;
  check(box != null, 'Missing $key');
  final p = box!.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: p, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 1, position: p));
  await settle();
}

Future<void> tap(String key) async {
  if (key.startsWith('library-map-') || key.startsWith('library-cannon-')) {
    if (keyed('library-filter-apply') == null) {
      await rawTap('library-filter-toggle');
    }
    await rawTap(key);
    await rawTap('library-filter-apply');
  } else {
    await rawTap(key);
  }
}

Future<void> main() async {
  final binding = DesktopBinding();
  String clipboard = '';
  ParityBinding.handlers[SystemChannels.platform.name] = (call) async {
    if (call.method == 'Clipboard.setData') {
      clipboard = (call.arguments as Map)['text'] as String;
    }
    return null;
  };
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  final report = <String>[];
  final dir = await Directory.systemTemp.createTemp('pvz-library-smoke-');
  var repo = await FormationRepository.open('${dir.path}/library.sqlite');
  final opened = <EditorSession>[];
  final boundary = GlobalKey();
  try {
    await OriginalAssets.ensureLoaded();
    await repo.saveArchive(
        id: 'archive-one',
        name: '泳池八炮',
        document: Formation().toJson(),
        note: '测试备注',
        tags: ['泳池']);
    await repo.saveArchive(
        id: 'archive-two',
        name: '屋顶收藏',
        document: Formation(mapId: 'roof').toJson());
    final draft = EditorSession(repo, name: '未完成草稿');
    draft.rename('未完成草稿 A');
    await draft.flush();
    draft.dispose();
    await repo.close();
    repo = await FormationRepository.open('${dir.path}/library.sqlite');
    runApp(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: LibraryPage(
                repository: repo,
                onOpenSession: (session) async {
                  opened.add(session);
                }))));
    await settle();
    await settle();
    await tap('library-section-我的存档');
    check(keyed('library-item-archive:archive-one') != null,
        'Archive fixture listed');
    check(keyed('library-item-draft:${draft.id}') == null,
        'Own archive section excludes drafts');
    report.add('archive and draft listing');
    await tap('library-item-archive:archive-one');
    check(keyed('library-detail-name') != null, 'Selection details visible');
    await tap('library-open-current');
    check(!opened.last.readOnly && opened.last.sourceArchiveId == 'archive-one',
        'Current tab opens editable working copy of exact archive');
    await tap('library-copy-code');
    check(clipboard == FormationExchange.encode(Formation()),
        'Archive copy contains Toolkit only');
    report.add('archive selection, editable current-tab open and Toolkit copy');
    check(keyed('library-favorite') == null && keyed('library-section-收藏') == null,
        'Favorite controls stay hidden');
    await repo.updateArchiveMetadata('archive-one', favorite: true);
    await repo.listArchives();
    check((await repo.listArchives()).firstWhere((a) => a.id == 'archive-one').favorite,
        'Legacy favorite metadata remains preserved');
    report.add('favorite controls hidden while metadata remains compatible');
    check(keyed('library-section-工作草稿') == null,
        'Legacy draft section remains removed');
    await tap('library-section-我的存档');
    check(keyed('library-item-archive:${draft.id}') != null,
        'Legacy draft migrated into own archives');
    await tap('library-item-archive:${draft.id}');
    await tap('library-open-current');
    check(!opened.last.readOnly && opened.last.sourceArchiveId == draft.id,
        'Migrated draft opens editable archive copy');
    await tap('library-copy-code');
    check(clipboard == FormationExchange.encode(Formation()),
        'Migrated draft copy contains Toolkit only');
    check((await repo.listDrafts()).isEmpty,
        'Migration leaves no hidden legacy drafts');
    report.add('legacy draft migrated, editable archive open and Toolkit copy');
    await tap('library-section-我的存档');
    final field = keyed('library-search')!.widget as TextField;
    field.onChanged!('测试备注');
    await settle();
    check(
        keyed('library-item-archive:archive-one') != null &&
            keyed('library-item-archive:archive-two') == null,
        'Search includes notes');
    field.onChanged!('未完成草稿 A');
    await settle();
    check(
        keyed('library-item-archive:${draft.id}') != null &&
            keyed('library-item-archive:archive-one') == null,
        'Search matches migrated draft archive name');
    field.onChanged!('不存在的阵型');
    await settle();
    check(keyed('library-item-archive:archive-one') == null,
        'Empty search results');
    field.onChanged!('');
    await settle();
    report.add('search archive notes, migrated names and empty results');
    await tap('library-section-预制名阵');
    LibraryBrowser browser() {
      LibraryBrowser? result;
      walk(WidgetsBinding.instance.rootElement!, (e) {
        if (e.widget is LibraryBrowser) result = e.widget as LibraryBrowser;
      });
      return result!;
    }

    check(browser().presets.length == 363,
        'All363 source presets supplied to real UI');
    check(
        (keyed('library-results')!.widget as ListView)
                .childrenDelegate
                .estimatedChildCount ==
            364,
        'All363 preset list entries available');
    final preset = LibraryPresets.all.first;
    (keyed('library-search')!.widget as TextField).onChanged!(preset.name);
    await settle();
    final firstKey = 'library-item-preset:${preset.id}';
    await tap(firstKey);
    check(keyed('library-add-preset') != null,
        'Builtin details offer copy action');
    final countBefore = (await repo.listArchives()).length,
        opensBefore = opened.length;
    await tap('library-add-preset');
    final copied =
        (await repo.listArchives()).singleWhere((a) => a.name == preset.name);
    check((await repo.listArchives()).length == countBefore + 1,
        'Copy persisted new own archive');
    check(jsonEncode(copied.document) == jsonEncode(preset.document.toJson()),
        'Copied source document exact');
    check(opened.length == opensBefore, 'Copy does not open main editor');
    check(browser().presets.length == 363, 'Copy preserves full builtins');
    report.add(
        '363 builtin list, source thumbnail selection, copy persists exact document without opening editor');
    (keyed('library-search')!.widget as TextField).onChanged!('');
    await settle();
    check(keyed('library-filters-panel') == null,
        'Filters are collapsed by default');
    await rawTap('library-filter-toggle');
    await rawTap('library-map-roof');
    check(keyed(firstKey) != null,
        'Staged filters do not change the live result list');
    await rawTap('library-filter-cancel');
    check(keyed(firstKey) != null && keyed('library-filters-panel') == null,
        'Cancel closes dialog without applying staged scene');
    await rawTap('library-filter-toggle');
    check((keyed('library-map-all')!.widget as ChoiceChip).selected,
        'Reopening restores applied conditions instead of canceled draft');
    await rawTap('library-map-roof');
    await rawTap('library-filter-reset');
    check(
        (keyed('library-map-all')!.widget as ChoiceChip).selected &&
            (keyed('library-cannon-all')!.widget as ChoiceChip).selected,
        'Reset changes staged scene and cannon values');
    await rawTap('library-filter-apply');
    check(keyed(firstKey) != null,
        'Applying reset restores unfiltered search result');
    report.add(
        'modal staging, cancel, reopening, staged reset and explicit apply');
    (keyed('library-search')!.widget as TextField).onChanged!('');
    await settle();
    await tap('library-map-roof');
    check(keyed(firstKey) == null, 'Builtin map filter excludes pool');
    await tap(keyed('library-clear-map-filter') != null
        ? 'library-clear-map-filter'
        : 'library-clear-filters');
    check(keyed(firstKey) != null, 'Empty map reset restores matching preset');
    (keyed('library-search')!.widget as TextField).onChanged!('');
    await settle();
    await tap('library-map-roof');
    final roof = LibraryPresets.all.firstWhere((p) => p.mapId == 'roof');
    (keyed('library-search')!.widget as TextField).onChanged!(roof.name);
    await settle();
    check(keyed('library-item-preset:${roof.id}') != null,
        'Builtin map filter includes roof');
    await tap('library-map-all');
    (keyed('library-search')!.widget as TextField).onChanged!(preset.name);
    await settle();
    check(keyed(firstKey) != null, 'All maps reset restores builtin');
    await tap('library-section-我的存档');
    (keyed('library-search')!.widget as TextField).onChanged!('');
    await settle();
    await tap('library-map-roof');
    check(
        keyed('library-item-archive:archive-two') != null &&
            keyed('library-item-archive:archive-one') == null,
        'Own archives map filter');
    await tap('library-map-all');
    await settle();
    final ownSearch = keyed('library-search')!.widget as TextField;
    ownSearch.onChanged!(preset.name);
    await settle();
    check(keyed('library-item-archive:${copied.id}') != null,
        'Copied preset searchable in own archives');
    ownSearch.onChanged!('');
    await settle();
    report.add(
        'builtin and own map filters with all reset, copied archive searchable');
    await tap('library-cannon-0');
    check(keyed('library-item-archive:archive-one') != null,
        'Misleading name 八炮 must still count actual zero cob plants');
    await tap('library-map-roof');
    check(
        keyed('library-item-archive:archive-two') != null &&
            keyed('library-item-archive:archive-one') == null,
        'Own scene and cannon filters combine');
    await tap('library-clear-filters');
    await tap('library-section-预制名阵');
    final cobPreset = LibraryPresets.all.firstWhere((p) =>
        p.mapId == 'pool' &&
        p.document.pieces.where((piece) => piece.type == 'cob').length >= 2);
    final cobCount =
        cobPreset.document.pieces.where((piece) => piece.type == 'cob').length;
    (keyed('library-search')!.widget as TextField).onChanged!(cobPreset.name);
    await settle();
    await tap('library-map-pool');
    await tap('library-cannon-$cobCount');
    check(keyed('library-item-preset:${cobPreset.id}') != null,
        'Scene, actual cannon count and search intersect');
    await rawTap('library-filter-toggle');
    final cannonTexts = <String>[];
    walk(keyed('library-cannon-$cobCount')!, (e) {
      if (e.widget is Text) cannonTexts.add((e.widget as Text).data ?? '');
    });
    check(cannonTexts.contains('$cobCount炮') && cannonTexts.contains('1阵'),
        'Cannon label and matching formation-count badge are distinct');
    check((keyed('library-filter-count')!.widget as Text).data == '匹配 1 个阵型',
        'Dialog gives separate overall matching formation count');
    check(keyed('library-map-roof') == null,
        'Zero-match scene choices must be hidden');
    await rawTap('library-filter-cancel');
    await tap('library-clear-filters');
    check(
        keyed('library-item-preset:${cobPreset.id}') != null &&
            (keyed('library-results')!.widget as ListView)
                    .childrenDelegate
                    .estimatedChildCount ==
                2,
        'Clearing both filters restores the single search-matching result');
    (keyed('library-search')!.widget as TextField).onChanged!('');
    await settle();
    report.add(
        'combined scene/cannon/search filters, actual cob counts, hidden zero-match choices and independent reset');
    await tap('library-section-我的存档');
    await tap('library-new');
    check(!opened.last.readOnly && opened.last.id != draft.id,
        'New session has separate identity');
    report.add('new formation');
    // Let the successful-copy snackbar expire before recording review images.
    await Future<void>.delayed(const Duration(seconds: 4));
    for (final size in [const Size(900, 600), const Size(800, 540)]) {
      desktopSize = size;
      binding.handleMetricsChanged();
      await settle();
      check(errors.isEmpty,
          'Layout errors at $size: ${errors.map((e) => e.exceptionAsString()).join('\n')}');
      final image = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${Directory.systemTemp.path}/pvz-library-compact-${size.width.toInt()}.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      if (size.width == 900) {
        await File('${Directory.systemTemp.path}/pvz-library-compact.png')
            .writeAsBytes(bytes.buffer.asUint8List());
      }
      image.dispose();
      await tap('library-section-预制名阵');
      final presetImage = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      final presetBytes =
          await presetImage.toByteData(format: ui.ImageByteFormat.png);
      await File('${Directory.systemTemp.path}/pvz-library-builtins-${size.width.toInt()}.png')
          .writeAsBytes(presetBytes!.buffer.asUint8List());
      presetImage.dispose();
      await rawTap('library-filter-toggle');
      await rawTap('library-map-pool');
      await rawTap('library-cannon-$cobCount');
      final filterImage = await (boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary)
          .toImage();
      final filterBytes =
          await filterImage.toByteData(format: ui.ImageByteFormat.png);
      await File('${Directory.systemTemp.path}/pvz-library-filters-${size.width.toInt()}.png')
          .writeAsBytes(filterBytes!.buffer.asUint8List());
      filterImage.dispose();
      await rawTap('library-filter-cancel');
      await tap('library-section-我的存档');
      report.add(
          'no layout/paint errors at ${size.width.toInt()}x${size.height.toInt()}');
    }
    await File('${Directory.systemTemp.path}/pvz-library-compact-report.json')
        .writeAsString(jsonEncode({
      'pass': report,
      'errors': errors.map((e) => e.exceptionAsString()).toList(),
      'scope':
          'real headless Flutter engine; LibraryPage repository integration; no native window assertion'
    }));
    stdout.writeln('PASS ${report.length}: ${report.join('; ')}');
    for (final session in opened) {
      session.dispose();
    }
    await repo.close();
    await dir.delete(recursive: true);
    exit(0);
  } catch (e, stack) {
    stderr.writeln('$e\n$stack');
    for (final error in errors) {
      stderr.writeln(error.exceptionAsString());
    }
    exit(1);
  }
}
