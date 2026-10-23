// Real NSSavePanel/NSOpenPanel QA. Only path-provider storage is redirected;
// the product files channel remains registered by the actual macOS runner.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pvz_formation_editor/platform/export_preferences.dart';
import 'package:pvz_formation_editor/platform/project_files.dart';
import 'package:pvz_formation_editor/storage/file_backups.dart';

const base = '/tmp/pvz-native-file-dialog';

class IsolatedPaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => '$base/support';
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> writeJson(String name, Object value) async {
  final file = File('$base/$name.tmp');
  await file.writeAsString(jsonEncode(value), flush: true);
  await file.rename('$base/$name');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = IsolatedPaths();
  const MethodChannel('pvz_formation_editor/lifecycle')
      .setMethodCallHandler((_) async => true);
  await Directory(base).create(recursive: true);
  for (final n in ['request.json', 'report.json']) {
    final f = File('$base/$n');
    if (await f.exists()) await f.delete();
  }
  runApp(const MaterialApp(
      home: Scaffold(
          body: Center(
              child: Text('Native file-dialog QA · temporary files only')))));
  await WidgetsBinding.instance.endOfFrame;
  final passed = <String>[];
  final target = '$base/formation-$pid.pvzproject';
  final original =
      Uint8List.fromList(utf8.encode('native-panel-original-$pid'));
  final replacement =
      Uint8List.fromList(utf8.encode('native-panel-replacement-$pid'));
  var serial = 0;
  Future<T> panel<T>(String action, Future<T> Function() call) async {
    await writeJson('request.json',
        {'id': ++serial, 'pid': pid, 'action': action, 'path': target});
    return call().timeout(const Duration(seconds: 45));
  }

  try {
    await ExportPreferences.setDirectory(base);
    final saved = await panel(
        'save',
        () => ProjectFiles.saveWithBackup(
            File(target).uri.pathSegments.last, original, 'application/json'));
    check(saved?.path == target && saved?.backupPath == null,
        'native save result');
    check(
        base64Encode(await File(target).readAsBytes()) ==
            base64Encode(original),
        'native save bytes');
    passed.add('real NSSavePanel saves exact bytes into temporary target');
    final picked = await panel('open', ProjectFiles.pickWithPath);
    check(
        picked?.path != null &&
            await File(picked!.path!).resolveSymbolicLinks() ==
                await File(target).resolveSymbolicLinks() &&
            base64Encode(picked.bytes) == base64Encode(original),
        'native open exact file and bytes: path=${picked?.path}, size=${picked?.bytes.length}, expected=${original.length}');
    passed.add('real NSOpenPanel returns saved path and exact bytes');
    final canceled = await panel(
        'cancel',
        () => ProjectFiles.saveWithBackup(File(target).uri.pathSegments.last,
            replacement, 'application/json'));
    check(
        canceled == null &&
            base64Encode(await File(target).readAsBytes()) ==
                base64Encode(original),
        'cancel leaves original intact');
    passed.add('cancel real save panel preserves existing file');
    final backup = await ProjectFiles.saveToPath(target, replacement);
    check(
        backup != null &&
            base64Encode(await File(backup).readAsBytes()) ==
                base64Encode(original),
        'backup stores original bytes');
    final redo = await FileBackups.restoreBackup(backup!, target);
    check(
        redo != null &&
            base64Encode(await File(target).readAsBytes()) ==
                base64Encode(original),
        'restore original');
    check(
        base64Encode(await File(redo!).readAsBytes()) ==
            base64Encode(replacement),
        'restore creates reversible backup');
    passed.add('real file replacement backup and reversible restore');
    await writeJson('report.json', {
      'pid': pid,
      'status': 'pass',
      'pass': passed,
      'scope':
          'real native macOS file panels and temporary files; path-provider support storage redirected, product files channel untouched'
    });
    exit(0);
  } catch (e, s) {
    await writeJson('report.json', {
      'pid': pid,
      'status': 'fail',
      'pass': passed,
      'error': '$e',
      'stack': '$s'
    });
    exit(1);
  }
}
