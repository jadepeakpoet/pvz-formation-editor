import 'dart:io';
import 'package:flutter/material.dart';
import '../platform/app_language.dart';

/// One tab strip shared by both retained sidebar engines.
class SidebarTabs extends StatelessWidget {
  const SidebarTabs(
      {super.key, required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;
  static const labels = ['存档仓库', '懒人布局', '图鉴选卡', '镜像窗口', '载入导出', '选项设置'];
  static const englishLabels = ['Archives', 'Quick', 'Cards', 'Mirrors', 'Transfer', 'Settings'];
  static const englishHints = ['Archive library', 'Quick layouts', 'Plant, zombie and item cards',
    'Mirror windows', 'Import and export formation codes and images', 'Application settings'];
  @override
  Widget build(BuildContext context) => Material(
      color: const Color(0xfff7f8f3),
      child: SizedBox(
          height: 34,
          child: Row(children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                  child: Tooltip(
                    message: AppLanguage.locale.value == 'en' ? englishHints[i] : labels[i],
                    child: InkWell(
                      key: ValueKey(
                          i == 0 ? 'sidebar-library-tab' : 'toolbox-tab-$i'),
                      onTap: () => onSelected(i),
                      child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: selected == i
                                  ? const Color(0xffd6e5d2)
                                  : null,
                              border: Border(
                                  bottom: BorderSide(
                                      color: selected == i
                                          ? const Color(0xff376b50)
                                          : const Color(0xffdce3d7),
                                      width: selected == i ? 3 : 1))),
                          child: Text(AppLanguage.locale.value == 'en' ? englishLabels[i] : labels[i],
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: Platform.isWindows ? 12 : 11,
                                  color: const Color(0xff263f35),
                                  fontWeight: selected == i
                                      ? FontWeight.w600
                                      : (Platform.isWindows
                                          ? FontWeight.w500
                                          : FontWeight.normal)))))))
          ])));
}
