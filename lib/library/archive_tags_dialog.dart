import '../platform/app_language.dart';
import 'package:flutter/material.dart';

/// Reuse existing labels or create new ones without entering comma syntax.
Future<List<String>?> archiveTagsDialog(BuildContext context,
    {required List<String> selected,
    required Iterable<String> available}) async {
  final result = await showDialog<List<String>>(
      context: context,
      builder: (_) =>
          _ArchiveTagsDialog(selected: selected, available: available));
  return result;
}

class _ArchiveTagsDialog extends StatefulWidget {
  final List<String> selected;
  final Iterable<String> available;
  const _ArchiveTagsDialog({required this.selected, required this.available});
  @override
  State<_ArchiveTagsDialog> createState() => _ArchiveTagsDialogState();
}

class _ArchiveTagsDialogState extends State<_ArchiveTagsDialog> {
  final input = TextEditingController();
  late final chosen =
      widget.selected.map((t) => t.trim()).where((t) => t.isNotEmpty).toSet();
  late final labels = {...widget.available, ...chosen}
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toSet();
  void add() {
    final names = input.text
        .split(RegExp('[,，\\n]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty);
    setState(() {
      labels.addAll(names);
      chosen.addAll(names);
      input.clear();
    });
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = labels.toList()..sort();
    return AlertDialog(
        title: Text(AppLanguage.text('设置标签')),
        content: SizedBox(
            width: 360,
            child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .55),
                child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(AppLanguage.text('点击选择，可添加多个标签'),
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 10),
                      if (sorted.isEmpty)
                        Text(AppLanguage.text('还没有标签，先添加一个吧。')),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        for (final tag in sorted)
                          FilterChip(
                              key: ValueKey('archive-tag-choice:$tag'),
                              label: Text(tag),
                              selected: chosen.contains(tag),
                              onSelected: (value) => setState(() {
                                    if (value) {
                                      chosen.add(tag);
                                    } else {
                                      chosen.remove(tag);
                                    }
                                  })),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                key: const ValueKey('archive-tag-input'),
                                controller: input,
                                onSubmitted: (_) => add(),
                                decoration: InputDecoration(
                                    labelText: AppLanguage.text('新标签'),
                                    isDense: true))),
                        TextButton(
                            key: const ValueKey('archive-tag-add'),
                            onPressed: add,
                            child: Text(AppLanguage.text('添加'))),
                      ]),
                    ])))),
        actions: [
          TextButton(
              key: const ValueKey('archive-tags-cancel'),
              onPressed: () => Navigator.pop(context),
              child: Text(AppLanguage.text('取消'))),
          FilledButton(
              key: const ValueKey('archive-tags-save'),
              onPressed: () {
                add();
                Navigator.pop(context, chosen.toList()..sort());
              },
              child: Text(AppLanguage.text('保存'))),
        ]);
  }
}
