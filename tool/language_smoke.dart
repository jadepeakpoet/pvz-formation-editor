import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/platform/app_language.dart';
import 'package:pvz_formation_editor/platform/language_selector.dart';
import 'sidebar_title_smoke.dart' as h;

class RetainedPage extends StatefulWidget {
  const RetainedPage({super.key});
  @override
  State<RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<RetainedPage> {
  final controller = TextEditingController(text: '用户阵型 My formation');
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
          body: Column(children: [
        Text(AppLanguage.text('植物大战僵尸布阵器')),
        TextField(controller: controller),
        const LanguageSelector(),
      ]));
}

Future<void> main() async {
  h.TitleBinding();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  final directory = await Directory.systemTemp.createTemp('pvz-language-');
  final file = File('${directory.path}/language.json');
  AppLanguage.fileOverride = file;
  try {
    runApp(
        LanguageScope(builder: () => const MaterialApp(home: RetainedPage())));
    await h.settle();
    final before = h.find((w) => w is TextField).single.widget as TextField;
    await h.tap('app-language');
    await h.settle();
    await h.tapElement(h.find((w) => w is Text && w.data == 'English').last);
    await h.settle();
    h.check(
        h.find((w) => w is Text && w.data == 'PVZ Formation Editor').isNotEmpty,
        'English UI');
    h.check(
        AppLanguage.text('已选 3（含 1 个筛选外存档）') ==
            '3 selected (1 outside current filter)',
        'specific template precedence');
    final after = h.find((w) => w is TextField).single.widget as TextField;
    h.check(identical(before.controller, after.controller),
        'editor state retained');
    h.check(
        after.controller!.text == '用户阵型 My formation', 'user content retained');
    AppLanguage.locale.value = 'zh';
    await AppLanguage.load();
    h.check(AppLanguage.locale.value == 'en', 'preference restored');
    await AppLanguage.setLanguage('zh');
    await h.settle();
    h.check(h.find((w) => w is Text && w.data == '植物大战僵尸布阵器').isNotEmpty,
        'Chinese UI');
    await file.writeAsString('{invalid');
    await AppLanguage.load();
    h.check(AppLanguage.locale.value == 'zh', 'corrupt preference handled');
    h.check(errors.isEmpty, errors.map((e) => e.exception).join('\n'));
    stdout.writeln(
        'PASS: language switch, live UI, retained state/content, persistence, corrupt preference');
    runApp(const SizedBox.shrink());
    await h.settle();
  } finally {
    AppLanguage.fileOverride = null;
    await directory.delete(recursive: true);
  }
  exit(0);
}
