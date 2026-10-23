import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'main_translations.dart';
import 'widget_translations.dart';

/// Application UI language. Document names and saved content remain untouched.
class AppLanguage {
  static final locale = ValueNotifier<String>('zh');
  static Future<void> _tail = Future.value();
  static File? fileOverride;
  static int _revision = 0;
  static Future<File> _file() async =>
      fileOverride ??
      File(
          '${(await getApplicationSupportDirectory()).path}/language-preferences.json');
  static Future<void> load() async {
    final revision = _revision;
    await _tail;
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString());
      if (revision == _revision &&
          data is Map &&
          const ['zh', 'en'].contains(data['language'])) {
        locale.value = data['language'] as String;
        await _syncNative();
      }
    } on FileSystemException {
      // A missing or temporarily unavailable preference uses the current language.
    } on FormatException {
      // Invalid preferences must not prevent opening the application.
    } on MissingPluginException {
      // Headless engines may not provide a platform application directory.
    }
  }

  static Future<void> _syncNative() async {
    try {
      await const MethodChannel('pvz_formation_editor/files')
          .invokeMethod<void>('setLanguage', {'language': locale.value});
    } on MissingPluginException {
      // Other platforms use their standard application title.
    } on PlatformException {
      // Native titles must not prevent changing the Flutter interface.
    }
  }

  static Future<void> setLanguage(String language) {
    if (!const ['zh', 'en'].contains(language)) {
      throw ArgumentError.value(language, 'language');
    }
    _revision++;
    final operation = _tail.then((_) async {
      final file = await _file();
      await file.parent.create(recursive: true);
      final temporaryDirectory = await file.parent.createTemp('.language-');
      try {
        final temporary = File('${temporaryDirectory.path}/preferences.json');
        await temporary.writeAsString(jsonEncode({'language': language}),
            flush: true);
        await temporary.rename(file.path);
      } finally {
        await temporaryDirectory.delete(recursive: true);
      }
      locale.value = language;
      await _syncNative();
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  static final Map<String, String> _translations = {
    ...mainTranslations,
    ...widgetTranslations,
    '语言': 'Language',
    '设置': 'Settings',
    '语言设置保存失败': 'Could not save language preference',
    '植物大战僵尸布阵器': 'PVZ Formation Editor',
  };
  static String text(String source) {
    if (locale.value != 'en') return source;
    final exact = _translations[source];
    if (exact != null) return exact;
    for (final entry in _templates) {
      final match = entry.pattern.firstMatch(source);
      if (match == null) continue;
      var result = entry.target;
      for (var i = 0; i < entry.names.length; i++) {
        result = result.replaceAll('{${entry.names[i]}}', match.group(i + 1)!);
      }
      return result;
    }
    return source;
  }

  static final _templates = _translations.entries
      .where((e) => RegExp(r'\{\w+\}').hasMatch(e.key))
      .map((e) => _Template(e.key, e.value))
      .toList()
    ..sort((a, b) => b.specificity.compareTo(a.specificity));
}

class _Template {
  final String target;
  final List<String> names = [];
  late final RegExp pattern;
  late final int specificity;
  _Template(String source, this.target) {
    specificity = source.replaceAll(RegExp(r'\{\w+\}'), '').length;
    final expression = StringBuffer('^');
    var offset = 0;
    for (final match in RegExp(r'\{(\w+)\}').allMatches(source)) {
      expression.write(RegExp.escape(source.substring(offset, match.start)));
      expression.write('([\\s\\S]*?)');
      names.add(match.group(1)!);
      offset = match.end;
    }
    expression.write(RegExp.escape(source.substring(offset)));
    expression.write(r'$');
    pattern = RegExp(expression.toString());
  }
}
