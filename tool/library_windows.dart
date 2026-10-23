// Native acceptance target: FLUTTER_TARGET=tool/library_windows.dart.
// Uses a temporary SQLite repository and three actual native Flutter engines.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

const base = '/tmp/pvz-library-native';
const native = MethodChannel('pvz_formation_editor/windows');
const library = MethodChannel('pvz_formation_editor/library');
Future<void> write(String path, Map value) async {
  final f = File('$path.tmp');
  await f.writeAsString(jsonEncode(value));
  await f.rename(path);
}

Future<Map<String, dynamic>?> read(String path) async {
  final f = File(path);
  if (!await f.exists()) return null;
  try {
    return Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map);
  } catch (_) {
    return null;
  }
}

void check(bool v, String label) {
  if (!v) throw StateError(label);
}

Future<void> until(bool Function() condition, String label) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException(label);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
}

void walk(Element e, void Function(Element) visit) {
  visit(e);
  e.debugVisitOnstageChildren((c) => walk(c, visit));
}

Element? find(bool Function(Widget) pred) {
  Element? result;
  final root = WidgetsBinding.instance.rootElement;
  if (root != null) {
    walk(root, (e) {
      if (pred(e.widget)) result = e;
    });
  }
  return result;
}

Future<void> tap(bool Function(Widget) locate, MethodChannel channel) async {
  await channel.invokeMethod('activateWindow');
  await Future<void>.delayed(const Duration(milliseconds: 120));
  // Activating the native window can complete initial layout and replace Elements.
  // Resolve the live target only after that transition has completed.
  await until(() => find(locate)?.renderObject is RenderBox, 'Live tap target');
  final e = find(locate)!;
  await Scrollable.ensureVisible(e, duration: Duration.zero, alignment: .5);
  await Future<void>.delayed(const Duration(milliseconds: 120));
  final b = e.renderObject as RenderBox;
  final p = b.localToGlobal(b.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: p, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 1, position: p));
  await Future<void>.delayed(const Duration(milliseconds: 350));
}

Future<void> key(String id, MethodChannel channel) async {
  final e = find((w) => w.key == ValueKey(id));
  check(e != null, 'Missing $id');
  await tap((w) => w.key == ValueKey(id), channel);
}

