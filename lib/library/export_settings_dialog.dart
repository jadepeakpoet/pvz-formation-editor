import '../widgets/app_about.dart';
import '../platform/app_language.dart';
import '../platform/language_selector.dart';
import 'package:flutter/material.dart';
import '../platform/export_preferences.dart';

/// Sets the initial export folder; each export can still choose another folder.
Future<void> showExportSettings(BuildContext context) async {
  await showDialog<void>(
      context: context,
      builder: (_) =>
          LanguageScope(builder: () => const _ExportSettingsDialog()));
}

class _ExportSettingsDialog extends StatefulWidget {
  const _ExportSettingsDialog();
  @override
  State<_ExportSettingsDialog> createState() => _ExportSettingsDialogState();
}

class _ExportSettingsDialogState extends State<_ExportSettingsDialog> {
  final directory = TextEditingController();
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await ExportPreferences.loadDirectory();
      if (mounted) directory.text = value ?? '';
    } catch (e) {
      if (mounted) setState(() => error = '无法读取设置：$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> perform(Future<void> Function() action) async {
    if (busy || loading) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => error = '操作失败：$e');
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLanguage.text('导出设置操作失败：$e'))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    directory.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          key: const ValueKey('export-settings-dialog'),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          title: Text(AppLanguage.text('设置'),
              style: const TextStyle(fontSize: 19)),
          content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const LanguageSelector(),
                    const SizedBox(height: 18),
                    Text(AppLanguage.text('默认导出目录'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                        AppLanguage.text(
                            '默认使用文稿目录下的“PvzFormationEditor”文件夹。每次导出时仍可更改保存位置。'),
                        style: const TextStyle(
                            fontSize: 12,
                            height: 1.6,
                            color: Color(0xff68756a))),
                    const SizedBox(height: 14),
                    if (loading)
                      const LinearProgressIndicator()
                    else
                      TextField(
                          key: const ValueKey('export-settings-directory'),
                          controller: directory,
                          enabled: !busy,
                          minLines: 2,
                          maxLines: 3,
                          decoration: InputDecoration(
                              hintText: AppLanguage.text('布阵器专用目录'),
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.all(12))),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, children: [
                      TextButton.icon(
                          key: const ValueKey('export-settings-pick'),
                          onPressed: loading || busy
                              ? null
                              : () => perform(() async {
                                    final path =
                                        await ExportPreferences.pickDirectory();
                                    if (path != null && mounted) {
                                      directory.text = path;
                                    }
                                  }),
                          icon:
                              const Icon(Icons.folder_open_outlined, size: 18),
                          label: Text(AppLanguage.text('选择文件夹'))),
                      TextButton(
                          key: const ValueKey('export-settings-default'),
                          onPressed: loading || busy
                              ? null
                              : () => perform(() async {
                                    final path = await ExportPreferences
                                        .defaultDirectory();
                                    if (mounted) directory.text = path;
                                  }),
                          child: Text(AppLanguage.text('恢复默认目录')))
                    ]),
                    if (error != null)
                      Text(AppLanguage.text(error!),
                          style:
                              const TextStyle(fontSize: 12, color: Colors.red))
                  ]))),
          actions: [
            TextButton(
                onPressed: () => showAppAbout(context),
                child: Text(AppLanguage.text('关于'))),
            TextButton(
                key: const ValueKey('export-settings-cancel'),
                onPressed: busy ? null : () => Navigator.of(context).pop(),
                child: Text(AppLanguage.text('取消'))),
            FilledButton(
                key: const ValueKey('export-settings-save'),
                onPressed: loading || busy
                    ? null
                    : () => perform(() async {
                          final value = directory.text.trim();
                          await ExportPreferences.setDirectory(
                              value.isEmpty ? null : value);
                          if (mounted) Navigator.of(this.context).pop();
                        }),
                child: Text(AppLanguage.text(busy ? '正在保存…' : '保存')))
          ]);
}
