import 'dart:io';
import 'package:flutter/services.dart';
import '../domain/formation.dart';
import '../editor/board_painter.dart';
import '../editor/original_assets.dart';
import '../platform/project_files.dart';

class FormationImages {
  static Future<Uint8List> render(Formation document) async {
    await OriginalAssets.ensureLoaded();
    return exportPng(document, multiplier: 2);
  }

  static Future<bool> export(Formation document, String name) async {
    final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
    return await ProjectFiles.save(
            '$safe.png', await render(document), 'image/png') !=
        null;
  }

  static Future<void> copy(Formation document) async {
    final bytes = await render(document);
    if (Platform.isLinux) {
      Process process;
      try {
        process = await Process.start('wl-copy', ['--type', 'image/png']);
      } on ProcessException {
        process = await Process.start(
            'xclip', ['-selection', 'clipboard', '-t', 'image/png', '-i']);
      }
      process.stdin.add(bytes);
      await process.stdin.close();
      if (await process.exitCode != 0) {
        throw const FileSystemException('复制图片失败');
      }
      return;
    }
    if (Platform.isWindows) {
      final folder = await Directory.systemTemp.createTemp('pvz-image-');
      try {
        final file = File('${folder.path}/formation.png');
        await file.writeAsBytes(bytes, flush: true);
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-STA',
          '-Command',
          r'Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; $i=[System.Drawing.Image]::FromFile($env:PVZ_IMAGE_FILE); try{[System.Windows.Forms.Clipboard]::SetImage($i)}finally{$i.Dispose()}'
        ], environment: {
          'PVZ_IMAGE_FILE': file.path
        });
        if (result.exitCode != 0) throw const FileSystemException('复制图片失败');
      } finally {
        await folder.delete(recursive: true);
      }
      return;
    }
    final success = await const MethodChannel('pvz_formation_editor/files')
        .invokeMethod<bool>('copyImage', {'bytes': bytes});
    if (success != true) throw const FileSystemException('当前平台不支持复制图片');
  }
}
