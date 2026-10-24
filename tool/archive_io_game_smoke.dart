// ignore_for_file: invalid_use_of_visible_for_testing_member, curly_braces_in_flow_control_structures
// Real library widgets, pointer events, disk and SQLite. OS dialog and game channel isolated.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/domain/archive_bundle.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/archive_files.dart';
import 'package:pvz_formation_editor/library/game_panel.dart';
import 'package:pvz_formation_editor/platform/export_preferences.dart';
import 'package:pvz_formation_editor/platform/project_files.dart';
import 'package:pvz_formation_editor/platform/app_theme.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';
import 'sidebar_title_smoke.dart' as h;

Future<void> main() async {
  h.TitleBinding();
  await OriginalAssets.ensureLoaded();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  final temp = await Directory.systemTemp.createTemp('pvz-library-io-game-');
  final source = await FormationRepository.open('${temp.path}/source.sqlite');
  final target = await FormationRepository.open('${temp.path}/target.sqlite');
  String? picked, saved;
  final methods = <String>[];
  int writes = 0;
  final clearFlags = <bool>[];
  var clipboard = '';
  ParityBinding.handlers[SystemChannels.platform.name] = (call) async {
    if (call.method == 'Clipboard.setData') {
      clipboard = (call.arguments as Map)['text'] as String;
    }
    return null;
  };
  final formation = Formation(
      mapId: 'day',
      pieces: [Piece(id: 'one', type: 'pea', row: 0, col: 0, layer: 10)]);
  ProjectFiles.desktopDialogOverride =
      ({required save, required name}) async => save ? saved : picked;
  ExportPreferences.fileOverride = File('${temp.path}/prefs.json');
  ExportPreferences.documentsDirectoryOverride = temp;
  ParityBinding.handlers['pvz_formation_editor/game'] = (call) async {
    methods.add(call.method);
    if (call.method == 'listGames')
      return [
        {
          'pid': 123,
          'timestamp': 0x49ecf563,
          'title': 'Isolated game',
          'executable': 'fake.exe',
          'version': '1.0.0.1051',
          'canRead': true,
          'canWrite': true
        }
      ];
    if (call.method == 'readFormation')
      return {
        'pid': 123,
        'version': '1.0.0.1051',
        'map': 'day',
        'sunValue': 8000,
        'includeZombies': (call.arguments as Map)['includeZombies'] == true,
        'pieces': []
      };
    if (call.method == 'applyFormation') {
      writes++;
      final args = call.arguments as Map;
      clearFlags.add(args['target']['includeZombies'] == true);
      h.check(
          args['target']['pieces'].length == 1, 'Selected archive is written');
      h.check(args['target']['sunValue'] == 8000, 'Current game sun preserved');
      return {
        'before': args['expectedBefore'],
        'after': {
          'pid': 123,
          'version': '1.0.0.1051',
          ...(args['target'] as Map)
        }
      };
    }
    throw StateError('Unexpected game call: ${call.method}');
  };
  try {
    await source.saveArchive(
        id: 'one',
        name: '中文阵型',
        document: formation.toJson(),
        note: '备注\n第二行',
        tags: ['测试']);
    await source.saveArchive(
        id: 'two', name: '另一个阵型', document: Formation(mapId: 'roof').toJson());
    final original = await source.listArchives();
    saved = '${temp.path}/完整存档.pvzlib.json';
    h.check(await ArchiveFiles.exportCollection(original),
        'Export writes a real file');
    final bundle = await File(saved).readAsString();
    h.check(ArchiveBundle.decode(bundle).length == 2, 'Complete batch');
    runApp(MaterialApp(
        theme: buildAppTheme(),
        home: app.LibraryPage(repository: target, showTitle: false)));
    await h.settle();
    await h.settle();
    final dynamic state =
        (h.find((w) => w is app.LibraryPage).single as StatefulElement).state;
    picked = saved;
    await state.importProject();
    await h.settle();
    final rows = await target.listArchives();
    h.check(rows.length == 2, 'Library import writes both archives');
    for (final record in original) {
      final match = rows.singleWhere((a) => a.name == record.name);
      h.check(
          Formation.fromJson(match.document).fingerprint ==
              Formation.fromJson(record.document).fingerprint,
          'Full document preserved');
      h.check(
          match.note == record.note &&
              match.tags.join(',') == record.tags.join(','),
          'Metadata preserved');
    }
    await state.importProject();
    h.check((await target.listArchives()).length == 2,
        'Repeat import skips duplicates');
    final malformed = jsonDecode(bundle);
    malformed['archives'].add({'name': 'bad'});
    picked = '${temp.path}/bad.json';
    await File(picked).writeAsString(jsonEncode(malformed));
    await state.importProject();
    h.check((await target.listArchives()).length == 2,
        'Malformed later entry writes nothing');
    picked = null;
    await state.importProject();
    h.check((await target.listArchives()).length == 2,
        'Cancel import leaves archives unchanged');
    saved = null;
    h.check(!await ArchiveFiles.exportCollection(rows),
        'Canceled export returns false');
    picked = '${temp.path}/oversized.json';
    await File(picked)
        .writeAsBytes(List.filled(ProjectFiles.maxProjectBytes + 1, 32));
    await state.importProject();
    h.check((await target.listArchives()).length == 2,
        'Oversized import leaves library unchanged');
    final item = rows.singleWhere((a) => a.name == '中文阵型');
    await h.tap('library-item-archive:${item.id}');
    await h.settle();
    final copy =
        h.find((w) => w.key == const ValueKey('library-copy-code')).single;
    final apply =
        h.find((w) => w.key == const ValueKey('library-apply-game')).single;
    h.check(
        copy.findAncestorWidgetOfExactType<Row>() ==
            apply.findAncestorWidgetOfExactType<Row>(),
        'Copy and apply share the same action group');
    h.check(copy.widget is OutlinedButton && apply.widget is FilledButton,
        'Copy and apply have visible button surfaces');
    final formatGroup = h.find((w) => w is RadioGroup<FormationFormat>).single.widget
        as RadioGroup<FormationFormat>;
    h.check(formatGroup.groupValue == FormationFormat.toolkit,
        'Archive copy defaults to Toolkit with mutually exclusive format choices');
    await h.tap('library-copy-format-website');
    await h.tap('library-copy-code');
    h.check(FormationExchange.detectFormat(clipboard) == FormationFormat.website &&
        FormationExchange.decode(clipboard).pieces.length == formation.pieces.length,
        'Archive detail copies a loadable website code');
    await h.tap('library-copy-format-toolkit');
    await h.tap('library-copy-code');
    h.check(FormationExchange.detectFormat(clipboard) == FormationFormat.toolkit,
        'Archive Toolkit action keeps the standard format');
    await h.tap('library-apply-game');
    await h.settle();
    h.check(writes == 1 && h.find((w) => w is GamePanel).isEmpty,
        'Detail apply writes directly without opening file tools');
    h.check(!clearFlags.single, 'Clearing zombies is unchecked by default');
    await h.tap('library-clear-zombies');
    await h.tap('library-apply-game');
    await h.settle();
    h.check(clearFlags.last, 'Checked clear option reaches the native write');
    await h.tap('library-detail-back');
    await h.tap('library-menu-archive:${item.id}');
    await h.tapElement(h.find((w) => w is Text && w.data == '应用阵型').single);
    await h.settle();
    h.check(writes == 3 && !methods.contains('listSaveFiles'),
        'More menu uses the same direct apply action');
    h.check(
        errors.isEmpty, errors.map((e) => e.exceptionAsString()).join('\n'));
    stdout.writeln(
        'PASS archive disk export/import, metadata, repeat duplicates, malformed/oversized/canceled files, direct apply and item More menu');
  } finally {
    runApp(const SizedBox.shrink());
    await h.settle();
    await source.close();
    await target.close();
    ProjectFiles.desktopDialogOverride = null;
    ExportPreferences.fileOverride = null;
    ExportPreferences.documentsDirectoryOverride = null;
    ParityBinding.handlers.remove('pvz_formation_editor/game');
    await temp.delete(recursive: true);
  }
  exit(0);
}
