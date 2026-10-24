// Prepared UI performance target. Run only after functional acceptance finishes.
// Headless: flutter_tester. Native: xcode FLUTTER_TARGET=this file and
// PVZ_PERFORMANCE_NATIVE=1. Native mode measures a single combined workspace,
// intentionally excluding secondary-window transport and user preferences.
// Native fallback layout can exceed its actual view width. Preparation scrolls
// each target into view outside measured event latency; actual view dimensions
// remain unchanged. Missing or still-invisible targets must fail honestly.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kProfileMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart' show ParityBinding, ParityMessenger;
import 'performance_smoke.dart' as stats;

class NativePerformanceBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      ParityMessenger(super.createBinaryMessenger());
}

List<Element> elements(bool Function(Widget) match) {
  final out = <Element>[];
  void visit(Element e) {
    if (match(e.widget)) out.add(e);
    e.debugVisitOnstageChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  return out;
}

Element find(bool Function(Widget) match) {
  final found = elements(match);
  if (found.isEmpty) throw StateError('UI performance target missing');
  return found.first;
}

Future<void> frame() async {
  SchedulerBinding.instance.scheduleFrame();
  await SchedulerBinding.instance.endOfFrame
      .timeout(const Duration(seconds: 15));
}

Future<void> until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('UI condition');
    }
    await frame();
  }
}

Offset center(Element element) {
  final box = element.renderObject as RenderBox;
  return box.localToGlobal(box.size.center(Offset.zero));
}

void checkVisible(Offset point) {
  final logicalSize =
      WidgetsBinding.instance.renderViews.first.configuration.logicalConstraints.biggest;
  if (!(Offset.zero & logicalSize).contains(point)) {
    throw StateError('UI point $point outside actual viewport $logicalSize');
  }
}

Future<void> prepareVisible(Element target) async {
  await Scrollable.ensureVisible(target,
      duration: Duration.zero, alignment: .5);
  await frame();
  checkVisible(center(target));
}

void click(Offset position, int pointer) {
  checkVisible(position);
  final binding = GestureBinding.instance;
  binding.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      kind: PointerDeviceKind.mouse,
      position: position,
      buttons: 1));
  binding.handlePointerEvent(PointerUpEvent(
      pointer: pointer, kind: PointerDeviceKind.mouse, position: position));
}

