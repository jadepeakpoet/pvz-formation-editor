// Real headless Flutter UI; missing windows plugin intentionally exercises fallback.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_browser.dart';
import 'package:pvz_formation_editor/main.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

class FallbackBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      ParityMessenger(super.createBinaryMessenger());
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(logicalConstraints: BoxConstraints.tight(Size(1800, 900)), physicalConstraints: BoxConstraints.tight(Size(1800, 900)), devicePixelRatio: 1);
}

void check(bool ok, String reason) {
  if (!ok) throw StateError(reason);
}

List<Element> elements(bool Function(Widget) predicate, {bool onstage = true}) {
  final found = <Element>[];
  void visit(Element e) {
    if (predicate(e.widget)) found.add(e);
    if (onstage) {
      e.debugVisitOnstageChildren(visit);
    } else {
      e.visitChildren(visit);
    }
  }

  visit(WidgetsBinding.instance.rootElement!);
  return found;
}

Element? keyed(String key, {bool onstage = true}) {
  final found = elements((w) => w.key == ValueKey(key), onstage: onstage);
  return found.isEmpty ? null : found.single;
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 250));
Future<void> tap(String key) async {
  final target = keyed(key);
  check(target != null, 'missing visible $key');
  await Scrollable.ensureVisible(target!,
      duration: Duration.zero, alignment: .5);
  await settle();
  final box = keyed(key)?.renderObject as RenderBox?;
  check(box != null && box.hasSize, 'unlaid $key');
  final point = box!.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 42, position: point, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 42, position: point));
  await settle();
}

EditableTextState searchState() {
  final target = keyed('library-search', onstage: false)!;
  EditableTextState? found;
  void visit(Element e) {
    if (e is StatefulElement && e.state is EditableTextState) {
      found = e.state as EditableTextState;
    }
    e.visitChildren(visit);
  }

  visit(target);
  return found!;
}

Future<void> typeSearch(String value) async {
  await tap('library-search');
  searchState().updateEditingValue(TextEditingValue(
      text: value, selection: TextSelection.collapsed(offset: value.length)));
  await settle();
}

bool selectedMode(String mode) =>
    (keyed('main-sidebar-selection-$mode')!.widget as Semantics)
        .properties
        .selected ==
    true;
void expectMode(String? mode) {
  check(
      selectedMode('toolbox') == (mode == 'toolbox') &&
          selectedMode('library') == (mode == 'library'),
      'mutuallyexclusive highlight expected $mode');
}

void immediateTap(String key, int pointer) {
  final box = keyed(key)!.renderObject as RenderBox;
  final point = box.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: pointer, position: point, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: pointer, position: point));
}

Future<void> backToList() async {
  if (keyed('library-detail-back') != null) await tap('library-detail-back');
  check(keyed('library-narrow-list') != null, 'visible narrowlist');
}

ScrollableState listScrollable() {
  ScrollableState? result;
  void visit(Element e) {
    if (result == null && e is StatefulElement && e.state is ScrollableState) {
      result = e.state as ScrollableState;
    }
    e.visitChildren(visit);
  }

  visit(keyed('library-results')!);
  return result!;
}

Future<void> applyPoolFilter() async {
  await tap('library-filter-toggle');
  await tap('library-map-pool');
  await tap('library-cannon-2');
  await tap('library-filter-apply');
}

