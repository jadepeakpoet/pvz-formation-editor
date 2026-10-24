import 'package:flutter/material.dart';
import '../platform/app_language.dart';
import '../platform/app_info.dart';
import '../platform/project_files.dart';

void showAppAbout(BuildContext context) => showAboutDialog(
        context: context,
        applicationName: 'PVZ Formation Editor',
        applicationVersion: AppInfo.version,
        children: [
          Text(AppLanguage.text('作者：越小梦')),
          const SizedBox(height: 8),
          Text(AppLanguage.text('快链')),
          Wrap(spacing: 8, children: [
            TextButton(
                onPressed: () => openAppLink(context, AppInfo.website),
                child: const Text('xmpvz.pages.dev')),
            TextButton(
                onPressed: () => openAppLink(context, AppInfo.documentation),
                child: Text(AppLanguage.text('使用文档'))),
            TextButton(
                onPressed: () => openAppLink(context, AppInfo.repository),
                child: const Text('GitHub')),
          ]),
          SelectableText('${AppLanguage.text('交流 QQ 群')}：${AppInfo.qqGroup}'),
          TextButton(
              onPressed: () =>
                  openAppLink(context, '${AppInfo.website}/license.txt'),
              child: const Text('GNU GPL v3.0')),
          const SizedBox(height: 12),
          Text(AppLanguage.text('主要参考项目')),
          const SelectableText('jspvz 网页布阵器 — LonelyStar（囧丫乙）\n'
              'http://jspvz.com/ArrayDesign/'),
          const SizedBox(height: 8),
          Text(AppLanguage.text(
              '以网页布阵器的功能和界面为基础，迁移到本地应用，并增强存档管理、桌面交互和游戏阵型读写等能力。')),
          const SizedBox(height: 12),
          Text(AppLanguage.text('技术参考项目')),
          TextButton(
              onPressed: () =>
                  openAppLink(context, 'https://pvz.lmintlcx.com/toolkit/'),
              child: const Text('PvZ Toolkit — lmintlcx ↗')),
          const SelectableText('https://pvz.lmintlcx.com/toolkit/'),
          TextButton(
              onPressed: () => openAppLink(
                  context, 'https://github.com/wszqkzqk/PvZ-Portable'),
              child: const Text('PvZ-Portable — wszqkzqk 及社区贡献者 ↗')),
          const SelectableText('https://github.com/wszqkzqk/PvZ-Portable'),
          const SizedBox(height: 12),
          Text(AppLanguage.text('致谢')),
          const Text('lmintlcx（PvZ Toolkit）\n'
              'wszqkzqk 及社区贡献者（PvZ-Portable）\n'
              '囧丫乙（LonelyStar）\nPopCap Games\nFlutter / Dart'),
        ]);

Future<void> openAppLink(BuildContext context, String url) async {
  try {
    await ProjectFiles.openExternal(Uri.parse(url));
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AppLanguage.text('无法打开链接：$e'))));
    }
  }
}
