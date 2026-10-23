// Native macOS acceptance target: FLUTTER_TARGET=tool/parity_windows.dart.
// Both entrypoints must live in this root library for the second FlutterEngine.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/original_catalog.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

const _qaPath = '/tmp/pvz-window-qa';
const _native = MethodChannel('pvz_formation_editor/windows');
Future<void> _write(String path, Map<String, dynamic> value) async {
  final temporary = File('$path.tmp');
  await temporary.writeAsString(jsonEncode(value), flush: true);
  await temporary.rename(path);
}

Future<Map<String, dynamic>?> _read(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  try {
    return Map<String, dynamic>.from(
        jsonDecode(await file.readAsString()) as Map);
  } on FormatException {
    return null;
  }
}

Future<void> _until(bool Function() condition, String description,
    {int seconds = 12}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException(description);
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

void _check(bool value, String description) {
  if (!value) throw StateError(description);
}

class _NativeHarness extends ParityHarness {
  _NativeHarness(super.boundary, super.output);
  dynamic get page =>
      (find((w) => w is app.EditorPage) as StatefulElement).state;
  Map<String, dynamic> get state =>
      Map<String, dynamic>.from(page.windowState() as Map);
  @override
  Future<void> settle() async {
    await super.settle();
    final binding = WidgetsBinding.instance;
    final render = boundary.currentContext?.findRenderObject();
    final needsPaint =
        render is RenderRepaintBoundary && render.debugNeedsPaint;
    if (!binding.hasScheduledFrame && !needsPaint) return;
    await _native.invokeMethod<void>('activateWindow');
    await binding.endOfFrame.timeout(const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException(
            'Native engine has pending rendering but did not complete a frame within 3 seconds'));
  }

  @override
  Future<void> tapAt(Offset position) async {
    await _native.invokeMethod<void>('activateWindow');
    await super.tapAt(position);
  }

  @override
  Future<String> screenshot(String id) async {
    await settle();
    return captureCurrentFrame(id);
  }

  Future<String> captureCurrentFrame(String id) async {
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage().timeout(const Duration(seconds: 3));
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final path = '${output.path}/${Uri.encodeComponent(id)}.png';
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    evidence.add(path);
    return path;
  }

  Future<void> keyTap(String key) =>
      tapElement(find((w) => w.key == ValueKey(key)));
  Offset center(Element e) {
    final box = e.renderObject as RenderBox;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void immediateTap(Offset p) {
    GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: 1, position: p, buttons: 1));
    GestureBinding.instance
        .handlePointerEvent(PointerUpEvent(pointer: 1, position: p));
  }
}

Future<(_NativeHarness, EditorSession, FormationRepository)> _mount(
    bool toolbox, String run) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!toolbox) {
    const MethodChannel('pvz_formation_editor/lifecycle')
        .setMethodCallHandler((call) async {
      if (call.method != 'prepareExit') throw MissingPluginException();
      for (final guard in app.exitGuards.reversed.toList()) {
        if (!await guard()) return false;
      }
      return true;
    });
  }
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final session =
      EditorSession(repo, persistDraft: false, name: 'Native window QA $run');
  final boundary = GlobalKey();
  final output = Directory('$_qaPath/$run');
  await output.create(recursive: true);
  final h = _NativeHarness(boundary, output);
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          title: toolbox ? '网页布阵器工具箱' : '植物大战僵尸阵型编辑器 · PVZ Studio',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
              useMaterial3: true,
              colorScheme:
                  ColorScheme.fromSeed(seedColor: const Color(0xff456b4e)),
              inputDecorationTheme: const InputDecorationTheme(
                  border: OutlineInputBorder(), isDense: true)),
          home: app.EditorPage(
              session: session,
              toolboxOnly: toolbox,
              continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  return (h, session, repo);
}