Future<void> main() async {
  FallbackBinding();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  final rows = <Map<String, dynamic>>[];
  final screenshots = <String>[];
  GlobalKey? boundaryForCapture;
  Future<void> captureLibrary(String name) async {
    final full = boundaryForCapture!.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final image = await full.toImage();
    final library =
        elements((w) => w is LibraryBrowser).single.renderObject as RenderBox;
    final origin = library.localToGlobal(Offset.zero);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
        image, origin & library.size, Offset.zero & library.size, Paint());
    final picture = recorder.endRecording();
    final crop = await picture.toImage(
        library.size.width.ceil(), library.size.height.ceil());
    final bytes = await crop.toByteData(format: ui.ImageByteFormat.png);
    final path = '/tmp/pvz-sidebar-fallback-$name.png';
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    screenshots.add(path);
    crop.dispose();
    picture.dispose();
    image.dispose();
  }

  Future<void> test(String id, Future<void> Function() body) async {
    final start = errors.length;
    try {
      await body();
      check(errors.length == start,
          'Flutter errors: ${errors.skip(start).map((e) => e.exception).join('; ')}');
      rows.add({'id': id, 'status': 'pass'});
    } catch (e, s) {
      rows.add({'id': id, 'status': 'fail', 'error': '$e', 'stack': '$s'});
    }
  }

  final dir = await Directory.systemTemp.createTemp('pvz-sidebar-fallback-');
  final repo = await FormationRepository.open('${dir.path}/formations.sqlite');
  final boundary = GlobalKey();
  boundaryForCapture = boundary;
  final tabs = EditorTabsController(repo);
  try {
    await OriginalAssets.ensureLoaded();
    await repo.saveArchive(
        id: 'pool-two',
        name: '泳池小阵',
        document: Formation(pieces: [
          Piece(id: 'cob-a', type: 'cob', row: 0, col: 0, layer: 10),
          Piece(id: 'cob-b', type: 'cob', row: 1, col: 0, layer: 10)
        ]).toJson());
    await repo.saveArchive(
        id: 'roof-none',
        name: '屋顶小阵',
        document: Formation(mapId: 'roof').toJson());
    for (var i = 0; i < 24; i++) {
      await repo.saveArchive(
          id: 'scroll-$i',
          name: '滚动存档 ${i.toString().padLeft(2, '0')}',
          document: Formation(mapId: 'day').toJson());
    }
    runApp(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: EditorWorkspace(
                controller: tabs,
                libraryPath: '${dir.path}/formations.sqlite',
                continueArchive: (_) async {}))));
    await settle();
    await settle();
    await test('fallback-start-and-blank-not-persisted', () async {
      check(
          keyed('main-sidebar-library') != null &&
              keyed('main-sidebar-toolbox') != null,
          'mainbar both modebuttons');
      check(
          keyed('sidebar-mode-library') == null &&
              keyed('sidebar-mode-toolbox') == null,
          'no duplicate sidebar modeheader');
      expectMode('toolbox');
      check((await repo.listDrafts()).isEmpty, 'blank startup must not save');
    });
    await test('mainbar-mutual-selection-and-serialized-rapid-taps', () async {
      immediateTap('main-sidebar-toolbox', 71);
      immediateTap('main-sidebar-toolbox', 72);
      await settle();
      await settle();
      expectMode('toolbox');
      immediateTap('main-sidebar-library', 73);
      immediateTap('main-sidebar-toolbox', 74);
      await settle();
      await settle();
      expectMode('toolbox');
      immediateTap('main-sidebar-library', 75);
      immediateTap('main-sidebar-library', 76);
      await settle();
      await settle();
      expectMode(null);
      check(keyed('library-search') == null, 'two library taps show then hide');
      await tap('main-sidebar-library');
      expectMode('library');
      await tap('main-sidebar-toolbox');
      expectMode('toolbox');
      check((await repo.listDrafts()).isEmpty,
          'rapid toggles do not persist blank');
    });
    await test('library-search-map-cannon-intersection', () async {
      await tap('main-sidebar-library');
      await settle();
      await tap('library-section-我的存档');
      await typeSearch('泳池');
      await tap('library-filter-toggle');
      await tap('library-map-pool');
      await tap('library-cannon-2');
      await tap('library-filter-apply');
      check(
          keyed('library-item-archive:pool-two') != null &&
              keyed('library-item-archive:roof-none') == null,
          'combined real composition filter');
    });
    await test('detail-excludes-hidden-search-focus-without-losing-input',
        () async {
      await tap('library-search');
      final input = searchState();
      check(input.widget.focusNode.hasFocus, 'focused before selecting');
      await tap('library-item-archive:pool-two');
      check(keyed('library-detail-back') != null,
          'actualcard opens narrowdetail');
      check(
          !input.widget.focusNode.hasFocus &&
              !input.widget.focusNode.canRequestFocus,
          'hidden list cannot keep or regain input focus');
      check(
          input.widget.controller.text == '泳池', 'hidden search text preserved');
      await tap('library-detail-back');
      check(
          identical(input, searchState()) &&
              searchState().widget.controller.text == '泳池',
          'back keeps search state');
    });
    await test('narrow-filter-hides-zero-and-uses-no-cannon-label', () async {
      check(
          (elements((w) => w is LibraryBrowser).single.renderObject
                      as RenderBox)
                  .size
                  .width ==
              410,
          'actual narrow content width');
      check(
          keyed('library-game-tools') == null &&
              keyed('library-apply-game') == null,
          'nonWindows hides live game entry');
      await tap('library-filter-toggle');
      check(
          keyed('library-map-roof') == null &&
              keyed('library-cannon-0') == null,
          'zeroavailable options hidden');
      check(elements((w) => w is Text && w.data == '0阵').isEmpty,
          'no zero badge');
      await tap('library-filter-reset');
      await tap('library-filter-cancel');
      check(
          elements((w) => w is Text && (w.data ?? '').contains('2炮'))
              .isNotEmpty,
          'cancel reset leaves applied filter');
      await tap('library-clear-filters');
      await typeSearch('屋顶');
      await tap('library-filter-toggle');
      check(elements((w) => w is Text && w.data == '无炮').isNotEmpty,
          'zero cannon labeled 无炮');
      await tap('library-cannon-0');
      await tap('library-filter-apply');
      check(keyed('library-item-archive:roof-none') != null,
          'actualzero formation result');
      await tap('library-clear-filters');
      await typeSearch('泳池');
      await applyPoolFilter();
    });
    await test('list-detail-back-preserves-scroll-and-filters', () async {
      await tap('library-clear-filters');
      await typeSearch('');
      final scroll = listScrollable();
      final box = keyed('library-results')!.renderObject as RenderBox;
      final point = box.localToGlobal(box.size.center(Offset.zero));
      GestureBinding.instance.handlePointerEvent(PointerScrollEvent(
          position: point, scrollDelta: const Offset(0, 330)));
      await settle();
      check(scroll.position.pixels > 0, 'realwheel moved list');
      final cards = elements((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>)
              .value
              .startsWith('library-item-archive:'));
      final viewport = box.localToGlobal(Offset.zero) & box.size;
      final card = cards.firstWhere((e) {
        final b = e.renderObject as RenderBox;
        final centre = b.localToGlobal(b.size.center(Offset.zero));
        return viewport.contains(centre);
      });
      await tap((card.widget.key as ValueKey<String>).value);
      final retained = scroll.position.pixels;
      check(
          keyed('library-detail-back') != null &&
              keyed('library-search') == null,
          'inplace detail hides list controls');
      await tap('library-detail-back');
      check((scroll.position.pixels - retained).abs() < .5,
          'list scroll retained after back');
      await captureLibrary('410-list');
      await typeSearch('泳池');
      await applyPoolFilter();
      await tap('library-item-archive:pool-two');
      await tap('library-detail-back');
      check(
          searchState().widget.controller.text == '泳池' &&
              keyed('library-item-archive:roof-none') == null,
          'back preserves search and composition filter');
    });
    Object? libraryState;
    await test('mode-switch-preserves-library-state-and-filter', () async {
      libraryState =
          (elements((w) => w is LibraryBrowser).single as StatefulElement)
              .state;
      await tap('main-sidebar-toolbox');
      expectMode('toolbox');
      await tap('main-sidebar-library');
      expectMode('library');
      check(
          identical(
              libraryState,
              (elements((w) => w is LibraryBrowser).single as StatefulElement)
                  .state),
          'same library State retained');
      check(searchState().widget.controller.text == '泳池', 'search retained');
      check(
          keyed('library-item-archive:roof-none') == null, 'filters retained');
    });
    await test('hidden-library-loses-focus-and-editor-shortcut-works',
        () async {
      await tap('library-search');
      final search = searchState();
      check(search.widget.focusNode.hasFocus, 'search really focused');
      await tap('main-sidebar-library');
      expectMode(null);
      check(keyed('library-search') == null,
          'library hidden while both mainbuttons remain available');
      check(
          !search.widget.focusNode.hasFocus, 'hidden input must releasefocus');
      tabs.active.execute('键盘撤销验证', tabs.active.document.copy(sunValue: 321));
      final dispatch = WidgetsBinding.instance.platformDispatcher.onKeyData!;
      var time = 0;
      void key(PhysicalKeyboardKey physical, LogicalKeyboardKey logical,
          ui.KeyEventType type) {
        // The platform entry dispatches both pressed-key state and FocusManager.
        // Synthesized events are standalone and need no legacy raw companion.
        dispatch(ui.KeyData(
            timeStamp: Duration(milliseconds: ++time),
            type: type,
            physical: physical.usbHidUsage,
            logical: logical.keyId,
            character: null,
            synthesized: true));
      }

      final focusBefore = '${FocusManager.instance.primaryFocus}';
      key(PhysicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlLeft,
          ui.KeyEventType.down);
      key(PhysicalKeyboardKey.keyZ, LogicalKeyboardKey.keyZ,
          ui.KeyEventType.down);
      key(PhysicalKeyboardKey.keyZ, LogicalKeyboardKey.keyZ,
          ui.KeyEventType.up);
      key(PhysicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlLeft,
          ui.KeyEventType.up);
      await settle();
      final undone = tabs.active.document.sunValue == 9990;
      await tap('main-sidebar-library');
      check(undone, 'editor CtrlZ must work after hide; focus=$focusBefore');
      check(keyed('library-search') != null, 'show restores librarymode');
      check(searchState().widget.controller.text == '泳池',
          'hidden search data retained');
    });
    await test('current-tab-open-returns-to-toolbox', () async {
      final old = tabs.active;
      final count = tabs.sessions.length;
      await tap('library-item-archive:pool-two');
      await tap('library-open-current');
      check(tabs.sessions.length == count && !identical(tabs.active, old),
          'current tab replaced');
      check(
          tabs.active.document.pieces.where((p) => p.type == 'cob').length == 2,
          'actual archive loaded');
      check(keyed('library-search') == null, 'librarydetail hidden');
      expectMode('toolbox');
    });
    await test('already-open-archive-reuses-tab-and-library-selection-retained',
        () async {
      await tap('main-sidebar-library');
      check(keyed('library-detail-back') != null,
          'library retains previous detail');
      await backToList();
      check(searchState().widget.controller.text == '泳池',
          'still same library search');
      final old = tabs.active;
      final count = tabs.sessions.length;
      await tap('library-item-archive:pool-two');
      await tap('library-open-tab');
      check(tabs.sessions.length == count && identical(tabs.active, old),
          'already-open editable archive reuses its existing tab');
      check(keyed('library-search') == null, 'new tab also returns toolbox');
      expectMode('toolbox');
      await tap('main-sidebar-library');
      await captureLibrary('410-detail');
    });
    await test('new-blank-from-library-not-persisted', () async {
      await backToList();
      final count = (await repo.listDrafts()).length;
      await tap('library-new');
      check(tabs.active.document.pieces.isEmpty,
          'blank library action opens empty');
      check((await repo.listDrafts()).length == count, 'newblank not saved');
      check(keyed('library-search') == null, 'blank opens toolbox');
      expectMode('toolbox');
    });
  } catch (e, s) {
    rows.add({
      'id': 'setup-or-teardown',
      'status': 'fail',
      'error': '$e',
      'stack': '$s'
    });
  } finally {
    await tabs.flushAll();
    runApp(const SizedBox.shrink());
    await settle();
    tabs.dispose();
    await repo.close();
    await dir.delete(recursive: true);
  }
  final report = {
    'suite': 'shared-sidebar-fallback',
    'runtime':
        'real headless Flutter, actual pointers and temporary SQLite; missing native windows plugin; viewport1800x900, shared sidebar width410 with mainbar modebuttons; native geometry accepted separately',
    'results': rows,
    'passed': rows.where((r) => r['status'] == 'pass').length,
    'failed': rows.where((r) => r['status'] == 'fail').length,
    'flutterErrors': errors.map((e) => '${e.exception}').toList(),
    'screenshots': screenshots
  };
  File('/tmp/pvz-sidebar-fallback-report.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln(jsonEncode(report));
  exit(report['failed'] == 0 && errors.isEmpty ? 0 : 1);
}
