// Real Flutter library import UI + temporary SQLite/files. Only the native
// file dialog channel is mocked. The .dat fixture below is synthetic primary-
// schema data, not an actual Windows 1051 capture; no live-game claim is made.
// Compile this entry point with Flutter's frontend_server (--target=flutter,
// --packages .dart_tool/package_config.json), then run the resulting dill using
// that SDK's flutter_tester and --flutter-assets-dir=build/flutter_assets.
// Writes /tmp/pvz-game-save-ui-report.json; exits nonzero on any failed check.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'mock_desktop_dialogs.dart';

late Dialogs dialogs;

class Binding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      dialogs = Dialogs(super.createBinaryMessenger());
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(logicalConstraints: BoxConstraints.tight(Size(1240, 800)), physicalConstraints: BoxConstraints.tight(Size(1240, 800)), devicePixelRatio: 1);
}

class Dialogs extends BinaryMessenger {
  final BinaryMessenger delegate;
  Dialogs(this.delegate);
  String? pickPath, savePath;
  final calls = <MethodCall>[];
  @override
  Future<ByteData?> send(String channel, ByteData? data) async {
    if (channel != 'pvz_formation_editor/files') {
      return delegate.send(channel, data);
    }
    const codec = StandardMethodCodec();
    final call = codec.decodeMethodCall(data);
    calls.add(call);
    if (call.method == 'chooseSavePath') {
      return codec.encodeSuccessEnvelope(savePath);
    }
    if (call.method == 'pickFormation') {
      return codec.encodeSuccessEnvelope(pickPath == null
          ? null
          : {'path': pickPath, 'bytes': await File(pickPath!).readAsBytes()});
    }
    throw StateError('Unexpected file method ${call.method}');
  }

  @override
  void setMessageHandler(
          String channel, Future<ByteData?>? Function(ByteData?)? handler) =>
      delegate.setMessageHandler(channel, handler);
  @override
  Future<void> handlePlatformMessage(
          String channel, ByteData? data, void Function(ByteData?)? callback) =>
      // ignore: deprecated_member_use
      delegate.handlePlatformMessage(channel, data, callback);
}

void check(bool value, String label) {
  if (!value) throw StateError(label);
}

void walk(Element e, void Function(Element) visit) {
  visit(e);
  e.visitChildren((c) => walk(c, visit));
}

Element? find(bool Function(Widget) predicate) {
  Element? result;
  walk(WidgetsBinding.instance.rootElement!, (e) {
    if (predicate(e.widget)) result = e;
  });
  return result;
}

dynamic get page => (find((w) => w is app.EditorPage) as StatefulElement).state;
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 350));
Future<void> clickText(String text) async {
  final e = find((w) => w is Text && w.data == text);
  check(e != null, 'Missing $text');
  final b = e!.renderObject as RenderBox;
  final p = b.localToGlobal(b.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: p, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 1, position: p));
  await settle();
}

Uint8List save(
    {int scene = 2,
    int sun = 50,
    int? seed = 42,
    bool asleep = true,
    bool mimic = true,
    int? gridKind = 3,
    bool dead = false}) {
  final result = BytesBuilder();
  void u(int n) {
    final b = ByteData(4)..setUint32(0, n, Endian.little);
    result.add(b.buffer.asUint8List());
  }

  void block(Uint8List bytes) {
    u(bytes.length);
    result.add(bytes);
  }

  final header = ByteData(12)
    ..setUint32(0, 0xfeeddead, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, 0x12345678, Endian.little);
  block(header.buffer.asUint8List());
  final board = ByteData(0x564c);
  void field(int offset, int value) =>
      board.setInt32(offset - 0x164, value, Endian.little);
  field(0x554c, scene);
  field(0x5560, sun);
  final rows = scene == 2 || scene == 3 ? 6 : 5;
  for (var r = 0; r < 6; r++) {
    final type = r >= rows
        ? 0
        : (scene == 2 || scene == 3) && (r == 2 || r == 3)
            ? 2
            : 1;
    field(0x5d8 + r * 4, type);
    for (var c = 0; c < 9; c++) {
      field(
          0x168 + (c * 6 + r) * 4,
          type == 0
              ? 2
              : type == 2
                  ? 3
                  : 1);
    }
  }
  block(board.buffer.asUint8List());
  void array(int stride, {ByteData? item}) {
    u(item == null ? 0 : 1);
    u(item == null ? 0 : 1);
    u(item == null ? 0 : 1);
    if (item == null) {
      block(Uint8List(0));
      return;
    }
    final record = Uint8List(stride);
    record.setRange(0, item.lengthInBytes, item.buffer.asUint8List());
    ByteData.sublistView(record).setUint32(stride - 4, 0x10000, Endian.little);
    block(record);
  }

  array(0x15c);
  ByteData? plant;
  if (seed != null) {
    plant = ByteData(0x148)
      ..setInt32(0x24, seed, Endian.little)
      ..setInt32(0x28, 2, Endian.little)
      ..setInt32(0x1c, 1, Endian.little)
      ..setInt32(0x138, mimic ? 48 : -1, Endian.little)
      ..setUint8(0x141, dead ? 1 : 0)
      ..setUint8(0x143, asleep ? 1 : 0)
      ..setUint8(0x144, 1);
  }
  array(0x14c, item: plant);
  array(0x94);
  array(0xd4);
  array(0x48);
  final grid = gridKind == null
      ? null
      : (ByteData(0xe8)
        ..setInt32(8, gridKind, Endian.little)
        ..setInt32(0x10, 2, Endian.little)
        ..setInt32(0x14, 1, Endian.little));
  array(0xec, item: grid);
  for (var i = 0; i < 6; i++) {
    array(4);
  }
  for (var i = 0; i < 6; i++) {
    block(Uint8List(0));
  }
  u(0xfeeddead);
  return result.takeBytes();
}

