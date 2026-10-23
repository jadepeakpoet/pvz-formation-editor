import 'package:flutter/material.dart';
import '../platform/app_language.dart';

Future<String?> showRenameDialog(BuildContext context, String currentName) =>
    showDialog<String>(
        context: context,
        builder: (_) => _RenameDialog(currentName: currentName));

class _RenameDialog extends StatefulWidget {
  final String currentName;
  const _RenameDialog({required this.currentName});
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController controller;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController.fromValue(TextEditingValue(
        text: widget.currentName,
        selection: TextSelection(
            baseOffset: 0, extentOffset: widget.currentName.length)));
  }

  void confirm() {
    final name = controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          key: const ValueKey('workspace-rename-dialog'),
          title: Text(AppLanguage.text('重命名')),
          content: SizedBox(
              width: 360,
              child: TextField(
                  key: const ValueKey('workspace-rename-input'),
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration:
                      InputDecoration(labelText: AppLanguage.text('名称')),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => confirm())),
          actions: [
            TextButton(
                key: const ValueKey('workspace-rename-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppLanguage.text('取消'))),
            FilledButton(
                key: const ValueKey('workspace-rename-confirm'),
                onPressed: controller.text.trim().isEmpty ? null : confirm,
                child: Text(AppLanguage.text('确定'))),
          ]);
}
