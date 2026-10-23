import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/library/formation_images.dart';
import 'package:pvz_formation_editor/platform/export_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
      const MaterialApp(home: Scaffold(body: Center(child: Text('导出与图片验证')))));
  final folder = await Directory.systemTemp.createTemp('pvz-native-export-');
  String? original;
  var loaded = false;
  final report = <String, dynamic>{'status': 'fail'};
  try {
    original = await ExportPreferences.loadDirectory();
    loaded = true;
    await ExportPreferences.setDirectory(folder.path);
    if (await ExportPreferences.loadDirectory() != folder.path) {
      throw StateError('导出目录未持久化');
    }
    await ExportPreferences.setDirectory(null);
    if (await ExportPreferences.loadDirectory() != null) {
      throw StateError('恢复系统默认失败');
    }
    final document = Formation(pieces: [
      Piece(id: 'pea', type: 'pea', row: 1, col: 1, layer: 10),
    ]);
    final png = await FormationImages.render(document);
    final codec = await ui.instantiateImageCodec(png);
    final image = (await codec.getNextFrame()).image;
    if (image.width != 1600 || image.height != 1200) throw StateError('图片尺寸错误');
    image.dispose();
    codec.dispose();
    await File('/tmp/pvz-archive-share.png').writeAsBytes(png);
    await FormationImages.copy(document);
    report.addAll({
      'status': 'pass',
      'imageSize': [1600, 1200],
      'pngBytes': png.length,
      'nativeClipboardWrite': true,
      'preferencesPersistAndReset': true,
      'scope':
          'Actual macOS image render, native NSPasteboard write, and real app-support preferences. No system save/picker sheet interaction.'
    });
  } catch (e, st) {
    report.addAll({'error': '$e', 'stack': '$st'});
  } finally {
    if (loaded) await ExportPreferences.setDirectory(original);
    await folder.delete(recursive: true);
    await File('/tmp/pvz-export-media-native.json')
        .writeAsString(jsonEncode(report));
  }
}