Future<void> main() async {
  Binding();
  installMockDesktopDialogs((call) async {
    if (call.method == 'chooseSavePath') return dialogs.savePath;
    if (call.method == 'pickFormation') return dialogs.pickPath == null ? null : {
      'path': dialogs.pickPath,
      'bytes': await File(dialogs.pickPath!).readAsBytes(),
    };
    throw StateError('Unexpected picker ${call.method}');
  });
  final dir = await Directory.systemTemp.createTemp('pvz-save-ui-');
  final repo = await FormationRepository.open('${dir.path}/library.sqlite');
  final source = File('${dir.path}/game1_13.dat');
  final bytes = save();
  await source.writeAsBytes(bytes);
  dialogs.pickPath = source.path;
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  final current = <EditorSession>[], tabs = <EditorSession>[];
  runApp(MaterialApp(
      home: app.LibraryPage(
          repository: repo,
          onOpenSession: (s) async {
            current.add(s);
          },
          onOpenTab: (s) async {
            tabs.add(s);
          })));
  await settle();
  await settle();
  dynamic library() =>
      (find((w) => w is app.LibraryPage) as StatefulElement).state;
  try {
    var task = library().importGameSave() as Future<void>;
    await settle();
    check(
        find((w) => w is Text && (w.data ?? '').contains('源 .dat 文件不会被修改')) !=
            null,
        'warning visible');
    check(
        find((w) => w is Text && (w.data ?? '').contains('植物：1，场地物品：1')) !=
            null,
        'scene counts visible');
    await clickText('取消');
    await task;
    check(current.isEmpty && tabs.isEmpty, 'cancel leaves editors unchanged');
    task = library().importGameSave() as Future<void>;
    await settle();
    await clickText('导入当前标签');
    await task;
    check(current.length == 1 && tabs.isEmpty, 'current tab target');
    check(
        current.single.filePath == null &&
            current.single.revision == 0 &&
            current.single.undoDepth == 0,
        'import starts independent document history without binary path');
    check(
        current.single.document.pieces.length == 2 &&
            current.single.document.pieces.first.asleep,
        'import actual placement');
    await library().importGameSave();
    await settle();
    check(current.length == 1 && tabs.isEmpty,
        'duplicate imported document creates no second editor');
    final alternate = File('${dir.path}/game2_13.dat');
    final alternateBytes = save(sun: 75);
    await alternate.writeAsBytes(alternateBytes);
    dialogs.pickPath = alternate.path;
    task = library().importGameSave() as Future<void>;
    await settle();
    await clickText('导入新标签');
    await task;
    check(
        tabs.length == 1 &&
            tabs.single.id != current.single.id &&
            tabs.single.filePath == null,
        'new independent tab without binary path');
    check(tabs.single.document.sunValue == 75,
        'new tab contains distinct source');
    check(
        base64.encode(await alternate.readAsBytes()) ==
            base64.encode(alternateBytes),
        'alternate source binary unchanged');
    check(base64.encode(await source.readAsBytes()) == base64.encode(bytes),
        'source binary unchanged');
    final malformed = File('${dir.path}/user1.dat');
    await malformed.writeAsString('invalid');
    dialogs.pickPath = malformed.path;
    await library().importGameSave();
    await settle();
    check(current.length == 1 && tabs.length == 1,
        'malformed file creates no session');
    check(errors.isEmpty, 'Flutter errors $errors');
    stdout.writeln(
        'PASS save import UI: warnings/counts, cancel, current/newtab, initial history, duplicate prevention, no binary path, unchanged source, malformed rejected');
    await File('${Directory.systemTemp.path}/pvz-game-save-ui-report.json').writeAsString(jsonEncode({
      'pass': 11,
      'errors': errors,
      'fixture': 'synthetic primary schema',
      'filePanel': 'mocked',
      'actual1051File': 'notRun'
    }));
    for (final s in [...current, ...tabs]) {
      s.dispose();
    }
    runApp(const SizedBox.shrink());
    await settle();
    await repo.close();
    await dir.delete(recursive: true);
    exit(0);
  } catch (e, stack) {
    stderr.writeln('$e\n$stack\n$errors');
    exit(1);
  }
}