Future<void> main() async {
  final native = Platform.environment['PVZ_PERFORMANCE_NATIVE'] == '1';
  if (native) {
    NativePerformanceBinding();
  } else {
    ParityBinding();
  }
  // The real workspace/library widgets remain intact. Disable only external
  // windows so native and headless can exercise the same combined layout.
  ParityBinding.handlers['pvz_formation_editor/windows'] = (_) async => false;
  final errors = <String>[];
  FlutterError.onError = (details) {
    errors.add(details.exceptionAsString());
  };
  final scenarios = <String, Object?>{};
  final slowEvents = <Map<String, Object?>>[];
  var currentScenario = '';
  final allFrames = <FrameTiming>[];
  void timing(List<FrameTiming> values) => allFrames.addAll(values);
  SchedulerBinding.instance.addTimingsCallback(timing);
  final report = <String, Object?>{
    'environment': {
      'mode': native
          ? 'native macOS ${kProfileMode ? 'profile' : kReleaseMode ? 'release' : 'debug'}; actual compositor'
          : 'headless flutter_tester debug; software rendering',
      'os': Platform.operatingSystemVersion,
      'dart': Platform.version,
      'pointer': 'Flutter GestureBinding mouse events; not OS CGEvents',
      'windows': 'combined EditorWorkspace; native bridge disabled',
      'persistence': 'in-memory SQLite; no real preferences loaded or modified',
      'latency':
          'event dispatch through next endOfFrame, plus explicit mutation conditions',
      'frames':
          'SchedulerBinding FrameTiming, delivery may be delayed/batched; not a 60fps acceptance claim',
    },
    'scenarios': scenarios,
    'slowEventsOver100ms': slowEvents,
  };
  FormationRepository? repo;
  EditorTabsController? tabs;
  var pointer = 100;
  Future<void> scenario(
      String name, Future<void> Function(List<double>) body) async {
    currentScenario = name;
    final startRevision = OriginalAssets.revision.value;
    final startFrames = allFrames.length;
    final watch = Stopwatch()..start();
    final latencies = <double>[];
    await body(latencies);
    watch.stop();
    // FrameTiming is asynchronously batched. Drain scheduled frames, without
    // introducing a fixed sleep into the response latency measurements.
    for (var i = 0; i < 3; i++) {
      await frame();
    }
    final frames = allFrames.skip(startFrames).toList();
    scenarios[name] = {
      'elapsedMs': watch.elapsedMicroseconds / 1000,
      'assetRevisionDelta': OriginalAssets.revision.value - startRevision,
      'events': latencies.length,
      if (latencies.isNotEmpty) 'eventToEndOfFrame': stats.summary(latencies),
      'frameCount': frames.length,
      if (frames.isNotEmpty)
        'build': stats.summary(
            [for (final f in frames) f.buildDuration.inMicroseconds / 1000]),
      if (frames.isNotEmpty)
        'raster': stats.summary(
            [for (final f in frames) f.rasterDuration.inMicroseconds / 1000]),
      if (frames.isNotEmpty)
        'totalSpan': stats.summary(
            [for (final f in frames) f.totalSpan.inMicroseconds / 1000]),
      if (frames.isEmpty)
        'frameTimingStatus': 'unavailable; no values invented',
    };
    stdout.writeln('$name ${jsonEncode(scenarios[name])}');
  }

  Future<void> event(List<double> latencies, void Function() dispatch,
      {bool Function()? complete}) async {
    final revisionBefore = OriginalAssets.revision.value;
    final watch = Stopwatch()..start();
    dispatch();
    await frame();
    if (complete != null) await until(complete);
    watch.stop();
    final elapsed = watch.elapsedMicroseconds / 1000;
    latencies.add(elapsed);
    if (elapsed > 100) {
      slowEvents.add({
        'scenario': currentScenario,
        'latencyMs': elapsed,
        'assetRevisionDelta': OriginalAssets.revision.value - revisionBefore
      });
    }
  }

  try {
    final assetWatch = Stopwatch()..start();
    await OriginalAssets.ensureLoaded();
    report['assetLoadMs'] = assetWatch.elapsedMicroseconds / 1000;
    repo = await FormationRepository.open(':memory:');
    final seedWatch = Stopwatch()..start();
    for (var i = 0; i < 500; i++) {
      await repo.saveArchive(
          id: 'performance-archive-$i',
          name: '性能存档 $i',
          document: stats.fixture(80).toJson());
    }
    report['dataset'] = {
      'archives': 500,
      'objectsPerArchive': 80,
      'seedSetupMs': seedWatch.elapsedMicroseconds / 1000
    };
    final workspaceWatch = Stopwatch()..start();
    final first = EditorSession(repo,
        persistDraft: false, document: stats.fixture(80), name: '性能隔离测试');
    tabs = EditorTabsController(repo, initial: first);
    await tabs.ready;
    runApp(MaterialApp(
        home: app.EditorWorkspace(
            controller: tabs, continueArchive: (_) async {})));
    await until(() => elements((w) => w is app.EditorPage).isNotEmpty);
    await frame();
    report['workspaceFirstInteractiveMs'] =
        workspaceWatch.elapsedMicroseconds / 1000;
    dynamic page() =>
        (find((w) => w is app.EditorPage) as StatefulElement).state;
    final archiveButton =
        find((w) => w.key == const ValueKey('main-sidebar-library'));
    await prepareVisible(archiveButton);
    await scenario('archiveLibrary.500archives.openToInteractive',
        (latencies) async {
      await event(latencies, () => click(center(archiveButton), pointer++),
          complete: () =>
              elements((w) => w.key == const ValueKey('library-narrow-list'))
                  .isNotEmpty);
    });
    final toolboxButton =
        find((w) => w.key == const ValueKey('main-sidebar-toolbox'));
    await prepareVisible(toolboxButton);
    click(center(toolboxButton), pointer++);
    await frame();
    page().selectToolboxTab(1);
    await frame();
    final selector = find((w) => w.key == const ValueKey('preset-selector-阵型'));
    await prepareVisible(selector);
    await scenario('library.presetPicker.firstOpenToInteractive',
        (latencies) async {
      await event(latencies, () => click(center(selector), pointer++),
          complete: () =>
              elements((w) => w.key == const ValueKey('preset-picker-results'))
                  .isNotEmpty);
    });
    final list = find((w) => w.key == const ValueKey('preset-picker-results'));
    await prepareVisible(list);
    final scroll = elements((w) => w is Scrollable).where((e) {
      var descendant = false;
      e.visitAncestorElements((a) {
        if (identical(a, list)) descendant = true;
        return !descendant;
      });
      return descendant;
    }).first as StatefulElement;
    final scrollState = scroll.state as ScrollableState;
    final initialScroll = scrollState.position.pixels;
    var furthestScroll = initialScroll;
    await scenario('library.realList.scroll60', (latencies) async {
      for (var i = 0; i < 60; i++) {
        await event(latencies, () {
          GestureBinding.instance.handlePointerEvent(PointerScrollEvent(
              position: center(list),
              scrollDelta: Offset(0, i < 30 ? 90 : -90),
              kind: PointerDeviceKind.mouse));
        });
        if (scrollState.position.pixels > furthestScroll) {
          furthestScroll = scrollState.position.pixels;
        }
      }
    });
    report['scrollObserved'] = {
      'initial': initialScroll,
      'furthest': furthestScroll
    };
    if (furthestScroll <= initialScroll) {
      throw StateError('Real list did not scroll');
    }
    scrollState.position.jumpTo(0);
    await frame();
    await scenario('library.card.currentPageNavigation8', (latencies) async {
      for (var i = 0; i < 8; i++) {
        final preset = LibraryPresets.all[i];
        final cardKey = ValueKey('library-item-preset:${preset.id}');
        if (elements((w) => w.key == cardKey).isEmpty) {
          scrollState.position.jumpTo(
              (i * 100.0).clamp(0.0, scrollState.position.maxScrollExtent));
          await frame();
        }
        final card =
            find((w) => w.key == ValueKey('library-item-preset:${preset.id}'));
        // Preparation is outside the measured pointer-response interval.
        await prepareVisible(card);
        await event(latencies, () => click(center(card), pointer++),
            complete: () =>
                tabs!.active.document.fingerprint ==
                preset.document.fingerprint);
      }
    });
    // Move back from the picker into the editor. Each test uses a new history
    // visit; all previous sessions remain owned by the tabs controller.
    page().selectToolboxTab(2);
    await frame();
    for (final count in [80, 500]) {
      await page().navigateFormation(stats.fixture(count), name: '性能$count');
      await frame();
      final dynamic editor = page();
      final boardElement = editor.plantingBoardKey.currentContext as Element;
      await prepareVisible(boardElement);
      final board = editor.plantingBoardKey.currentContext.findRenderObject()
          as RenderBox;
      await scenario('board.$count.plant30', (latencies) async {
        editor.setState(() {
          editor.tool = '放置';
          editor.selectedType = 'pea';
        });
        await frame();
        for (var i = 0; i < 30; i++) {
          final point = BoardGeometry(tabs!.active.document)
              .cellCenter(i % 6, (i * 3) % 9);
          final global = board.localToGlobal(point);
          checkVisible(global);
          await event(latencies, () {
            GestureBinding.instance.handlePointerEvent(PointerHoverEvent(
                position: global, kind: PointerDeviceKind.mouse));
            click(global, pointer++);
          });
        }
      });
      await scenario('board.$count.smartShovel30', (latencies) async {
        editor.setState(() {
          editor.tool = '铲除';
          editor.shovelFilter = '智能';
        });
        await frame();
        for (var i = 0; i < 30; i++) {
          final point = BoardGeometry(tabs!.active.document)
              .cellCenter(i % 6, (i * 3) % 9);
          final global = board.localToGlobal(point);
          checkVisible(global);
          await event(latencies, () {
            GestureBinding.instance.handlePointerEvent(PointerHoverEvent(
                position: global, kind: PointerDeviceKind.mouse));
            click(global, pointer++);
          });
        }
      });
    }
    report['status'] = errors.isEmpty ? 'complete' : 'flutterErrors';
  } catch (error, stack) {
    report['status'] = 'failed';
    stdout.writeln('UI performance failure: $error');
    report['error'] = '$error';
    report['stack'] = '$stack';
    exitCode = 1;
  } finally {
    report['flutterErrors'] = errors;
    report['frameCountOverall'] = allFrames.length;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    report['view'] = {
      'physicalWidth': view.physicalSize.width,
      'physicalHeight': view.physicalSize.height,
      'devicePixelRatio': view.devicePixelRatio,
      'configuredLogicalWidth':
          WidgetsBinding.instance.renderViews.first.configuration.logicalConstraints.biggest.width,
      'configuredLogicalHeight':
          WidgetsBinding.instance.renderViews.first.configuration.logicalConstraints.biggest.height
    };
    SchedulerBinding.instance.removeTimingsCallback(timing);
    runApp(const SizedBox.shrink());
    await frame();
    await tabs?.flushAll();
    tabs?.dispose();
    await repo?.close();
    final output = Platform.environment['PVZ_PERFORMANCE_UI_OUTPUT'] ??
        '/tmp/pvz-performance-ui-${native ? 'native' : 'headless'}.json';
    await File(output)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln('UI performance report: $output');
  }
  exit(exitCode);
}
