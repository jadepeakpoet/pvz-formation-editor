// Native title acceptance; language preferences and archives use an isolated directory.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/platform/app_language.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

@pragma('vm:entry-point')
Future<void> toolboxMain() => app.toolboxMain();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = Directory(Platform.environment['PVZ_TITLE_REVIEW']!);
  AppLanguage.fileOverride = File('${root.path}/language.json');
  final repository = await FormationRepository.open('${root.path}/test.sqlite');
  const channel = MethodChannel('pvz_formation_editor/windows');
  runApp(const MaterialApp(home: SizedBox.shrink()));
  final report = <String, dynamic>{};
  Future<void> stage(String name, String language, String mode) async {
    await AppLanguage.setLanguage(language);
    await channel.invokeMethod('selectSidebarMode', {'mode': mode});
    await File('${root.path}/$name.ready.json').writeAsString(jsonEncode({
      'pid': pid, 'language': language, 'mode': mode}));
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!await File('${root.path}/$name.done').exists()) {
      if (DateTime.now().isAfter(deadline)) throw StateError('Native title check timed out: $name');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  try {
    await AppLanguage.setLanguage('en');
    await channel.invokeMethod('initialize', {'dataPath': '${root.path}/test.sqlite'});
    await stage('english-toolbox', 'en', 'toolbox');
    await stage('english-library', 'en', 'library');
    await stage('chinese-library', 'zh', 'library');
    await stage('english-library-again', 'en', 'library');
    await stage('english-toolbox-again', 'en', 'toolbox');
    report['status'] = 'pass';
  } catch (error, stack) {
    report.addAll({'status': 'fail', 'error': '$error\n$stack'});
  } finally {
    await repository.close();
    await File('${root.path}/report.json').writeAsString(jsonEncode(report));
  }
  exit(report['status'] == 'pass' ? 0 : 1);
}
