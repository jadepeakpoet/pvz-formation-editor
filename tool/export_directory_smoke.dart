// Temporary paths and mocked native pickers; real filesystem writes and UI.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/library/export_settings_dialog.dart';
import 'package:pvz_formation_editor/platform/export_preferences.dart';
import 'package:pvz_formation_editor/platform/project_files.dart';
import 'parity_support.dart';
import 'sidebar_title_smoke.dart' as h;

Future<void> main() async {
  h.TitleBinding();
  final temporary =
      await Directory.systemTemp.createTemp('pvz-export-directory-');
  final documents = await Directory('${temporary.path}/Documents').create();
  final preference = File('${temporary.path}/support/export-preferences.json');
  ExportPreferences.fileOverride = preference;
  ExportPreferences.documentsDirectoryOverride = documents;
  final expected = '${documents.path}/PvzFormationEditor';
  final custom = await Directory('${temporary.path}/My formations').create();
  final customChild =
      await Directory('${custom.path}/PvzFormationEditor').create();
  final calls = <MethodCall>[];
  ParityBinding.handlers['pvz_formation_editor/files'] = (call) async {
    calls.add(call);
    final arguments = call.arguments as Map;
    final directory = arguments['directory'] as String?;
    h.check(directory != null && await Directory(directory).exists(),
        'Picker must receive an existing directory');
    if (call.method == 'chooseSavePath') {
      return '$directory/${arguments['name']}';
    }
    if (call.method == 'chooseExportDirectory') return custom.path;
    throw StateError('Unexpected native picker ${call.method}');
  };
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  try {
    h.check(
        await ExportPreferences.defaultDirectory() == expected &&
            await ExportPreferences.loadDirectory() == expected,
        'Unset preference must resolve dedicated application subfolder');
    h.check(!await Directory(expected).exists() && !await preference.exists(),
        'Reading default path must not create a directory or preference');
    await preference.parent.create(recursive: true);
    final oldRootPreference = jsonEncode({'directory': '${documents.path}/'});
    await preference.writeAsString(oldRootPreference);
    h.check(
        await ExportPreferences.loadDirectory() == expected &&
            await preference.readAsString() == oldRootPreference &&
            !await Directory(expected).exists(),
        'Persisted Documents root must resolve subfolder without writes');
    await ExportPreferences.setDirectory(custom.path);
    h.check(await ExportPreferences.loadDirectory() == custom.path,
        'Explicit custom folder must remain unchanged');
    await ExportPreferences.setDirectory(customChild.path);
    h.check(await ExportPreferences.loadDirectory() == customChild.path,
        'A custom app-named folder must not receive another nested folder');
    await ExportPreferences.setDirectory(null);
    h.check(
        await ExportPreferences.loadDirectory() == expected &&
            !await Directory(expected).exists(),
        'Reset should resolve, not create');

    final bytes = Uint8List.fromList(utf8.encode('formation-export'));
    final saved =
        await ProjectFiles.saveWithBackup('first.png', bytes, 'image/png');
    h.check(
        saved?.path == '$expected/first.png' &&
            utf8.decode(await File(saved!.path).readAsBytes()) ==
                'formation-export',
        'Export must create dedicated folder and save exact content');
    final second =
        await ProjectFiles.saveWithBackup('second.png', bytes, 'image/png');
    h.check(
        second?.path == '$expected/second.png' &&
            await ExportPreferences.loadDirectory() == expected &&
            !await Directory('$expected/PvzFormationEditor').exists(),
        'Remembered exports must not append nested application folders');
    await ExportPreferences.setDirectory(custom.path);
    final customSave =
        await ProjectFiles.saveWithBackup('custom.png', bytes, 'image/png');
    h.check(customSave?.path == '${custom.path}/custom.png',
        'Export should honor explicit custom directory');
    await ExportPreferences.setDirectory(null);
    await Directory(expected).delete(recursive: true);
    final selected = await ExportPreferences.pickDirectory();
    h.check(
        selected == custom.path &&
            (calls.last.arguments as Map)['directory'] == expected &&
            await Directory(expected).exists(),
        'Directory picker should start in created application folder');

    await ExportPreferences.setDirectory(custom.path);
    await Directory(expected).delete(recursive: true);
    runApp(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    key: const ValueKey('launch'),
                    onPressed: () => showExportSettings(context),
                    child: const Text('设置'))))));
    await h.settle();
    await h.tap('launch');
    await h.settle();
    TextField field() => h
        .find((w) => w.key == const ValueKey('export-settings-directory'))
        .single
        .widget as TextField;
    h.check(field().controller!.text == custom.path,
        'Settings must display actual custom path');
    await h.tap('export-settings-default');
    h.check(
        field().controller!.text == expected &&
            !await Directory(expected).exists(),
        'Reset UI must show dedicated path without creating it');
    await h.tap('export-settings-cancel');
    h.check(await ExportPreferences.loadDirectory() == custom.path,
        'Canceling reset must preserve selected preference');
    await h.tap('launch');
    await h.settle();
    await h.tap('export-settings-default');
    await h.tap('export-settings-save');
    await h.settle();
    h.check(
        await ExportPreferences.loadDirectory() == expected &&
            !await Directory(expected).exists() &&
            (jsonDecode(await preference.readAsString()) as Map)['directory'] ==
                null,
        'Saving default should retain a dynamic default without creating folder');
    await h.tap('launch');
    await h.settle();
    h.check(field().controller!.text == expected,
        'Reopened default settings must display dedicated path');
    await h.tap('export-settings-cancel');
    h.check(
        errors.isEmpty, errors.map((e) => e.exceptionAsString()).join('\n'));
    stdout.writeln(
        'PASS dedicated Documents subfolder, legacy root migration without writes, custom path preservation, no nesting, export/picker directory creation, real temporary file content, settings reset/save/cancel');
  } finally {
    runApp(const SizedBox.shrink());
    await h.settle();
    ParityBinding.handlers.remove('pvz_formation_editor/files');
    ExportPreferences.fileOverride = null;
    ExportPreferences.documentsDirectoryOverride = null;
    await temporary.delete(recursive: true);
  }
  exit(0);
}
