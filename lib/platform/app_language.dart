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
  static int _nativeEventRevision = 0;
  static Future<File> _file() async =>
      fileOverride ??
      File(
          '${(await getApplicationSupportDirectory()).path}/language-preferences.json');
  static const _native = MethodChannel('pvz_formation_editor/language');
  static bool _handlerInstalled = false, _nativeLinked = false, _loaded = false;
  static Future<void>? _loading;

  static void _ensureNativeHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _native.setMethodCallHandler((call) async {
      if (call.method != 'changed') throw MissingPluginException();
      final arguments = call.arguments;
      final supplied = arguments is Map ? arguments['language'] : null;
      if (!const ['zh', 'en'].contains(supplied)) return;
      final revision = _revision;
      final nativeEventRevision = ++_nativeEventRevision;
      // A queued event can describe an older selection. Ask for the current
      // native value instead of letting that event overwrite a newer choice.
      final current = await _nativeLanguage();
      if (revision != _revision ||
          nativeEventRevision != _nativeEventRevision) {
        return;
      }
      _nativeLinked = true;
      _loaded = true;
      _receive(current ?? supplied as String);
    });
  }

  static void _receive(String language) {
    if (locale.value == language) return;
    _revision++;
    locale.value = language;
  }

  static Future<String?> _nativeLanguage() async {
    try {
      final language = await _native.invokeMethod<String>('getLanguage');
      return const ['zh', 'en'].contains(language) ? language : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<void> load() {
    _ensureNativeHandler();
    // A connected native host pushes changes immediately. Polling its older
    // disk snapshot can only delay or undo that live choice.
    if (_nativeLinked && _loaded) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  static Future<void> _load() async {
    final revision = _revision;
    final nativeEventRevision = _nativeEventRevision;
    await _tail;
    final nativeLanguage = await _nativeLanguage();
    if (revision != _revision || nativeEventRevision != _nativeEventRevision) {
      return;
    }
    if (nativeLanguage != null) {
      _nativeLinked = true;
      _loaded = true;
      _receive(nativeLanguage);
      return;
    }
    try {
      final file = await _file();
      final exists = await file.exists();
      if (revision != _revision || nativeEventRevision != _nativeEventRevision) {
        return;
      }
      if (!exists) {
        _loaded = true;
        unawaited(_syncNative(locale.value, initializeOnly: true));
        return;
      }
      final data = jsonDecode(await file.readAsString());
      if (revision == _revision &&
          nativeEventRevision == _nativeEventRevision &&
          data is Map &&
          const ['zh', 'en'].contains(data['language'])) {
        _receive(data['language'] as String);
        _loaded = true;
        unawaited(_syncNative(locale.value, initializeOnly: true));
      }
    } on FileSystemException {
      // A temporarily unavailable preference uses the current language.
    } on FormatException {
      // Invalid preferences must not prevent opening the application.
    } on MissingPluginException {
      // Headless engines may not provide a platform application directory.
    }
  }

  static Future<void> _syncNative(String language,
      {bool initializeOnly = false}) async {
    try {
      await const MethodChannel('pvz_formation_editor/files')
          .invokeMethod<void>('setLanguage',
              {'language': language, 'initializeOnly': initializeOnly});
    } on MissingPluginException {
      // Other platforms use their standard application title.
    } on PlatformException {
      // Native titles must not prevent changing the Flutter interface.
    }
  }

  static Future<void> _write(File file, String language) async {
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
  }

  static Future<void> setLanguage(String language) {
    if (!const ['zh', 'en'].contains(language)) {
      throw ArgumentError.value(language, 'language');
    }
    _ensureNativeHandler();
    final previous = locale.value;
    final revision = ++_revision;
    _loaded = true;
    // Respond in this event turn, before path lookup, fsync or native replies.
    locale.value = language;
    unawaited(_syncNative(language));
    final operation = _tail.then((_) async {
      try {
        final file = await _file();
        for (var attempt = 0; attempt < 8; attempt++) {
          final writeRevision = _revision;
          final writeNativeRevision = _nativeEventRevision;
          final desired = locale.value;
          await _write(file, desired);
          final canonical = await _nativeLanguage();
          if (canonical != null &&
              writeRevision == _revision &&
              writeNativeRevision == _nativeEventRevision) {
            _nativeLinked = true;
            _receive(canonical);
          }
          if (writeRevision == _revision &&
              writeNativeRevision == _nativeEventRevision &&
              desired == locale.value &&
              (canonical == null || canonical == desired)) return;
        }
        throw const FileSystemException(
            'Language changed during preference save');
      } catch (_) {
        // Never roll back a selection made later by this or another window.
        if (_nativeLinked) {
          // Native state represents all engines, including newer same-value
          // choices which do not increment this engine's locale notifier.
          final failedRevision = _revision;
          final failedNativeRevision = _nativeEventRevision;
          final canonical = await _nativeLanguage();
          if (canonical != null &&
              failedRevision == _revision &&
              failedNativeRevision == _nativeEventRevision) {
            _receive(canonical);
          }
        } else if (_revision == revision && locale.value == language) {
          _revision++;
          locale.value = previous;
          unawaited(_syncNative(previous));
        }
        rethrow;
      }
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
