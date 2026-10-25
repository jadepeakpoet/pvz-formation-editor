// Real Win32 reset acceptance; the external driver moves only this fixture's windows.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/platform/app_language.dart';

const channel = MethodChannel('pvz_formation_editor/windows');
Directory get root => Directory(Platform.environment['PVZ_RESET_REVIEW']!);

Future<void> waitFor(String name) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!await File('${root.path}/$name').exists()) {
    if (DateTime.now().isAfter(deadline)) throw StateError('Timed out: $name');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: SizedBox.shrink()));
  await channel.invokeMethod('ready');
  await waitFor('secondary-request');
  final result = await channel.invokeMethod<bool>('resetWindowPositions');
  await File('${root.path}/secondary-result').writeAsString('$result');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLanguage.fileOverride = File('${root.path}/language.json');
  runApp(const MaterialApp(home: SizedBox.shrink()));
  final report = <String, dynamic>{};
  Future<void> stage(String name) async {
    await File('${root.path}/$name.ready').writeAsString('$pid');
    await waitFor('$name.moved');
    if (name == 'secondary') {
      await File('${root.path}/secondary-request').writeAsString('reset');
      await waitFor('secondary-result');
      if (await File('${root.path}/secondary-result').readAsString() != 'true')
        throw StateError('Secondary reset was rejected');
    } else if (await channel.invokeMethod<bool>('resetWindowPositions') != true) {
      throw StateError('Reset was rejected: $name');
    }
    await File('${root.path}/$name.reset').writeAsString('true');
    await waitFor('$name.done');
  }
  try {
    await AppLanguage.setLanguage('en');
    await channel.invokeMethod('setLanguage', {'language': 'en'});
    await stage('main-only');
    await channel.invokeMethod('initialize');
    await channel.invokeMethod('setSidebarVisible', {'visible': true});
    for (final name in ['normal', 'hidden', 'sidebar-minimized', 'main-minimized', 'secondary']) {
      await stage(name);
    }
    report['status'] = 'pass';
  } catch (error, stack) {
    report.addAll({'status': 'fail', 'error': '$error\n$stack'});
  }
  await File('${root.path}/report.json').writeAsString(jsonEncode(report));
  exit(report['status'] == 'pass' ? 0 : 1);
}
