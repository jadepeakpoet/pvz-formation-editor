import 'package:flutter/material.dart';
import '../platform/app_language.dart';
import '../storage/formation_repository.dart';

Future<ArchiveDedupResult?> showArchiveDedupDialog(
    BuildContext context, FormationRepository repository,
    {required Set<String> Function() protectedArchiveIds,
    Future<void> Function()? flushEditors}) async {
  await flushEditors?.call();
  final plan = await repository.planDuplicateArchives(
      protectedArchiveIds: protectedArchiveIds());
  if (!context.mounted) return null;
  if (plan.removableCount == 0) {
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(AppLanguage.text('存档去重')),
                content: Text(AppLanguage.text('没有可清理的重复存档。正在打开的存档会保留。')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(AppLanguage.text('确定')))
                ]));
    return null;
  }
  final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
              key: const ValueKey('archive-dedup-dialog'),
              title: Text(AppLanguage.text('存档去重')),
              content: SizedBox(
                  width: 430,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(AppLanguage.text(
                            '发现 ${plan.groupsCount} 组重复，可清理 ${plan.removableCount} 个存档。')),
                        const SizedBox(height: 8),
                        Text(
                            AppLanguage.text(
                                '仅合并阵型内容、备注、标签和收藏状态相同的存档。优先保留正在打开的存档，否则保留最近修改的一份；历史版本会完整保留。'),
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 240),
                            child: SingleChildScrollView(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  for (final group in plan.groups)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: Text(
                                            AppLanguage.text(
                                                '保留：${group.keeper.name}；清理 ${group.duplicates.length} 份重复'),
                                            style:
                                                const TextStyle(fontSize: 12)))
                                ]))),
                      ])),
              actions: [
                TextButton(
                    key: const ValueKey('archive-dedup-cancel'),
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(AppLanguage.text('取消'))),
                FilledButton(
                    key: const ValueKey('archive-dedup-confirm'),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(AppLanguage.text('确认去重'))),
              ]));
  if (confirmed != true || !context.mounted) return null;
  await flushEditors?.call();
  return repository.removeDuplicateArchives(plan,
      protectedArchiveIds: protectedArchiveIds());
}
