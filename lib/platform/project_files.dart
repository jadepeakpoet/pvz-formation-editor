import 'dart:typed_data' show BytesBuilder;
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import '../storage/file_backups.dart';
import 'export_preferences.dart';

class PickedFormationFile {
  final String? path;
  final Uint8List bytes;
  const PickedFormationFile({required this.path, required this.bytes});
}

class SavedFormationFile {
  final String path;
  final String? backupPath;
  const SavedFormationFile({required this.path, this.backupPath});
}

class ProjectFiles {
  static const _channel = MethodChannel('pvz_formation_editor/files');

  /// Test seam for OS-owned dialogs; all validation and file I/O still run.
  @visibleForTesting
  static Future<String?> Function({required bool save, required String name})?
      desktopDialogOverride;
  static const maxProjectBytes = 8 * 1024 * 1024;

  /// Opens a public web address in the system browser. No shell interpolation.
  static void validateExternal(Uri uri) {
    if (!const ['http', 'https'].contains(uri.scheme.toLowerCase()) ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.authority.contains('@') ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(uri.toString()) ||
        RegExp(r'%0[ad]', caseSensitive: false).hasMatch(uri.toString())) {
      throw ArgumentError.value(uri, 'uri', '只支持有效的 HTTP/HTTPS 网页地址');
    }
  }

  static Future<bool> openExternal(Uri uri) async {
    validateExternal(uri);
    final url = uri.toString();
    if (Platform.isLinux || Platform.isWindows) {
      final result = Platform.isLinux
          ? await Process.run('xdg-open', [url], runInShell: false)
          : await Process.run(
              'powershell',
              [
                '-NoProfile',
                '-NonInteractive',
                '-Command',
                r'$ErrorActionPreference="Stop"; Start-Process -FilePath $env:PVZ_EXTERNAL_URL'
              ],
              environment: {'PVZ_EXTERNAL_URL': url},
              runInShell: false);
      if (result.exitCode != 0) {
        throw FileSystemException('无法打开网页：${result.stderr}');
      }
      return true;
    }
    return await _channel.invokeMethod<bool>('openExternal', {'url': url}) ??
        false;
  }

  static Future<Uint8List?> pick() async => (await pickWithPath())?.bytes;

  static Future<PickedFormationFile?> pickWithPath() async {
    if (Platform.isLinux || Platform.isWindows) {
      final path = await _desktopDialog(save: false);
      if (path == null) return null;
      final file = File(path);
      if (await file.length() > maxProjectBytes) {
        throw const FormatException('项目文件超过 8 MiB');
      }
      final collected = BytesBuilder(copy: false);
      await for (final chunk in file.openRead()) {
        if (collected.length + chunk.length > maxProjectBytes) {
          throw const FormatException('项目文件超过 8 MiB');
        }
        collected.add(chunk);
      }
      return PickedFormationFile(path: path, bytes: collected.takeBytes());
    }
    if (Platform.isMacOS) {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('pickFormation');
      if (result == null) return null;
      final bytes = result['bytes'] as Uint8List;
      if (bytes.length > maxProjectBytes) {
        throw const FormatException('项目文件超过 8 MiB');
      }
      return PickedFormationFile(path: result['path'] as String?, bytes: bytes);
    }
    final bytes = await _channel.invokeMethod<Uint8List>('pickProject');
    if (bytes != null && bytes.length > maxProjectBytes) {
      throw const FormatException('项目文件超过 8 MiB');
    }
    return bytes == null ? null : PickedFormationFile(path: null, bytes: bytes);
  }

  static Future<String?> saveToPath(String path, Uint8List bytes) =>
      FileBackups.replace(path, bytes);

  static Future<String?> save(
          String name, Uint8List bytes, String mime) async =>
      (await saveWithBackup(name, bytes, mime))?.path;

  static Future<SavedFormationFile?> saveWithBackup(
      String name, Uint8List bytes, String mime) async {
    if (bytes.length > maxProjectBytes) {
      throw const FormatException('项目文件超过 8 MiB');
    }
    if (Platform.isLinux || Platform.isWindows) {
      final path = await _desktopDialog(save: true, name: name);
      if (path == null) return null;
      final backup = await saveToPath(path, bytes);
      await ExportPreferences.rememberSavedFile(path);
      return SavedFormationFile(path: path, backupPath: backup);
    }
    if (Platform.isMacOS) {
      final path = await _channel.invokeMethod<String>('chooseSavePath', {
        'name': name,
        'mime': mime,
        'directory': await ExportPreferences.ensureDirectory(),
      });
      if (path == null) return null;
      final backup = await saveToPath(path, bytes);
      await ExportPreferences.rememberSavedFile(path);
      return SavedFormationFile(path: path, backupPath: backup);
    }
    final path = await _channel.invokeMethod<String>(
        'saveFile', {'name': name, 'bytes': bytes, 'mime': mime});
    return path == null ? null : SavedFormationFile(path: path);
  }

  static Future<String?> _desktopDialog(
      {required bool save, String name = 'formation.pvzproject'}) async {
    if (desktopDialogOverride != null) {
      return desktopDialogOverride!(save: save, name: name);
    }
    ProcessResult result;
    try {
      String? directory;
      if (save) {
        directory = await ExportPreferences.ensureDirectory();
      }
      if (Platform.isLinux) {
        result = await Process.run('zenity', [
          '--file-selection',
          if (save) '--save',
          if (save) '--confirm-overwrite',
          if (save) '--filename=$directory/$name',
          '--title=${save ? '导出阵型' : '导入项目'}'
        ]);
      } else {
        int? owner;
        for (var attempt = 0; attempt < 5; attempt++) {
          try {
            owner = await const MethodChannel('pvz_formation_editor/windows')
                .invokeMethod<int>('getDialogOwner');
            break;
          } on MissingPluginException {
            // The first Dart frame may precede native channel registration.
            if (attempt < 4) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          }
        }
        // Suggested name is passed through the environment, never interpolated into script code.
        const base =
            r'''[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false); Add-Type -AssemblyName System.Windows.Forms;
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition 'public class PvzDialogOwner : System.Windows.Forms.IWin32Window { public System.IntPtr Handle { get; private set; } public PvzDialogOwner(long handle) { Handle = new System.IntPtr(handle); } }';
$owner = New-Object PvzDialogOwner ([long]$env:PVZ_DIALOG_OWNER);
''';
        final script = save
            ? base +
                r'$d=New-Object System.Windows.Forms.SaveFileDialog; $d.FileName=$env:PVZ_EXPORT_NAME; $d.InitialDirectory=$env:PVZ_EXPORT_DIRECTORY; $d.OverwritePrompt=$true; if($d.ShowDialog($owner) -eq "OK") { [Console]::Write($d.FileName) }'
            : base +
                r'$d=New-Object System.Windows.Forms.OpenFileDialog; if($d.ShowDialog($owner) -eq "OK") { [Console]::Write($d.FileName) }';
        result = await Process.run('powershell', [
          '-NoProfile',
          '-STA',
          '-Command',
          script
        ], environment: {
          'PVZ_EXPORT_NAME': name,
          'PVZ_DIALOG_OWNER': '${owner ?? 0}',
          'PVZ_EXPORT_DIRECTORY': directory ?? ''
        });
      }
    } on ProcessException {
      throw UnsupportedError(
          '当前系统缺少文件对话框工具（Linux 需要 zenity，Windows 需要 PowerShell）');
    }
    if (result.exitCode == 1 && Platform.isLinux) return null;
    if (result.exitCode != 0) {
      throw FileSystemException('文件对话框失败：${result.stderr}');
    }
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  }
}
