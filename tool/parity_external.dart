import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/platform/project_files.dart';

/// Parameter validation only: no external browser is opened.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Directionality(
      textDirection: TextDirection.ltr, child: Text('外链参数验收')));
  final cases = <Map<String, Object>>[];
  try {
    for (final source in [
      'https://pvz.lmintlcx.com/',
      'https://tieba.baidu.com/p/5272254427',
      'https://www.pvz.moe/?a=1&b=2',
      'https://example.com/a%20b?q=%27%3B%24%28x%29#part'
    ]) {
      ProjectFiles.validateExternal(Uri.parse(source));
      cases.add({'url': source, 'result': 'accepted'});
    }
    for (final source in [
      'file:///tmp/test',
      'javascript:alert(1)',
      'data:text/html,test',
      'mailto:test@example.com',
      'ftp://example.com',
      '//example.com',
      'https:///',
      'http:example.com',
      'https://user:pass@example.com',
      'https://@example.com',
      'https://example.com/%0aInjected',
      'https://example.com/%0DInjected'
    ]) {
      var rejected = false;
      try {
        await ProjectFiles.openExternal(Uri.parse(source));
      } on ArgumentError {
        rejected = true;
      }
      if (!rejected) throw StateError('accepted invalid external URL: $source');
      cases.add({'url': source, 'result': 'rejectedBeforeDispatch'});
    }
    await File('/tmp/pvz-external-results.json')
        .writeAsString(jsonEncode({'success': true, 'cases': cases}));
    exit(0);
  } catch (e, st) {
    await File('/tmp/pvz-external-results.json').writeAsString(jsonEncode(
        {'success': false, 'error': '$e', 'stack': '$st', 'cases': cases}));
    exit(1);
  }
}
