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
          Text(AppLanguage.text(
              '基于 Flutter Widget / Canvas 的本地布阵器，提供阵型编辑、自动存档、阵型码交换和图片导出。')),
          const SizedBox(height: 8),
          Text(AppLanguage.text(
              'Windows 为主要平台，Release 构建及真实游戏阵型读写已验证。Windows 专属功能包括游戏阵型读取、应用与游戏存档接入。')),
          const SizedBox(height: 8),
          Text(AppLanguage.text(
              '提供 Windows、macOS、Linux、Android、iOS 工程。macOS 已有构建与桌面交互验证；Linux、Android、iOS 待设备验证。')),
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
                  openAppLink(context, 'https://pvz.tools/toolkit/'),
              child: const Text('PvZ Toolkit — lmintlcx ↗')),
          const SelectableText('https://pvz.tools/toolkit/'),
          TextButton(
              onPressed: () => openAppLink(
                  context, 'https://github.com/wszqkzqk/PvZ-Portable'),
              child: const Text('PvZ-Portable — wszqkzqk ↗')),
          const SelectableText('https://github.com/wszqkzqk/PvZ-Portable'),
          const SizedBox(height: 12),
          Text(AppLanguage.text('致谢')),
          const Text('lmintlcx（PvZ Toolkit）\n'
              'wszqkzqk（PvZ-Portable）\n'
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
