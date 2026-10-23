import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/platform/original_audio.dart';

/// Run: flutter run -d macos -t tool/parity_audio.dart
/// Verifies the real native AVAudioPlayer, briefly playing each volume level.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('原站音频功能验收'))));
  final cases = <Map<String, Object?>>[];
  try {
    await OriginalAudio.initialize();
    if (OriginalAudio.status.value != 'paused') {
      throw StateError('initialize: ${OriginalAudio.status.value}');
    }
    for (final volume in [0.0, 0.25, 0.5, 0.75, 1.0, 0.0]) {
      await OriginalAudio.setMusicVolume(volume);
      final native = await OriginalAudio.channel
          .invokeMapMethod<String, dynamic>('diagnostics');
      if (native?['musicLoaded'] != true ||
          native?['musicLoops'] != -1 ||
          native?['musicPlaying'] != (volume > 0) ||
          ((native?['musicVolume'] as num).toDouble() - volume).abs() > 0.001) {
        throw StateError('native volume $volume: $native');
      }
      cases.add({'id': 'AUDIO-MUSIC-$volume', 'pass': true, 'native': native});
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await OriginalAudio.setSoundVolume(1);
    await OriginalAudio.playPlantingSound();
    if (OriginalAudio.soundStatus.value != 'missingAsset') {
      throw StateError('missing asset reported as ready');
    }
    cases.add(
        {'id': 'AUDIO-SOUND', 'result': 'missingAsset', 'implemented': false});
    for (final invalid in [-1.0, 1.1, double.nan, double.infinity]) {
      var rejected = false;
      try {
        await OriginalAudio.setMusicVolume(invalid);
      } on ArgumentError {
        rejected = true;
      }
      if (!rejected) throw StateError('invalid volume accepted: $invalid');
    }
    await OriginalAudio.dispose();
    final native = await OriginalAudio.channel
        .invokeMapMethod<String, dynamic>('diagnostics');
    if (native?['musicLoaded'] != false || native?['musicPlaying'] != false) {
      throw StateError('dispose failed');
    }
    cases.add({'id': 'AUDIO-DISPOSE', 'pass': true, 'native': native});
    await File('/tmp/pvz-audio-results.json')
        .writeAsString(jsonEncode({'success': true, 'cases': cases}));
    exit(0);
  } catch (e, st) {
    await OriginalAudio.dispose();
    await File('/tmp/pvz-audio-results.json').writeAsString(jsonEncode(
        {'success': false, 'error': '$e', 'stack': '$st', 'cases': cases}));
    exit(1);
  }
}