@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic>? meta;
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (meta == null && DateTime.now().isBefore(deadline)) {
    meta = await _read('$_qaPath/meta.json');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (meta == null) return;
  final run = meta['runId'] as String;
  final (h, session, repo) = await _mount(true, run);
  try {
    await _until(() => WindowBridge.supported && h.page.nativeWindows == true,
        'Toolbox did not connect to actual native windows');
    await _write('$_qaPath/$run/toolbox-ready.json', {
      'pid': pid,
      'supported': WindowBridge.supported,
      'persistDraft': session.persistDraft
    });
    var previous = 0;
    while (true) {
      final command = await _read('$_qaPath/$run/command.json');
      if (command == null || command['id'] == previous) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        continue;
      }
      previous = command['id'] as int;
      final name = command['name'] as String;
      final payload =
          Map<String, dynamic>.from(command['payload'] as Map? ?? {});
      final ack = <String, dynamic>{
        'id': previous,
        'name': name,
        'status': 'pass'
      };
      final before = h.errors.length;
      try {
        switch (name) {
          case 'selectCard':
            await h.tap('图鉴选卡');
            await h.keyTap('original-card-sunflower');
            _check(h.state['selectedType'] == 'sunflower',
                'Toolbox card selection failed');
            break;
          case 'changeMap':
            await h.tap('选项设置');
            final fingerprint = session.document.fingerprint;
            await h.keyTap('settings-change-map');
            _check(session.document.fingerprint == fingerprint,
                'Opening map picker must not change the document');
            await h.keyTap('map-picker-map-day');
            break;
          case 'preset':
            await h.tap('懒人布局');
            await h.choose<int>(0, index: 0);
            await h.tap('布阵且更换相应地图');
            break;
          case 'style':
            await h.tap('选项设置');
            await h.keyTap('original-rWindow3');
            _check(h.state['windowStyle'] == 3,
                'Toolbox window style radio did not change');
            break;
          case 'rapid':
            await h.tap('选项设置');
            final soil =
                h.find((w) => w.key == const ValueKey('original-cSoil'));
            final brain =
                h.find((w) => w.key == const ValueKey('original-rBrain'));
            await Scrollable.ensureVisible(soil, alignment: .4);
            await Scrollable.ensureVisible(brain, alignment: .6);
            await h.settle();
            final first = h.center(soil), second = h.center(brain);
            final expectedSoil = !session.document.display['泥土']!,
                expectedBrain = !session.document.display['脑子']!;
            final completed = Completer<void>();
            var inFlight = false;
            h.immediateTap(first);
            scheduleMicrotask(() {
              try {
                inFlight = h.page.windowPublishInFlight == true;
                h.immediateTap(second);
                completed.complete();
              } catch (e, stack) {
                completed.completeError(e, stack);
              }
            });
            await completed.future;
            _check(inFlight,
                'Second real pointer event must happen while first native publish awaits ACK');
            _check(
                session.document.display['泥土'] == expectedSoil &&
                    session.document.display['脑子'] == expectedBrain,
                'Local rapid edits did not both apply');
            ack.addAll({
              'inFlightAtSecond': inFlight,
              'expectedSoil': expectedSoil,
              'expectedBrain': expectedBrain
            });
            break;
          case 'prepareRetain':
            await h.tap('图鉴选卡');
            await h.keyTap('original-card-sunflower');
            await h.tap('载入导出');
            await h.enterText(
                h.find((w) => w is EditableText), payload['marker'] as String);
            break;
          case 'assertRetained':
            _check(
                h
                    .all(
                        (w) => w.key == const ValueKey('original-link-toolkit'))
                    .isNotEmpty,
                'Toolbox local tab was reset after hiding');
            _check(
                (h.find((w) => w is EditableText).widget as EditableText)
                        .controller
                        .text ==
                    payload['marker'],
                'Toolbox local unsent text was reset after hiding');
            _check(h.state['selectedType'] == 'sunflower',
                'Toolbox selected card was reset');
            break;
          case 'snapshot':
            await _until(
                () => session.document.fingerprint == payload['fingerprint'],
                'Toolbox replica did not converge to canonical main document');
            break;
          case 'finish':
            await session.flush();
            _check(!session.persistDraft && (await repo.listDrafts()).isEmpty,
                'Replica must not create a competing persisted draft');
            ack['replicaDraftCount'] = 0;
            break;
          default:
            throw StateError('Unknown QA command $name');
        }
        if (h.errors.length > before) {
          throw StateError(h.errors
              .skip(before)
              .map((e) => e.exceptionAsString())
              .join('\n'));
        }
        ack['screenshot'] =
            await h.screenshot('toolbox-${payload['caseId'] ?? name}');
        ack['state'] = h.state;
        ack['fingerprint'] = session.document.fingerprint;
      } catch (e, stack) {
        ack.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
        ack['classicTab'] = h.page.classicTab;
        ack['state'] = h.state;
        ack['fingerprint'] = session.document.fingerprint;
        try {
          ack['failureScreenshot'] = await h.captureCurrentFrame(
              'toolbox-failure-${payload['caseId'] ?? name}');
        } catch (captureError) {
          ack['failureScreenshotError'] = '$captureError';
        }
      }
      await _write('$_qaPath/$run/ack.json', ack);
      if (name == 'finish') return;
    }
  } catch (e, stack) {
    await _write('$_qaPath/$run/toolbox-fatal.json',
        {'error': '$e', 'stack': '$stack', 'pid': pid});
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Directory(_qaPath).create(recursive: true);
  final run = '${DateTime.now().microsecondsSinceEpoch}-$pid';
  await _write('$_qaPath/meta.json', {
    'runId': run,
    'pid': pid,
    'startedAt': DateTime.now().toIso8601String()
  });
  final (h, session, repo) = await _mount(false, run);
  final rows = <Map<String, dynamic>>[];
  var commandId = 0;
  var nativeReady = false;
  Future<Map<String, dynamic>> command(String name,
      [Map<String, dynamic> payload = const {}]) async {
    final id = ++commandId;
    await _write('$_qaPath/$run/command.json',
        {'id': id, 'name': name, 'payload': payload});
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final ack = await _read('$_qaPath/$run/ack.json');
      if (ack != null && ack['id'] == id) {
        if (ack['status'] != 'pass') {
          throw StateError('Toolbox $name: ${ack['error']}');
        }
        return ack;
      }
      final fatal = await _read('$_qaPath/$run/toolbox-fatal.json');
      if (fatal != null) throw StateError('Toolbox fatal: ${fatal['error']}');
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    throw TimeoutException('Toolbox did not acknowledge $name');
  }

  Future<Map<String, dynamic>> diagnostics() async => Map<String, dynamic>.from(
      (await _native.invokeMethod<dynamic>('diagnostics')) as Map);
  Future<void> report() async => _write('$_qaPath/report.json', {
        'schemaVersion': 1,
        'runId': run,
        'pid': pid,
        'scope':
            'actual native dual FlutterEngine windows; no window-channel mocks',
        'nativeBridgeSupported': WindowBridge.supported,
        'toolbarVisibilityAction':
            'Real pointer clicks on the Flutter operation-bar toolbox toggle invoke actual NSWindow hide/show',
        'nativeCloseButton':
            'notRun here; leave app open for root AX close/reopen acceptance',
        'storage':
            'both sessions :memory: and persistDraft:false; actual user library untouched',
        'cases': rows,
        'summary': {
          for (final status in ['pass', 'fail', 'notRun'])
            status: rows.where((r) => r['status'] == status).length
        },
        'finishedAt': DateTime.now().toIso8601String(),
        'leaveAppRunning': true
      });
  Future<void> test(
      String id, Future<void> Function(Map<String, dynamic>) body) async {
    final row = <String, dynamic>{'id': id, 'status': 'pass'};
    final before = h.errors.length;
    try {
      await body(row);
      if (h.errors.length > before) {
        throw StateError(
            h.errors.skip(before).map((e) => e.exceptionAsString()).join('\n'));
      }
      row['mainScreenshot'] = await h.screenshot('main-$id');
    } on MissingPluginException catch (e) {
      row.addAll({
        'status': 'notRun',
        'reason': 'Native diagnostics/event unavailable: $e'
      });
    } catch (e, stack) {
      row.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
    }
    if (row['status'] != 'pass') {
      row['mainState'] = h.state;
      try {
        row['mainFailureScreenshot'] =
            await h.captureCurrentFrame('main-failure-$id');
      } catch (captureError) {
        row['mainFailureScreenshotError'] = '$captureError';
      }
      final lastAck = await _read('$_qaPath/$run/ack.json');
      if (lastAck != null) row['lastToolboxAck'] = lastAck;
    }
    rows.add(row);
    await report();
  }

  await test('native.bootstrap', (row) async {
    await _until(() => WindowBridge.supported && h.page.nativeWindows == true,
        'No actual native window bridge; headless engine is not native acceptance',
        seconds: 20);
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    Map<String, dynamic>? ready;
    while (ready == null && DateTime.now().isBefore(deadline)) {
      ready = await _read('$_qaPath/$run/toolbox-ready.json');
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    _check(ready != null && ready['supported'] == true,
        'Second real FlutterEngine did not become ready');
    _check(ready!['persistDraft'] == false,
        'Replica has draft persistence enabled');
    nativeReady = true;
    row['toolboxReady'] = ready;
    row['diagnostics'] = await diagnostics();
  });
  if (!nativeReady) {
    await report();
    return;
  }
  await test('native.fixed-layout', (row) async {
    final d = await diagnostics();
    row['diagnostics'] = d;
    bool size(dynamic value, int width, int height) =>
        value is List &&
        value.length == 2 &&
        ((value[0] as num) - width).abs() < .01 &&
        ((value[1] as num) - height).abs() < .01;
    _check(
        size(d['mainContentSize'], 810, 667) &&
            size(d['toolboxContentSize'], 410, 640),
        'Native fixed content sizes differ');
    _check(d['mainResizable'] == false && d['toolboxResizable'] == false,
        'Native windows must not be resizable');
    _check(
        d['toolbarVisible'] == false &&
            d['hasToolboxEngine'] == true &&
            d['toolboxVisible'] == true,
        'Native toolbar must be absent and separate toolbox engine/window live');
    _check((d['mainTitle'] as String).contains('PVZ Studio'),
        'Native main window title differs');
    _check(h.all((w) => w is Scrollable).isEmpty,
        'Main page must not have a scrolling container');
    final background = h
        .find((w) => w.key == const ValueKey('original-window-background-1'))
        .renderObject as RenderBox;
    final board = h
        .find((w) => w is CustomPaint && w.painter is BoardPainter)
        .renderObject as RenderBox;
    final delta = board.localToGlobal(Offset.zero) -
        background.localToGlobal(Offset.zero);
    final toggle = h
        .find((w) => w.key == const ValueKey('toolbox-visibility-toggle'))
        .renderObject as RenderBox;
    final toggleTop = toggle.localToGlobal(Offset.zero).dy;
    final backgroundTop = background.localToGlobal(Offset.zero).dy;
    _check(
        toggleTop >= 0 &&
            toggleTop + toggle.size.height <= 32.1 &&
            (backgroundTop - 32).abs() < .1,
        'Toolbox toggle must stay in operation bar y0..32 wholly above PVZ');
    _check((delta.dx - 3).abs() < .1 && (delta.dy - 27).abs() < .1,
        'PVZ title decoration must remain above board below operation bar');
    _check(background.size == const Size(810, 635),
        'Original PVZ window background must keep fixed 810x635 bounds');
    final before = board.localToGlobal(Offset.zero),
        pointer = board.localToGlobal(board.size.center(Offset.zero));
    GestureBinding.instance.handlePointerEvent(PointerScrollEvent(
        kind: ui.PointerDeviceKind.mouse,
        position: pointer,
        scrollDelta: const Offset(0, -300)));
    await h.settle();
    final negative = board.localToGlobal(Offset.zero);
    GestureBinding.instance.handlePointerEvent(PointerScrollEvent(
        kind: ui.PointerDeviceKind.mouse,
        position: pointer,
        scrollDelta: const Offset(0, 300)));
    await h.settle();
    final positive = board.localToGlobal(Offset.zero);
    _check(
        (negative - before).distance < .1 && (positive - before).distance < .1,
        'Mouse wheel moved fixed main page/board');
    final header = background.localToGlobal(const Offset(500, 10));
    GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: 2, position: header, buttons: 1));
    GestureBinding.instance.handlePointerEvent(PointerMoveEvent(
        pointer: 2,
        position: header + const Offset(0, 120),
        delta: const Offset(0, 120),
        buttons: 1));
    GestureBinding.instance.handlePointerEvent(
        PointerUpEvent(pointer: 2, position: header + const Offset(0, 120)));
    await h.settle();
    _check((board.localToGlobal(Offset.zero) - before).distance < .1,
        'Dragging the PVZ header moved the main page');
    row['fixedBoardOrigins'] = {
      'before': [before.dx, before.dy],
      'wheelMinus300': [negative.dx, negative.dy],
      'wheelPlus300': [positive.dx, positive.dy]
    };
  });
  await test('sync.card-to-main-plant', (row) async {
    row['toolbox'] =
        await command('selectCard', {'caseId': 'sync.card-to-main-plant'});
    await _until(() => h.state['selectedType'] == 'sunflower',
        'Toolbox card did not arrive in main engine');
    final board = h
        .find((w) => w is CustomPaint && w.painter is BoardPainter)
        .renderObject as RenderBox;
    await h.tapAt(
        board.localToGlobal(BoardGeometry(session.document).cellCenter(0, 0)));
    await _until(
        () =>
            session.document.pieces.length == 1 &&
            session.document.pieces.single.type == 'sunflower',
        'Main real pointer did not plant toolbox-selected card');
    row['canonicalFingerprint'] = session.document.fingerprint;
    row['convergedToolbox'] = await command('snapshot', {
      'caseId': 'sync.card-to-main-plant-converged',
      'fingerprint': session.document.fingerprint
    });
  });
  await test('sync.toolbox-map-to-main', (row) async {
    row['toolbox'] =
        await command('changeMap', {'caseId': 'sync.toolbox-map-to-main'});
    await _until(
        () =>
            session.document.mapId == 'day' && session.document.pieces.isEmpty,
        'Toolbox map apply did not change canonical main document');
    row['canonicalMap'] = session.document.mapId;
  });
  await test('sync.toolbox-preset-to-main', (row) async {
    row['toolbox'] =
        await command('preset', {'caseId': 'sync.toolbox-preset-to-main'});
    final expected =
        WebsiteCodec.encode(OriginalCatalog.formations.first.decode());
    await _until(() => WebsiteCodec.encode(session.document) == expected,
        'Toolbox preset did not match canonical source formation in main');
    row['objectCount'] = session.document.pieces.length;
  });
  await test('sync.style-updates-main-asset', (row) async {
    row['toolbox'] =
        await command('style', {'caseId': 'sync.style-updates-main-asset'});
    await _until(
        () =>
            h.state['windowStyle'] == 3 &&
            h
                .all((w) =>
                    w.key == const ValueKey('original-window-background-3'))
                .isNotEmpty,
        'Toolbox style must change actual main PVZ asset, not only radio state');
    final image = h
        .find((w) => w.key == const ValueKey('original-window-background-3'))
        .widget as Image;
    _check(
        image.image is AssetImage &&
            (image.image as AssetImage).assetName.endsWith('/window3.png'),
        'Main window style asset differs');
  });
  await test('sync.rapid-edits-before-native-ack', (row) async {
    final ack = await command(
        'rapid', {'caseId': 'sync.rapid-edits-before-native-ack'});
    row['toolbox'] = ack;
    _check(ack['inFlightAtSecond'] == true,
        'Second pointer did not precede native ACK');
    await _until(
        () =>
            session.document.display['泥土'] == ack['expectedSoil'] &&
            session.document.display['脑子'] == ack['expectedBrain'],
        'Canonical main dropped one of two rapid toolbox edits');
    row['canonicalDisplay'] = session.document.display;
    row['convergedToolbox'] = await command('snapshot', {
      'caseId': 'sync.rapid-edits-converged',
      'fingerprint': session.document.fingerprint
    });
  });
  await test('native.hide-show-retains-toolbox-state', (row) async {
    final marker = 'retain-$run';
    await command(
        'prepareRetain', {'marker': marker, 'caseId': 'native.before-hide'});
    await _until(() => h.state['selectedType'] == 'sunflower',
        'Selected card before hide did not synchronize');
    final before = session.document.fingerprint;
    final beforeDiag = await diagnostics();
    _check(h.all((w) => w is Text && w.data == '隐藏工具箱').isNotEmpty,
        'Visible toolbox toggle must offer hide');
    await h.keyTap('toolbox-visibility-toggle');
    await _until(() => h.page.toolboxVisible == false,
        'Native hide event did not update operation bar');
    final hidden = await diagnostics();
    _check(
        hidden['toolboxVisible'] == false &&
            hidden['hasToolboxEngine'] == true &&
            h.all((w) => w is Text && w.data == '显示工具箱').isNotEmpty,
        'Pointer hide must retain toolbox engine and update operation bar');
    await h.keyTap('toolbox-visibility-toggle');
    await _until(() => h.page.toolboxVisible == true,
        'Native show event did not update operation bar');
    final shown = await diagnostics();
    _check(
        shown['toolboxVisible'] == true &&
            h.all((w) => w is Text && w.data == '隐藏工具箱').isNotEmpty,
        'Native show did not restore toolbox window');
    row.addAll({
      'before': beforeDiag,
      'hidden': hidden,
      'shown': shown,
      'invocation': 'real pointer clicks on Flutter operation-bar toggle'
    });
    row['retainedToolbox'] = await command(
        'assertRetained', {'marker': marker, 'caseId': 'native.after-show'});
    _check(session.document.fingerprint == before,
        'Hiding/reopening changed canonical formation');
  });
  await test('replica.no-competing-draft', (row) async {
    row['toolbox'] =
        await command('finish', {'caseId': 'replica.no-competing-draft'});
    await session.flush();
    _check(!session.persistDraft && (await repo.listDrafts()).isEmpty,
        'QA main must not write real or competing drafts');
  });
  await report();
  // Deliberately leave both actual windows running for independent screenshots,
  // a real native close-button AX press, and operation-bar reopen acceptance.
}
