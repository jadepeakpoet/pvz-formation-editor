// Real 410x640 library UI + temporary SQLite/files. File picker/clipboard simulated.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

class Binding extends ParityBinding {
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      const ViewConfiguration(size: Size(410, 640), devicePixelRatio: 1);
}

Element? find(bool Function(Widget) predicate) {
  Element? result;
  void walk(Element e) {
    if (predicate(e.widget)) result = e;
    e.debugVisitOnstageChildren(walk);
  }

  walk(WidgetsBinding.instance.rootElement!);
  return result;
}

Element? key(String name) => find((w) => w.key == ValueKey(name));
void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 200));
Future<void> tapElement(Element e) async {
  await Scrollable.ensureVisible(e, duration: Duration.zero, alignment: .5);
  await settle();
  final b = e.renderObject as RenderBox;
  final p = b.localToGlobal(b.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: p, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 1, position: p));
  await settle();
}

Future<void> tap(String name) async {
  final e = key(name);
  check(e != null, 'Missing visible $name');
  await tapElement(e!);
}

ScrollPosition listPosition() {
  ScrollPosition? p;
  void walk(Element e) {
    if (e is StatefulElement && e.state is ScrollableState) {
      p = (e.state as ScrollableState).position;
    }
    e.visitChildren(walk);
  }

  walk(key('library-results')!);
  return p!;
}

Future<void> main() async {
  Binding();
  await OriginalAssets.ensureLoaded();
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  final dir = await Directory.systemTemp.createTemp('pvz-narrow-');
  final repo = await FormationRepository.open('${dir.path}/test.sqlite');
  final opened = <EditorSession>[];
  String clipboard = '';
  final importPath = '${dir.path}/imported.txt';
  await File(importPath).writeAsString('0,0 1 2 0 0 0');
  ParityBinding.handlers['pvz_formation_editor/files'] = (call) async {
    if (call.method == 'pickFormation') {
      return {
        'path': importPath,
        'bytes': await File(importPath).readAsBytes()
      };
    }
    throw MissingPluginException();
  };
  ParityBinding.handlers[SystemChannels.platform.name] = (call) async {
    if (call.method == 'Clipboard.setData') {
      clipboard = (call.arguments as Map)['text'] as String;
    }
    return null;
  };
  for (var i = 0; i < 30; i++) {
    await repo.saveArchive(
        id: 'archive-$i',
        name: '阵型${i.toString().padLeft(2, '0')}',
        document: Formation(pieces: [
          Piece(id: 'pea-$i', type: 'pea', row: 0, col: 0, layer: 10)
        ]).toJson());
  }
  final boundary = GlobalKey();
  runApp(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true),
          home: app.LibraryPage(
              repository: repo,
              onOpenSession: (s) async {
                opened.add(s);
              }))));
  await settle();
  await settle();
  final passed = <String>[];
  Future<void> image(String label) async {
    final screenshot = await (boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary)
        .toImage();
    final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/pvz-library-narrow-$label.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    screenshot.dispose();
  }

  try {
    await tap('library-section-我的存档');
    check(
        key('library-narrow-list') != null, '410 library must use list screen');
    await image('list');
    final position = listPosition();
    position.jumpTo((position.maxScrollExtent * .6)
        .clamp(position.minScrollExtent, position.maxScrollExtent));
    await settle();
    final card = find((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('library-item-archive:'))!;
    await Scrollable.ensureVisible(card,
        duration: Duration.zero, alignment: .5);
    await settle();
    final before = listPosition().pixels;
    await tapElement(card);
    check(
        key('library-narrow-detail') != null &&
            key('library-detail-back') != null,
        'Card opens separate narrow detail screen');
    await image('detail');
    await tap('library-detail-back');
    check((listPosition().pixels - before).abs() < 1,
        'Back lost list scroll offset');
    passed.add(
        '410 list/detail/back preserves scroll and has separate detail screen');
    listPosition().jumpTo(listPosition().minScrollExtent);
    await settle();
    final search = key('library-search')!.widget as TextField;
    search.controller!.text = '阵型00';
    search.onChanged!('阵型00');
    await settle();
    await tap('library-item-archive:archive-0');
    await tap('library-open-current');
    check(opened.last.sourceArchiveId == 'archive-0' && !opened.last.readOnly,
        'Current opens editable work copy');
    final currentId = opened.last.id;
    await tap('library-open-tab');
    check(
        opened.last.sourceArchiveId == 'archive-0' &&
            opened.last.id != currentId,
        'New tab creates separate archive work copy');
    await tap('library-copy-code');
    check(
        clipboard ==
            FormationExchange.encode(Formation.fromJson(
                (await repo.listArchives())
                    .firstWhere((a) => a.id == 'archive-0')
                    .document)),
        'Narrow copy is Toolkit only');
    await tap('library-detail-back');
    check(
        (key('library-search')!.widget as TextField).controller!.text == '阵型00',
        'Detail/back lost search');
    passed.add('narrow current/new tab, Toolkit copy and query retention');
    final field = key('library-search')!.widget as TextField;
    field.controller!.clear();
    field.onChanged!('');
    await settle();
    await tap('library-filter-toggle');
    await tap('library-map-pool');
    await tap('library-cannon-0');
    await image('filter-dialog');
    await tap('library-filter-apply');
    check(key('library-results') != null, '410 modal filter failed to apply');
    passed.add(
        '410 search and combination filter modal fit without horizontal overflow');
    await tap('library-section-预制名阵');
    final preset = LibraryPresets.all.first;
    final filter = key('library-search')!.widget as TextField;
    filter.controller!.text = preset.name;
    filter.onChanged!(preset.name);
    await settle();
    await tap('library-item-preset:${preset.id}');
    final count = (await repo.listArchives()).length;
    await tap('library-add-preset');
    check((await repo.listArchives()).length == count + 1,
        'Narrow preset add did not persist');
    await tap('library-detail-back');
    passed.add('narrow preset detail adds exact source to own archive');
    final clear = key('library-search')!.widget as TextField;
    clear.controller!.clear();
    clear.onChanged!('');
    await settle();
    await tap('library-import');
    await tapElement(
        find((w) => w is PopupMenuItem<String> && w.value == 'project')!);
    await settle();
    check(
        opened.last.filePath == importPath &&
            opened.last.fileFormat == 'website' &&
            opened.last.document.pieces.single.col == 1,
        'Narrow file import lost document or path');
    passed.add('narrow import menu retains source file association');
    check(errors.isEmpty, 'Flutter errors: $errors');
    await File('/tmp/pvz-library-narrow-report.json').writeAsString(jsonEncode({
      'pass': passed,
      'errors': errors,
      'scope':
          'real 410x640 Flutter library + temporary SQLite/files; file picker and clipboard channel simulated'
    }));
    stdout.writeln('PASS ${passed.length}: ${passed.join('; ')}');
    for (final session in opened) {
      session.dispose();
    }
    await repo.close();
    await dir.delete(recursive: true);
    exit(0);
  } catch (e, stack) {
    stderr.writeln('$e\n$stack\n$errors');
    exit(1);
  }
}
