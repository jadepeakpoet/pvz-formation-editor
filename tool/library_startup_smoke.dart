// A first library frame must render before artwork preparation begins.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_browser.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  ParityBinding.handlers['pvz_formation_editor/library'] = (call) async {
    if (call.method == 'ready') return {'dataPath': ':memory:'};
    return null;
  };
  final clock = Stopwatch()..start();
  await app.libraryMain();
  await WidgetsBinding.instance.endOfFrame;
  final firstFrameMs = clock.elapsedMilliseconds;
  var loading = false;
  void walk(Element e) {
    final w = e.widget;
    if (w is Text && w.data == '正在加载存档库…') loading = true;
    e.visitChildren(walk);
  }

  walk(WidgetsBinding.instance.rootElement!);
  if (!loading) {
    throw StateError('Library did not paint the startup shell first');
  }
  final imagesAtFirstFrame = OriginalAssets.images.length;
  await OriginalAssets.ensureLoaded();
  await Future<void>.delayed(const Duration(milliseconds: 500));
  var library = false;
  void inspect(Element e) {
    if (e.widget is LibraryBrowser) library = true;
    e.visitChildren(inspect);
  }

  inspect(WidgetsBinding.instance.rootElement!);
  if (!library) {
    throw StateError('Prepared library did not replace startup shell');
  }
  final report = {
    'status': 'pass',
    'firstFrameMs': firstFrameMs,
    'totalReadyMs': clock.elapsedMilliseconds,
    'imagesAtFirstFrame': imagesAtFirstFrame,
    'imagesReady': OriginalAssets.images.length,
    'scope':
        'real Flutter engine first loading frame then actual library; configuration channel mocked'
  };
  await File('/tmp/pvz-library-startup-report.json')
      .writeAsString(jsonEncode(report));
  stdout.writeln(jsonEncode(report));
  exit(0);
}
