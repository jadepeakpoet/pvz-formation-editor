import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Read from disk on every call so independent Flutter windows share settings.
class ExportPreferences {
  static const _channel = MethodChannel('pvz_formation_editor/files');
  static const applicationDirectoryName = 'PvzFormationEditor';

  // Isolated harnesses never need to create folders in the user's Documents.
  static File? fileOverride;
  static Directory? documentsDirectoryOverride;
  static Future<File> _file() async => File(fileOverride?.path ??
      '${(await getApplicationSupportDirectory()).path}/export-preferences.json');

  static Future<Directory> _documents() async =>
      documentsDirectoryOverride ?? await getApplicationDocumentsDirectory();

  static bool _sameDirectory(String a, String b) {
    String normalized(String path) {
      final value = Directory(path).absolute.uri.normalizePath().toString();
      return Platform.isWindows ? value.toLowerCase() : value;
    }

    return normalized(a) == normalized(b);
  }

  /// Resolve the effective default without creating a folder while viewing settings.
  static Future<String> defaultDirectory() async => Directory(
          '${(await _documents()).path}${Platform.pathSeparator}$applicationDirectoryName')
      .path;

  static Future<String?> loadDirectory() async {
    String? stored;
    try {
      final file = await _file();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        final path = data is Map ? data['directory'] : null;
        if (path is String &&
            Directory(path).isAbsolute &&
            await Directory(path).exists()) {
          stored = path;
        }
      }
    } on MissingPluginException {
      /* Resolve a Documents default even without preference storage support. */
    } on FormatException {
      /* Invalid preferences fall back to the application folder. */
    }
    try {
      final documents = await _documents();
      final legacyDefault = Directory(
          '${documents.path}${Platform.pathSeparator}PVZ Formation Editor').path;
      if (stored != null && !_sameDirectory(stored, documents.path) &&
          !_sameDirectory(stored, legacyDefault)) {
        return stored;
      }
      return Directory(
              '${documents.path}${Platform.pathSeparator}$applicationDirectoryName')
          .path;
    } on MissingPluginException {
      return stored;
    } on PlatformException {
      return stored;
    } on MissingPlatformDirectoryException {
      return stored;
    }
  }

  /// Only an export or folder-picker action creates the application directory.
  static Future<String?> ensureDirectory() async {
    final path = await loadDirectory();
    if (path != null) await Directory(path).create(recursive: true);
    return path;
  }

  static Future<bool> _isDefaultDirectory(String path) async {
    try {
      return _sameDirectory(path, await defaultDirectory());
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } on MissingPlatformDirectoryException {
      return false;
    }
  }

  static Future<void> setDirectory(String? directory) async {
    final path = directory?.trim();
    final hasPath = path != null && path.isNotEmpty;
    final isDefault = hasPath && await _isDefaultDirectory(path);
    if (hasPath &&
        (!Directory(path).isAbsolute ||
            (!isDefault && !await Directory(path).exists()))) {
      throw const FileSystemException('请选择存在的绝对目录');
    }
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary =
        File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      await temporary.writeAsString(
          jsonEncode({'directory': !hasPath || isDefault ? null : path}),
          flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<String?> pickDirectory() async {
    final current = await ensureDirectory();
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
