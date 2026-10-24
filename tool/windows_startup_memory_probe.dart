// ignore_for_file: depend_on_referenced_packages, invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/platform/image_memory.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/library/formation_thumbnail.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/library/thumbnail_store.dart';

class ProbePaths extends PathProviderPlatform {
  ProbePaths(this.root, this.delegate);
  final String root;
  final PathProviderPlatform delegate;
  @override
  Future<String?> getApplicationSupportPath() async => '$root/support';
  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
  @override
  Future<String?> getTemporaryPath() => delegate.getTemporaryPath();
  @override
  Future<String?> getApplicationDocumentsPath() =>
      delegate.getApplicationDocumentsPath();
}

void configurePaths() {
  if (Platform.environment['PVZ_PROBE_UNBOUNDED_GPU'] == '1') {
    ImageMemory.configureGpuCache = false;
  }
  final root = Platform.environment['PVZ_STARTUP_PROBE_ROOT']!;
  PathProviderPlatform.instance =
      ProbePaths(root, PathProviderPlatform.instance);
  ThumbnailStore.directoryOverride = Directory('$root/cache');
}

@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  configurePaths();
  await app.toolboxMain();
}

@pragma('vm:entry-point')
Future<void> libraryMain() async {
  configurePaths();
  await app.libraryMain();
}

Map<String, Object> editingDocument() {
  final result = <String, Object>{};
  void visit(Element e) {
    final widget = e.widget;
    if (widget is app.EditorPage && !widget.toolboxOnly) {
      result['objects'] = widget.session.document.pieces.length;
      result['map'] = widget.session.document.mapId;
    }
    e.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  return result;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configurePaths();
  final file = File(
      '${Platform.environment['PVZ_STARTUP_PROBE_ROOT']}/startup-report.json');
  final report = <String, dynamic>{'samples': <Map<String, dynamic>>[]};
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  Future<void> sample(int ms) async {
    final stats = <String, dynamic>{
      'ms': ms,
      'rss': ProcessInfo.currentRss,
      'root': OriginalAssets.resourceStats(),
      'previewBytes': FormationThumbnail.cachedBytes,
      'presetDocuments': LibraryPreset.cachedDocumentCount,
      'document': editingDocument()
    };
    try {
      stats['windows'] = await WindowBridge.channel.invokeMethod('diagnostics');
    } catch (e) {
      stats['nativeError'] = '$e';
    }
    (report['samples'] as List).add(stats);
  }

  await sample(0);
  await app.main();
  for (var i = 1; i <= 40; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (i <= 8 || i % 4 == 0) await sample(i * 250);
  }
  report['sidebar'] =
      await WindowBridge.channel.invokeMethod('resourceDiagnostics');
  report['errors'] = errors;
  await file.writeAsString(jsonEncode(report));
}