@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  await app.toolboxMain();
  final meta = await read('$base/meta.json');
  final run = meta!['run'] as String;
  while (true) {
    final state = WindowBridge.latestState;
    if (state != null && WindowBridge.supported) {
      final element = find((w) => w is app.EditorPage) as StatefulElement?;
      final dynamic controller = element?.state;
      await write('$base/$run/toolbox-state.json',
          {...state, 'liveOutput': controller?.outputFormation.text ?? ''});
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

@pragma('vm:entry-point')
Future<void> libraryMain() async {
  await app.libraryMain();
  final meta = await read('$base/meta.json');
  final run = meta!['run'] as String;
  int previous = -1;
  while (true) {
    final command = await read('$base/$run/command.json');
    if (command == null || command['id'] == previous) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      continue;
    }
    previous = command['id'] as int;
    final ack = <String, dynamic>{'id': previous, 'status': 'pass'};
    try {
      // A background FlutterEngine can suspend frames before the first library
      // layout. Focus before waiting for widgets, rather than after finding one.
      await library.invokeMethod('activateWindow');
      if (command['name'] == 'close') {
        await library.invokeMethod('close');
        ack['diagnostics'] = await library.invokeMethod('diagnostics');
        await write('$base/$run/ack.json', ack);
        continue;
      }
      await until(
          () => find((w) => w.key == const ValueKey('library-new')) != null,
          'Library UI loaded');
      switch (command['name']) {
        case 'archive':
          await key('library-item-archive:qa-archive', library);
          await key('library-open-preview', library);
          break;
        case 'new':
          await key('library-new', library);
          break;
        case 'file':
          final element = find((w) => w is app.LibraryPage)! as StatefulElement;
          final dynamic controller = element.state;
          final path = '$base/$run/imported.txt';
          await File(path).writeAsString('0');
          final session = EditorSession(controller.repo as FormationRepository,
              document: Formation(), name: 'QA imported file')
            ..filePath = path
            ..fileFormat = 'website';
          await controller.edit(session);
          break;
        case 'close':
          await library.invokeMethod('close');
          break;
        case 'snapshot':
          break;
        default:
          throw StateError('Unknown command');
      }
      ack['diagnostics'] = await library.invokeMethod('diagnostics');
    } catch (e, stack) {
      ack.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
    }
    await write('$base/$run/ack.json', ack);
  }
}

EditorSession? active;
int routes = 0;

class Host extends StatefulWidget {
  final FormationRepository repo;
  final String path;
  const Host(this.repo, this.path, {super.key});
  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => edit());
  }

  Future<void> edit() async {
    EditorSession? current =
        EditorSession(widget.repo, name: 'Native library QA original');
    current.rename('Native library QA saved');
    await current.flush();
    while (current != null) {
      if (!mounted) {
        current.dispose();
        break;
      }
      final session = current;
      active = session;
      routes++;
      final route = MaterialPageRoute<EditorSession>(
          builder: (_) => app.EditorPage(
              session: session,
              libraryPath: widget.path,
              continueArchive: (_) async {}));
      current = await Navigator.push<EditorSession>(context, route);
      // A pop result precedes reverse-animation disposal. The old editor must
      // release its per-engine bridge before the next editor installs a handler.
      await route.completed;
      await session.flush();
      session.dispose();
    }
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Native library QA route host')));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const MethodChannel('pvz_formation_editor/lifecycle')
      .setMethodCallHandler((call) async {
    if (call.method != 'prepareExit') throw MissingPluginException();
    for (final guard in app.exitGuards.reversed.toList()) {
      if (!await guard()) return false;
    }
    return true;
  });
  await OriginalAssets.ensureLoaded();
  final run = '${DateTime.now().microsecondsSinceEpoch}-$pid';
  await Directory('$base/$run').create(recursive: true);
  await write('$base/meta.json', {'run': run, 'pid': pid});
  final path = '$base/$run/test.sqlite';
  final repo = await FormationRepository.open(path);
  await repo.saveArchive(
      id: 'qa-archive',
      name: 'Native library snapshot',
      document: Formation(mapId: 'roof').toJson());
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  runApp(MaterialApp(
      theme: ThemeData(useMaterial3: true), home: Host(repo, path)));
  final rows = <Map<String, dynamic>>[];
  int sequence = 0;
  Future<Map<String, dynamic>> diag() async => Map<String, dynamic>.from(
      (await native.invokeMethod('diagnostics')) as Map);
  Future<void> command(String name) async {
    final id = ++sequence;
    await write('$base/$run/command.json', {'id': id, 'name': name});
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(end)) {
      final ack = await read('$base/$run/ack.json');
      if (ack?['id'] == id) {
        check(ack!['status'] == 'pass', 'Library $name: ${ack['error']}');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('Library command $name');
  }

  Future<Map<String, dynamic>> syncedToolbox() async {
    final end = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(end)) {
      final state = await read('$base/$run/toolbox-state.json');
      if (state != null &&
          state['readOnly'] == active!.readOnly &&
          state['documentJson'] == jsonEncode(active!.document.toJson())) {
        return state;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw TimeoutException('Toolbox did not converge to current main document');
  }

  Future<void> test(
      String id, Future<void> Function(Map<String, dynamic>) body) async {
    final row = <String, dynamic>{'id': id, 'status': 'pass'};
    try {
      await body(row);
      check(errors.isEmpty, 'Flutter errors: $errors');
    } catch (e, stack) {
      row.addAll({'status': 'fail', 'error': '$e', 'stack': '$stack'});
    }
    rows.add(row);
    await write('$base/$run/report.json', {
      'scope':
          'actual native three-engine windows; temporary database; no channel mocks',
      'run': run,
      'pid': pid,
      'cases': rows,
      'errors': errors
    });
    await write('$base/report.json',
        {'run': run, 'pid': pid, 'cases': rows, 'errors': errors});
  }

  await until(
      () => active != null && WindowBridge.supported, 'Main native bridge');
  Future<void> open() async {
    await tap((w) => w.key == const ValueKey('main-library-open'), native);
  }

  Map<String, dynamic>? before;
  String? fingerprint;
  String? originalId;
  await test('library.independent-window-preserves-editor', (row) async {
    before = await diag();
    fingerprint = active!.document.fingerprint;
    originalId = active!.id;
    await open();
    await command('snapshot');
    var after = await diag();
    final visibleDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (after['libraryVisible'] != true &&
        DateTime.now().isBefore(visibleDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      after = await diag();
    }
    row['diagnostics'] = after;
    check(after['libraryVisible'] == true && after['hasLibraryEngine'] == true,
        'Independent library visible');
    check(after['libraryResizable'] == true, 'Library resizable');
    check(jsonEncode(after['libraryContentSize']) == '[900.0,600.0]',
        'Compact library content900x600');
    check(jsonEncode(before!['mainFrame']) == jsonEncode(after['mainFrame']),
        'Main frame unchanged');
    check(
        active!.document.fingerprint == fingerprint && active!.id == originalId,
        'Browsing preserves main document');
  });
  await test('library.archive-opens-main-readonly', (row) async {
    await command('archive');
    await until(() => active?.id == 'qa-archive' && WindowBridge.supported,
        'Archive main route');
    check(active!.readOnly && active!.document.mapId == 'roof',
        'Exact readonly snapshot');
    check(routes == 2, 'Single route replacement');
    row['toolboxReadOnly'] = (await syncedToolbox())['readOnly'];
    row['diagnostics'] = await diag();
  });
  await test('library.hide-and-reopen-retains-engine', (row) async {
    await command('close');
    check((await diag())['libraryVisible'] == false, 'Hidden');
    await open();
    await command('snapshot');
    final value = await diag();
    check(value['libraryVisible'] == true && value['hasLibraryEngine'] == true,
        'Reopened retained engine');
    row['diagnostics'] = value;
  });
  await test('library.new-empty-editor-opens-without-persisting-draft',
      (row) async {
    await command('new');
    await until(
        () =>
            active != null &&
            !active!.readOnly &&
            active!.id != originalId &&
            WindowBridge.supported,
        'New draft route');
    final drafts = await repo.listDrafts();
    check(!drafts.any((d) => d.id == active!.id),
        'Untouched empty editor must remain ephemeral after cross-engine open');
    check(routes == 3, 'One new route');
    row['toolboxReadOnly'] = (await syncedToolbox())['readOnly'];
    row['draftId'] = active!.id;
    row['diagnostics'] = await diag();
  });
  await test('library.first-plant-creates-draft-and-clear-retains-it',
      (row) async {
    await tap((w) => w is CustomPaint && w.painter is BoardPainter, native);
    check(active!.document.pieces.isNotEmpty,
        'Actual board pointer placed a plant');
    await active!.flush();
    check((await repo.listDrafts()).any((d) => d.id == active!.id),
        'First plant persists current draft');
    var replica = await syncedToolbox();
    check(replica['liveOutput'] == FormationExchange.encode(active!.document),
        'Actual secondary engine output updates after planting without Get');
    active!
        .execute('QA clear planted objects', active!.document.copy(pieces: []));
    await active!.flush();
    final saved =
        (await repo.listDrafts()).singleWhere((d) => d.id == active!.id);
    check((saved.document['objects'] as List).isEmpty,
        'Clearing a previously edited formation retains its persisted draft');
    replica = await syncedToolbox();
    check(replica['liveOutput'] == FormationExchange.encode(active!.document),
        'Actual secondary output updates after clearing without Get');
    row['secondaryLiveOutput'] = replica['liveOutput'];
    row['draftId'] = active!.id;
  });
  await test('library.file-association-survives-engine-handoff', (row) async {
    await command('file');
    await until(
        () => active?.name == 'QA imported file' && WindowBridge.supported,
        'Imported file main route');
    check(
        active!.filePath == '$base/$run/imported.txt' &&
            active!.fileFormat == 'website',
        'Explicitly imported source path and format transferred to main');
    check(await File(active!.filePath!).readAsString() == '0',
        'Actual source file preserved');
    check(!(await repo.listDrafts()).any((d) => d.id == active!.id),
        'Unmodified empty imported file preserves association without a draft');
    row['toolboxReadOnly'] = (await syncedToolbox())['readOnly'];
    row['filePath'] = active!.filePath;
  });
  await write('$base/$run/done.json', {
    'pass': rows.where((r) => r['status'] == 'pass').length,
    'fail': rows.where((r) => r['status'] == 'fail').length,
    'pid': pid
  });
}
