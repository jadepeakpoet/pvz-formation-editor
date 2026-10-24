import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

late LanguageMessenger native;

class _LanguageBinding extends h.TitleBinding {
  @override
  BinaryMessenger createBinaryMessenger() {
    native = LanguageMessenger(super.createBinaryMessenger());
    return native;
  }
}

class LanguageMessenger extends BinaryMessenger {
  static const channel = 'pvz_formation_editor/language';
  static const codec = StandardMethodCodec();
  final BinaryMessenger delegate;
  Future<ByteData?>? Function(ByteData?)? handler;
  bool connected = false;
  String? canonical;
  Completer<void>? fileReply;
  Completer<String?>? nextGet;
  Completer<void>? nextGetStarted;
  int reads = 0;
  LanguageMessenger(this.delegate);

  Future<void> changed(String language) async {
    final response = await handler!(
        codec.encodeMethodCall(MethodCall('changed', {'language': language})));
    codec.decodeEnvelope(response!);
  }

  @override
  Future<ByteData?> send(String name, ByteData? data) async {
    if (name == channel) {
      final call = codec.decodeMethodCall(data);
      if (call.method == 'getLanguage') {
        reads++;
        final gate = nextGet;
        if (gate != null) {
          nextGet = null;
          nextGetStarted?.complete();
          return codec.encodeSuccessEnvelope(await gate.future);
        }
        return codec.encodeSuccessEnvelope(connected ? canonical : null);
      }
    }
    if (name == 'pvz_formation_editor/files' || name == 'pvz_formation_editor/windows') {
      final call = codec.decodeMethodCall(data);
      if (call.method == 'setLanguage') {
        if (connected) {
          canonical = (call.arguments as Map)['language'] as String;
        }
        await fileReply?.future;
        return codec.encodeSuccessEnvelope(null);
      }
    }
    return await delegate.send(name, data);
  }

  @override
  void setMessageHandler(
      String name, Future<ByteData?>? Function(ByteData?)? callback) {
    if (name == channel) {
      handler = callback;
    } else {
      delegate.setMessageHandler(name, callback);
    }
  }

  @override
  Future<void> handlePlatformMessage(
          String name, ByteData? data, void Function(ByteData?)? callback) =>
      // ignore: deprecated_member_use
      delegate.handlePlatformMessage(name, data, callback);
}

Future<void> main() async {
  _LanguageBinding();
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
    h.check(AppLanguage.text('粘贴导入') == 'Paste and import' &&
        AppLanguage.text('已忽略 2 个僵尸或装饰对象') == '2 zombies or decorative objects omitted' &&
        AppLanguage.text('僵尸携带物、潜水和啃食状态以所选外观为准。') ==
            'Zombie objects, water states and eating follow the selected appearance.',
        'New clipboard and zombie controls must have English translations');
    final after = h.find((w) => w is TextField).single.widget as TextField;
    h.check(identical(before.controller, after.controller),
        'editor state retained');
    h.check(
        after.controller!.text == '用户阵型 My formation', 'user content retained');
    native.fileReply = Completer<void>();
    final immediate = AppLanguage.setLanguage('zh');
    h.check(AppLanguage.locale.value == 'zh',
        'Language should change synchronously before persistence/native replies');
    await immediate.timeout(const Duration(seconds: 3));
    h.check(!native.fileReply!.isCompleted,
        'Persistence should not wait for an unrelated native reply');
    native.fileReply!.complete();
    native.fileReply = null;
    await AppLanguage.setLanguage('en');
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
    final blockedParent = File('${directory.path}/not-a-directory');
    await blockedParent.writeAsString('block');
    AppLanguage.fileOverride = File('${blockedParent.path}/language.json');
    var writeFailed = false;
    try {
      await AppLanguage.setLanguage('en');
    } on FileSystemException {
      writeFailed = true;
    }
    h.check(writeFailed && AppLanguage.locale.value == 'zh',
        'A failed newest save should roll the UI back without losing input');
    AppLanguage.fileOverride = file;
    await file.writeAsString(jsonEncode({'language': 'zh'}));
    native.connected = true;
    native.canonical = 'en';
    await native.changed('en');
    await h.settle();
    h.check(
        AppLanguage.locale.value == 'en' &&
            h
                .find((w) => w is Text && w.data == 'PVZ Formation Editor')
                .isNotEmpty,
        'Another engine should update UI through the pushed language event');
    final reads = native.reads;
    await AppLanguage.load();
    h.check(AppLanguage.locale.value == 'en' && native.reads == reads,
        'Native-linked polling should not reapply the stale disk preference');
    native.canonical = 'zh';
    await native.changed('en');
    h.check(AppLanguage.locale.value == 'zh',
        'A delayed old event must use the current native selection');
    final oldRead = Completer<String?>();
    native.nextGet = oldRead;
    final staleEvent = native.changed('en');
    await Future<void>.delayed(Duration.zero);
    final newerLocal = AppLanguage.setLanguage('zh');
    oldRead.complete('en');
    await staleEvent;
    await newerLocal;
    h.check(AppLanguage.locale.value == 'zh',
        'A native reply in flight must not overwrite a newer local choice');
    final delayedOldEvent = Completer<String?>();
    native.canonical = 'en';
    native.nextGet = delayedOldEvent;
    final olderRemote = native.changed('en');
    await Future<void>.delayed(Duration.zero);
    native.canonical = 'zh';
    await native.changed('zh');
    delayedOldEvent.complete('en');
    await olderRemote;
    h.check(AppLanguage.locale.value == 'zh',
        'A newer same-value native event must invalidate older queries');
    final writtenRead = Completer<String?>();
    native.nextGet = writtenRead;
    native.nextGetStarted = Completer<void>();
    final olderSave = AppLanguage.setLanguage('en');
    await native.nextGetStarted!.future;
    native.canonical = 'zh';
    await native.changed('zh');
    writtenRead.complete('en');
    await olderSave;
    h.check(
        AppLanguage.locale.value == 'zh' &&
            (jsonDecode(await file.readAsString()) as Map)['language'] == 'zh',
        'A superseded write must persist the newest native choice');
    AppLanguage.fileOverride = File('${blockedParent.path}/language.json');
    var linkedWriteFailed = false;
    try {
      await AppLanguage.setLanguage('en');
    } on FileSystemException {
      linkedWriteFailed = true;
    }
    h.check(
        linkedWriteFailed &&
            AppLanguage.locale.value == 'en' &&
            native.canonical == 'en',
        'A failed write must not roll back authoritative native language');
    AppLanguage.fileOverride = file;
    await AppLanguage.setLanguage('zh');
    var notifications = 0;
    void listener() => notifications++;
    AppLanguage.locale.addListener(listener);
    await native.changed('zh');
    AppLanguage.locale.removeListener(listener);
    h.check(notifications == 0, 'Same-language events should not rebuild UI');
    h.check(errors.isEmpty, errors.map((e) => e.exception).join('\n'));
    stdout.writeln(
        'PASS: language switch, live UI, retained state/content, persistence, corrupt preference, immediate response, native pushes, stale-event/write protection');
    runApp(const SizedBox.shrink());
    await h.settle();
  } finally {
    AppLanguage.fileOverride = null;
    await directory.delete(recursive: true);
  }
  exit(0);
}
