import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/library/export_settings_dialog.dart';
import 'package:pvz_formation_editor/platform/export_preferences.dart';
import 'sidebar_title_smoke.dart' as h;

Future<void> main() async {
  h.TitleBinding();
  final temporary =
      await Directory.systemTemp.createTemp('pvz-export-settings-');
  ExportPreferences.fileOverride = File('${temporary.path}/preferences.json');
  ExportPreferences.documentsDirectoryOverride =
      Directory('${temporary.path}/Documents');
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
          builder: (context) => Scaffold(
              body: Center(
                  child: TextButton(
                      key: const ValueKey('launch'),
                      onPressed: () => showExportSettings(context),
                      child: const Text('设置')))))));
  await h.settle();
  final rows = <Map<String, dynamic>>[];
  try {
    await h.tap('launch');
    await h.settle();
    for (final key in [
      'export-settings-dialog',
      'export-settings-directory',
      'export-settings-pick',
      'export-settings-default',
      'export-settings-save',
      'export-settings-cancel'
    ]) {
      h.check(
          h.find((w) => w.key == ValueKey(key)).length == 1, 'missing $key');
    }
    h.check(
        h
            .find((w) =>
                w is Text && (w.data ?? '').contains('PvzFormationEditor'))
            .isNotEmpty,
        'default folder explained');
    await h.tap('export-settings-default');
    await h.tap('export-settings-cancel');
    await h.settle();
    h.check(
        h
            .find((w) => w.key == const ValueKey('export-settings-dialog'))
            .isEmpty,
        'cancel closes dialog');
    h.check(errors.isEmpty, 'Flutter errors');
    rows.add(
        {'id': '410x640-settings-layout-default-and-cancel', 'status': 'pass'});
  } catch (e, s) {
    rows.add({
      'id': '410x640-settings-layout-default-and-cancel',
      'status': 'fail',
      'error': '$e',
      'stack': '$s'
    });
  }
  final report = {
    'results': rows,
    'flutterErrors': errors.map((e) => '${e.exception}').toList()
  };
  File('${Directory.systemTemp.path}/pvz-export-settings-report.json')
      .writeAsStringSync(jsonEncode(report));
  stdout.writeln(jsonEncode(report));
  ExportPreferences.fileOverride = null;
  ExportPreferences.documentsDirectoryOverride = null;
  await temporary.delete(recursive: true);
  exit(rows.every((r) => r['status'] == 'pass') && errors.isEmpty ? 0 : 1);
}
