import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Read from disk on every call so independent Flutter windows share settings.
class ExportPreferences {
  static const _channel = MethodChannel('pvz_formation_editor/files');
  static Future<File> _file() async => File(
      '${(await getApplicationSupportDirectory()).path}/export-preferences.json');

  static Future<String?> loadDirectory() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      final path = data is Map ? data['directory'] : null;
      return path is String &&
              Directory(path).isAbsolute &&
              await Directory(path).exists()
          ? path
          : null;
    } on MissingPluginException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Future<void> setDirectory(String? directory) async {
    final path = directory?.trim();
    if (path != null &&
        path.isNotEmpty &&
        (!Directory(path).isAbsolute || !await Directory(path).exists())) {
      throw const FileSystemException('请选择存在的绝对目录');
    }
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary =
        File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      await temporary.writeAsString(
          jsonEncode({
            'directory': path == null || path.isEmpty ? null : path,
          }),
          flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<String?> pickDirectory() async {
    final current = await loadDirectory();
    if (Platform.isMacOS) {
      return _channel.invokeMethod<String>(
          'chooseExportDirectory', {'directory': current});
    }
    if (Platform.isWindows || Platform.isLinux) {
      final result = Platform.isLinux
          ? await Process.run('zenity', [
              '--file-selection',
              '--directory',
              '--title=选择默认导出目录',
              if (current != null) '--filename=$current/'
            ])
          : await Process.run('powershell', [
              '-NoProfile',
              '-STA',
              '-Command',
              r'[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false); Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.FolderBrowserDialog; $d.SelectedPath=$env:PVZ_EXPORT_DIRECTORY; if($d.ShowDialog() -eq "OK"){[Console]::Write($d.SelectedPath)}'
            ], environment: {
              'PVZ_EXPORT_DIRECTORY': current ?? ''
            });
      if (Platform.isLinux && result.exitCode == 1) return null;
      if (result.exitCode != 0) throw const FileSystemException('无法打开目录选择器');
      final path = (result.stdout as String).trim();
      return path.isEmpty ? null : path;
    }
    return _channel
        .invokeMethod<String>('chooseExportDirectory', {'directory': current});
  }

  static Future<void> rememberSavedFile(String path) async {
    // The export already succeeded. Missing settings support must not turn a
    // successful export into a false failure on a platform file provider.
    try {
      if (File(path).isAbsolute) await setDirectory(File(path).parent.path);
    } on MissingPluginException {
      /* Platform does not provide app storage. */
    } on FileSystemException {
      /* The export succeeded; preferences are non-fatal. */
    } on PlatformException {
      /* A file-provider export must not depend on settings plugin availability. */
    }
  }
}
