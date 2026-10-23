import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/planting_support.dart';

class PlantingPreferences {
  final bool autoLily;
  final String potMode;
  const PlantingPreferences({this.autoLily = true, this.potMode = 'roof'});
  static PlantingPreferences current = const PlantingPreferences();
  static Future<void> _tail = Future.value();
  static Future<File> _file() async => File(
      '${(await getApplicationSupportDirectory()).path}/planting-preferences.json');
  static Future<PlantingPreferences> load({File? file}) async {
    try {
      final source = file ?? await _file();
      if (!await source.exists()) return current = const PlantingPreferences();
      final value = jsonDecode(await source.readAsString());
      return current = PlantingPreferences(
          autoLily: value is Map && value['autoLily'] is bool
              ? value['autoLily'] as bool
              : true,
          potMode: value is Map &&
                  PlantingSupport.potModes.contains(value['potMode'])
              ? value['potMode'] as String
              : 'roof');
    } on MissingPluginException {
      return current = const PlantingPreferences();
    } on FileSystemException {
      return current = const PlantingPreferences();
    } on FormatException {
      return current = const PlantingPreferences();
    }
  }

  Future<void> save({File? file}) {
    current = this;
    final operation = _tail.then((_) async {
      final target = file ?? await _file();
      await target.parent.create(recursive: true);
      final temporary = File('${target.path}.tmp');
      try {
        await temporary.writeAsString(
            jsonEncode({'autoLily': autoLily, 'potMode': potMode}),
            flush: true);
        await temporary.rename(target.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    });
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }
}
