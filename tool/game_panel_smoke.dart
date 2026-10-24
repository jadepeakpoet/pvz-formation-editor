// Real Flutter GamePanel, simulated game channel. No Windows process is opened.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/game_panel.dart';
import 'package:pvz_formation_editor/platform/game_writes.dart';
import 'formation_io_smoke.dart' as helpers;

late FakeGame fake;

class Binding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      fake = FakeGame(super.createBinaryMessenger());
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      const ViewConfiguration(size: Size(900, 650), devicePixelRatio: 1);
}

class FakeGame extends BinaryMessenger {
  final BinaryMessenger delegate;
  FakeGame(this.delegate);
  int writes = 0;
  bool reject = true, backupBeforeNative = false;
  @override
  Future<ByteData?> send(String channel, ByteData? data) async {
    if (channel != 'pvz_formation_editor/game') {
      return delegate.send(channel, data);
    }
    const codec = StandardMethodCodec();
    final call = codec.decodeMethodCall(data);
    switch (call.method) {
      case 'listGames':
        return codec.encodeSuccessEnvelope([
          {
            'pid': 123,
            'timestamp': 0x49ecf563,
            'title': 'Fake supported game',
            'executable': 'fake.exe',
            'version': '1.0.0.1051 en',
            'canRead': true,
            'canWrite': true
          },
          {
            'pid': 124,
            'timestamp': 0,
            'title': 'Fake unsupported game',
            'executable': 'fake2.exe',
            'version': 'unsupported',
            'canRead': false,
            'canWrite': false
          }
        ]);
      case 'listSaveFiles':
        return codec.encodeSuccessEnvelope([]);
      case 'readFormation':
        return codec.encodeSuccessEnvelope({
          'pid': 123,
          'version': '1.0.0.1051 en',
          'map': 'day',
          'sunValue': 50,
          'pieces': [
            {'type': 0, 'row': 0, 'col': 0, 'imitater': false, 'asleep': false}
          ]
        });
      case 'applyFormation':
        writes++;
        backupBeforeNative = (call.arguments as Map)['expectedBefore'] is Map;
        if (!reject) {
          final args = call.arguments as Map;
          return codec.encodeSuccessEnvelope({
            'before': args['expectedBefore'],
            'after': {
              'pid': 123,
              'version': '1.0.0.1051 en',
              ...(args['target'] as Map)
            }
          });
        }
        return codec.encodeErrorEnvelope(
            code: 'game_unavailable', message: 'simulated native refusal');
      default:
        throw StateError('Unexpected game method ${call.method}');
    }
  }

  @override
  void setMessageHandler(String c, Future<ByteData?>? Function(ByteData?)? h) =>
      delegate.setMessageHandler(c, h);
  @override
  Future<void> handlePlatformMessage(
          String c, ByteData? d, void Function(ByteData?)? cb) =>
      // ignore: deprecated_member_use
      delegate.handlePlatformMessage(c, d, cb);
}

Future<void> main() async {
  Binding();
  await OriginalAssets.ensureLoaded();
  final dir = await Directory.systemTemp.createTemp('pvz-game-panel-');
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  final reports = <String>[];
  final archived = <Formation>[], edited = <Formation>[];
  try {
    runApp(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
            body: GamePanel(
                target: Formation(mapId: 'day'),
                onArchive: (f) async {
                  archived.add(f);
                },
                onEdit: (f) async {
                  edited.add(f);
                }))));
    await helpers.settle();
    await helpers.settle();
    dynamic state =
        (helpers.find((w) => w is GamePanel) as StatefulElement).state;
    state.backups = GameWrites(Directory('${dir.path}/backups'));
    helpers.check(state.games.length == 2, 'Two game capabilities displayed');
    await helpers.clickText('获取阵型');
    helpers.check(
        state.snapshot.formation.pieces.length == 1, 'Read snapshot shown');
    await helpers.clickText('加入我的存档');
    await helpers.clickText('在编辑器打开');
    helpers.check(
        archived.single.mapId == 'day' &&
            edited.single.pieces.single.type == 'pea',
        'Archive/edit callbacks exactsnapshot');
    reports
        .add('simulated native list/read and actual read/archive/edit buttons');
    await helpers.clickText('应用到游戏');
    helpers.check(
        fake.writes == 1 &&
            state.error.toString().contains('simulated native refusal'),
        'Native refusal visible');
    helpers.check(
        helpers.find((w) =>
                w is OutlinedButton &&
                w.child is Text &&
                (w.child as Text).data == '回退注入') ==
            null,
        'No injection history controls');
    helpers.check(fake.backupBeforeNative,
        'Current snapshot is passed for consistency checking');
    fake.reject = false;
    await helpers.clickText('应用到游戏');
    helpers.check(
        fake.writes == 2 &&
            state.snapshot.formation.pieces.isEmpty &&
            state.error == null,
        'Simulated success updates scene preview');
    reports.add('backup-before-apply call order and simulated success preview');
    final dropdown = helpers.find((w) => w is DropdownButton<int>)!.widget
        as DropdownButton<int>;
    dropdown.onChanged!(124);
    await helpers.settle();
    final read = helpers
        .find((w) =>
            w is FilledButton &&
            w.child is Text &&
            (w.child as Text).data == '获取阵型')!
        .widget as FilledButton;
    final apply = helpers
        .find((w) =>
            w is OutlinedButton &&
            w.child is Text &&
            (w.child as Text).data == '应用到游戏')!
        .widget as OutlinedButton;
    helpers.check(read.onPressed == null && apply.onPressed == null,
        'Unsupported process controls disabled');
    reports.add('unsupported game read/apply controls disabled');
    helpers.check(errors.isEmpty, 'Flutter errors $errors');
    await File('${dir.path}/report.json').writeAsString(jsonEncode({
      'pass': reports,
      'errors': errors,
      'scope':
          'real Flutter GamePanel; fake native game method channel; no Windows compilation or live-process acceptance'
    }));
    stdout.writeln('PASS ${reports.length}: ${reports.join('; ')}');
    await dir.delete(recursive: true);
    exit(0);
  } catch (e, stack) {
    stderr.writeln('$e\n$stack\n$errors');
    exit(1);
  }
}
