import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/library/thumbnail_store.dart';
import 'package:pvz_formation_editor/library/formation_thumbnail.dart';
import 'package:pvz_formation_editor/platform/image_memory.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';

@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  final cache = Platform.environment['PVZ_THUMBNAIL_CACHE_ROOT'];
  if (cache != null) ThumbnailStore.directoryOverride = Directory(cache);
  await app.toolboxMain();
  final report = Platform.environment['PVZ_SCROLL_REPORT'];
  if (report != null) unawaited(scrollPreviewTest(File(report)));
}

@pragma('vm:entry-point')
Future<void> libraryMain() => app.libraryMain();
void check(bool value, String message) {
  if (!value) throw StateError(message);
}

List<Element> findWidgets(bool Function(Widget) test) {
  final result = <Element>[];
  void visit(Element e) {
    if (test(e.widget)) result.add(e);
    e.debugVisitOnstageChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  return result;
}

Future<void> scrollPreviewTest(File file) async {
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  try {
    final start = File('${file.path}.start');
    for (var i = 0; i < 300 && !start.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    check(start.existsSync(),
        'Root requests scrolling after switch verification');
    Element? section;
    for (var i = 0; i < 300; i++) {
      final found = findWidgets((w) =>
          w.key == const ValueKey('library-section-\u9884\u5236\u540d\u9635'));
      if (found.isNotEmpty) {
        section = found.first;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    check(section != null, 'Preset section visible');
    (section!.widget as InkWell).onTap!();
    await pause();
    final list =
        findWidgets((w) => w.key == const ValueKey('library-results')).first;
    ScrollableState? scroll;
    void locate(Element e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        scroll ??= e.state as ScrollableState;
      }
      e.visitChildren(locate);
    }

    locate(list);
    check(scroll != null, 'Actual library scroll position');
    final samples = <int>[ProcessInfo.currentRss];
    final max = scroll!.position.maxScrollExtent;
    for (var pass = 0; pass < 3; pass++) {
      for (var pixel = 0.0; pixel <= max; pixel += 550) {
        scroll!.position.jumpTo(pass % 2 == 0 ? pixel : max - pixel);
        await Future<void>.delayed(const Duration(milliseconds: 90));
      }
      await pause();
      samples.add(ProcessInfo.currentRss);
    }
    scroll!.position.jumpTo(0);
    await pause();
    final images = findWidgets((w) =>
        w is RawImage && w.image?.width == 256 && w.image?.height == 192);
    check(images.isNotEmpty,
        'Visible thumbnails remain decoded after scrolling back');
    check(ThumbnailStore.generated == 0,
        'Built-in scrolling never generates formations');
    check(FormationThumbnail.cachedBytes <= 4 << 20,
        'Decoded preview pool remains bounded');
    check(errors.isEmpty, 'No rendering errors: $errors');
    await file.writeAsString(jsonEncode({
      'status': 'pass',
      'rssSamplesBytes': samples,
      'previewBytes': FormationThumbnail.cachedBytes,
      'bundledHits': ThumbnailStore.bundledHits,
      'diskHits': ThumbnailStore.diskHits,
      'generated': ThumbnailStore.generated,
      'resources': OriginalAssets.resourceStats(),
      'presetDocumentsCached': LibraryPreset.cachedDocumentCount,
      'errors': errors
    }));
  } catch (error, stack) {
    await file.writeAsString(
        jsonEncode({'error': '$error\n$stack', 'errors': errors}));
  }
}

Future<void> pause() => Future<void>.delayed(const Duration(seconds: 1));
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ImageMemory.configure();
  app.initializeExitHandling();
  final cache = Platform.environment['PVZ_THUMBNAIL_CACHE_ROOT'];
  if (cache != null) {
    ThumbnailStore.directoryOverride = Directory(cache);
    await ThumbnailStore.primeBuiltins();
  }
  final reportFile = File(Platform.environment['PVZ_MEMORY_REPORT']!);
  final report = <String, dynamic>{};
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  try {
    final path = '${reportFile.parent.path}/memory-close.sqlite';
    final repo = await FormationRepository.open(path);
    final session = EditorSession(repo,
        document: LibraryPresets.all.first.document,
        name: 'Exit autosave verification');
    final tabs = EditorTabsController(repo, initial: session);
    runApp(MaterialApp(
        home: app.EditorWorkspace(
            controller: tabs,
            libraryPath: path,
            continueArchive: (_) async {})));
    for (var i = 0; i < 100 && !WindowBridge.supported; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    check(WindowBridge.supported, 'Native bridge initializes');
    await pause();
    const channel = WindowBridge.channel;
    report['initial'] = await channel.invokeMethod('diagnostics');
    final samples = <int>[ProcessInfo.currentRss];
    for (var i = 0; i < 6; i++) {
      await WindowBridge.selectMode('library');
      await pause();
      final diagnostics = (await channel.invokeMapMethod('diagnostics'))!;
      check(
          diagnostics['libraryReady'] == true, 'Library shares sidebar engine');
      check(
          diagnostics['sidebarEngineCount'] == 1 &&
              diagnostics['hasLibraryEngine'] == false,
          'Repeated mode changes never create an extra engine');
      samples.add(ProcessInfo.currentRss);
      await WindowBridge.selectMode('toolbox');
      await pause();
      samples.add(ProcessInfo.currentRss);
    }
    final scrollReport = Platform.environment['PVZ_SCROLL_REPORT'];
    if (scrollReport != null) {
      await WindowBridge.selectMode('library');
      await File('$scrollReport.start').writeAsString('go');
      for (var i = 0; i < 180 && !File(scrollReport).existsSync(); i++) {
        await pause();
      }
      check(File(scrollReport).existsSync(),
          'Scroll performance report completed');
      report['scroll'] = jsonDecode(await File(scrollReport).readAsString());
      check((report['scroll'] as Map)['status'] == 'pass',
          'Scroll verification failed: ${report['scroll']}');
    }
    report['afterSwitching'] = await channel.invokeMethod('diagnostics');
    report['rssSamplesBytes'] = samples;
    report['rootResources'] = OriginalAssets.resourceStats();
    report['sidebarResources'] =
        await channel.invokeMethod('resourceDiagnostics');
    if (Platform.environment['PVZ_MEMORY_PROFILE'] == '1') {
      session.rename('Saved immediately before normal close');
      report['expectedId'] = session.id;
      report['database'] = path;
      report['errors'] = errors;
      report['status'] = 'ready-for-normal-close';
      await reportFile.writeAsString(jsonEncode(report));
      return;
    }
    Future<bool> veto() async => false;
    app.exitGuards.add(veto);
    await channel.invokeMethod('requestCloseForTest');
    await pause();
    report['vetoPreservedWindow'] =
        await channel.invokeMethod('diagnostics') != null;
    app.exitGuards.remove(veto);
    session.rename('Saved immediately before normal close');
    report['expectedId'] = session.id;
    report['database'] = path;
    report['errors'] = errors;
    check(errors.isEmpty, 'No Flutter errors during page switching');
    report['status'] = 'requesting-normal-close';
    await reportFile.writeAsString(jsonEncode(report));
    await channel.invokeMethod('requestCloseForTest');
    // Parent checks process exit and the committed SQLite name after WM_CLOSE.
  } catch (error, stack) {
    report['error'] = '$error\n$stack';
    await reportFile.writeAsString(jsonEncode(report));
    exit(1);
  }
}
