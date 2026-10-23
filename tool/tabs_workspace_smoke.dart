// Real Flutter Workspace + temporary SQLite. Native windows channel is simulated.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

late Bridge bridge;

class Binding extends ParityBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      bridge = Bridge(super.createBinaryMessenger());
}

class Bridge extends BinaryMessenger {
  final BinaryMessenger delegate;
  Bridge(this.delegate);
  Future<ByteData?>? Function(ByteData?)? incoming;
  @override
  Future<ByteData?>? send(String c, ByteData? data) {
    if (c != 'pvz_formation_editor/windows') return delegate.send(c, data);
    const codec = StandardMethodCodec();
    final call = codec.decodeMethodCall(data);
    return Future.value(codec.encodeSuccessEnvelope(
        call.method == 'initialize' ||
            call.method == 'publishState' ||
            call.method == 'setToolboxVisible'));
  }

  Future<dynamic> emit(String method, dynamic arguments) async {
    const codec = StandardMethodCodec();
    final response =
        await incoming!(codec.encodeMethodCall(MethodCall(method, arguments)));
    return codec.decodeEnvelope(response!);
  }

  @override
  void setMessageHandler(
      String c, Future<ByteData?>? Function(ByteData?)? handler) {
    if (c == 'pvz_formation_editor/windows') {
      incoming = handler;
    } else {
      delegate.setMessageHandler(c, handler);
    }
  }

  @override
  Future<void> handlePlatformMessage(
          String c, ByteData? d, void Function(ByteData?)? cb) =>
      // ignore: deprecated_member_use
      delegate.handlePlatformMessage(c, d, cb);
}

class Harness extends ParityHarness {
  Harness(super.boundary, super.output);
  @override
  Future<String> screenshot(String id) async {
    await settle();
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    final path = '${output.path}/$id.png';
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    evidence.add(path);
    return path;
  }
}

Future<void> main() async {
  Binding();
  await OriginalAssets.ensureLoaded();
  final dir = await Directory.systemTemp.createTemp('pvz-tabs-ui-');
  final repo = await FormationRepository.open('${dir.path}/test.sqlite');
  final initial = EditorSession(repo, name: 'Tab A');
  final tabs = EditorTabsController(repo, initial: initial);
  final boundary = GlobalKey();
  final out = Directory('/tmp/pvz-tabs-workspace');
  await out.create(recursive: true);
  final h = Harness(boundary, out);
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: app.EditorWorkspace(
              controller: tabs,
              libraryPath: '${dir.path}/test.sqlite',
              continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  dynamic page() =>
      (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  final originalState = page();
  final firstToken = page().documentToken as String;
  final firstState = Map<String, dynamic>.from(page().windowState() as Map);
  Future<void> tick() async {
    await h.settle();
    await h.settle();
  }

  Future<void> open(String name, bool newTab, {String map = 'pool'}) async {
    await page().openLibraryItem({
      'kind': 'new',
      'name': name,
      'newTab': newTab,
      'documentJson': jsonEncode(Formation(mapId: map).toJson())
    });
    await tick();
  }

  Future<void> clickKey(String key) async {
    await h.tapElement(h.find((w) => w.key == ValueKey(key)));
    await tick();
  }

  await h.run('tabs.blank-token',
      'Identical empty tabs receive different tokens and reject stale tool edits',
      () async {
    await open('Tab B', true);
    h.expect(
        tabs.sessions.length == 2 &&
            tabs.active.document.fingerprint == initial.document.fingerprint,
        'New blank tab changed old formation');
    h.expect(
        identical(page(), originalState) && page().documentToken != firstToken,
        'Session switch recreated editor State or reused token');
    final stale = {
      ...firstState,
      'documentJson': jsonEncode(Formation(pieces: [
        Piece(id: 'stale', type: 'pea', row: 0, col: 0, layer: 10)
      ]).toJson())
    };
    h.expect(
        page().receiveWindowState(stale) == false &&
            tabs.active.document.pieces.isEmpty,
        'Old blank-tab edit crossed token boundary');
  });
  await h.run('tabs.pointer-history',
      'Actual tab pointers preserve independent session undo history',
      () async {
    await clickKey('editor-tab-${initial.id}');
    final board = h
        .find((w) => w is CustomPaint && w.painter is BoardPainter)
        .renderObject as RenderBox;
    await h.tapAt(board
        .localToGlobal(BoardGeometry(tabs.active.document).cellCenter(0, 0)));
    h.expect(initial.document.pieces.length == 1 && initial.canUndo,
        'Actual plant did not create history');
    final second = tabs.sessions[1];
    await clickKey('editor-tab-${second.id}');
    h.expect(
        tabs.active.document.pieces.isEmpty, 'Tab B inherited Tab A edits');
    await clickKey('editor-tab-${initial.id}');
    h.expect(initial.canUndo && initial.document.pieces.length == 1,
        'Switch lost history');
  });
  await h.run(
      'tabs.stale-action', 'Late old-token undo cannot mutate current session',
      () async {
    final before = tabs.active.document.fingerprint;
    final result = await bridge
        .emit('mainAction', {'action': 'undo', 'documentToken': firstToken});
    h.expect(result == false && tabs.active.document.fingerprint == before,
        'Old-token mainAction changed new active session');
  });
  await h.run('tabs.current-open',
      'Current-tab open replaces only active slot and keeps editor State',
      () async {
    final count = tabs.sessions.length;
    await open('Roof replacement', false, map: 'roof');
    h.expect(
        tabs.sessions.length == count && tabs.active.document.mapId == 'roof',
        'Current open added extra tab');
    h.expect(identical(page(), originalState), 'Current open recreated editor');
    h.expect(
        page().outputFormation.text ==
            FormationExchange.encode(tabs.active.document),
        'Live Toolkit code stale after tab replacement');
  });
  await h.run('tabs.close-last',
      'Closing last tab creates ephemeral blank without an extra database draft',
      () async {
    while (tabs.sessions.length > 1) {
      await clickKey('editor-close-tab-${tabs.active.id}');
    }
    final count = (await repo.listDrafts()).length;
    await clickKey('editor-close-tab-${tabs.active.id}');
    h.expect(tabs.sessions.length == 1 && tabs.active.document.pieces.isEmpty,
        'Last close must leave one blank tab');
    await tabs.active.flush();
    h.expect((await repo.listDrafts()).length == count,
        'Untouched new last blank persisted');
    h.expect(h.all((w) => w is Text && w.data == 'Windows 游戏与存档').isEmpty,
        'Windows tools shown in macOS workspace');
  });
  await h.report();
  await File('/tmp/pvz-tabs-workspace-report.json').writeAsString(jsonEncode({
    'cases': h.cases,
    'scope':
        'real headless Flutter Workspace/tab gestures; native window protocol simulated; no native three-engine acceptance'
  }));
  await tabs.flushAll();
  runApp(const SizedBox());
  await h.settle();
  tabs.dispose();
  await repo.close();
  await dir.delete(recursive: true);
  exit(h.cases.any((c) => c['status'] != 'pass') ? 1 : 0);
}
