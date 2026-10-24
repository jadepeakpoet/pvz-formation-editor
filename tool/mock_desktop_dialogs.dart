// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/platform/export_preferences.dart';
import 'package:pvz_formation_editor/platform/project_files.dart';
import 'package:pvz_formation_editor/platform/app_language.dart';
import 'package:pvz_formation_editor/library/formation_images.dart';

/// Reuses picker fixtures across desktop platforms while exercising real I/O.
void installMockDesktopDialogs(
    Future<dynamic> Function(MethodCall) handler) {
  final root = Directory.systemTemp.createTempSync('pvz-dialog-fixtures-');
  AppLanguage.fileOverride ??= File('${root.path}/language.json');
  FormationImages.clipboardOverride ??= (bytes) async {
    final copied = await handler(MethodCall('copyImage', {'bytes': bytes}));
    if (copied != true) throw StateError('Image clipboard fixture rejected data');
  };
  ExportPreferences.fileOverride ??= File('${root.path}/preferences.json');
  ExportPreferences.documentsDirectoryOverride ??=
      Directory('${root.path}/Documents')..createSync(recursive: true);
  ProjectFiles.desktopDialogOverride ??= ({required save, required name}) async {
    if (save) {
      final directory = await ExportPreferences.ensureDirectory();
      return await handler(MethodCall('chooseSavePath', {
        'name': name, 'directory': directory,
      })) as String?;
    }
    final picked = await handler(const MethodCall('pickFormation'));
    if (picked == null) return null;
    final map = picked as Map;
    final path = map['path'] as String? ?? '${root.path}/picked.txt';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(map['bytes'] as Uint8List);
    return path;
  };
  ExportPreferences.directoryDialogOverride ??= (directory) async =>
      await handler(MethodCall('chooseExportDirectory', {
        'directory': directory,
      })) as String?;
}
