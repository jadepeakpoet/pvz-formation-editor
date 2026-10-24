// Real bundled assets; delayed mock audio channel tests initialization ordering.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:pvz_formation_editor/platform/original_audio.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  final cases = <Map<String, dynamic>>[];
  for (final muteDuringLoad in [false, true]) {
    await OriginalAudio.dispose();
    final blocked = Completer<void>();
    final release = Completer<void>();
    final calls = <Map<String, dynamic>>[];
    final statuses = <String>[];
    void statusChanged() => statuses.add(OriginalAudio.soundStatus.value);
    OriginalAudio.soundStatus.addListener(statusChanged);
    ParityBinding.handlers[OriginalAudio.channel.name] = (call) async {
      final args = call.arguments as Map?;
      calls.add({
        'method': call.method,
        'source': args?['source'],
        'volume': args?['volume']
      });
      if (call.method == 'configurePlantingSound' &&
          args?['source'] == 'plant2') {
        blocked.complete();
        await release.future;
      }
      return call.method == 'playPlantingSound' ? true : null;
    };
    final row = <String, dynamic>{
      'id': muteDuringLoad
          ? 'loading.mute-cancels-pending-water'
          : 'loading.water-waits-for-all-three',
      'status': 'pass'
    };
    try {
      final loading = OriginalAudio.setSoundVolume(.5);
      await blocked.future.timeout(const Duration(seconds: 5));
      final water = OriginalAudio.playPlantingSound(water: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (OriginalAudio.soundStatus.value != 'loading' ||
          statuses.contains('ready')) {
        throw StateError('Partial configuration exposed ready: $statuses');
      }
      if (calls.any((c) => c['method'] == 'playPlantingSound')) {
        throw StateError('Water playback emitted before source loaded');
      }
      Future<void>? mute;
      if (muteDuringLoad) mute = OriginalAudio.setSoundVolume(0);
      release.complete();
      await Future.wait([loading, water, if (mute != null) mute])
          .timeout(const Duration(seconds: 5));
      final configured = calls
          .where((c) => c['method'] == 'configurePlantingSound')
          .map((c) => c['source'])
          .toList();
      if (jsonEncode(configured) != '["plant1","plant2","plant_water"]' ||
          OriginalAudio.soundStatus.value != 'ready') {
        throw StateError('Full configuration incomplete');
      }
      final plays =
          calls.where((c) => c['method'] == 'playPlantingSound').toList();
      if (muteDuringLoad
          ? plays.isNotEmpty
          : plays.length != 1 || plays.single['source'] != 'plant_water') {
        throw StateError('Pending water/mute ordering incorrect: $plays');
      }
      row.addAll({'calls': calls, 'statuses': statuses});
    } catch (e, stack) {
      if (!release.isCompleted) release.complete();
      row.addAll({
        'status': 'fail',
        'error': '$e',
        'stack': '$stack',
        'calls': calls,
        'statuses': statuses
      });
    } finally {
      OriginalAudio.soundStatus.removeListener(statusChanged);
    }
    cases.add(row);
  }
  await OriginalAudio.dispose();
  final report = {
    'scope':
        'real bundled mp3 assets; mock audio channel with second configure reply explicitly blocked',
    'cases': cases
  };
  await File('${Directory.systemTemp.path}/pvz-planting-audio-race-report.json')
      .writeAsString(jsonEncode(report));
  stdout.writeln(jsonEncode(report));
  exit(cases.every((c) => c['status'] == 'pass') ? 0 : 1);
}
