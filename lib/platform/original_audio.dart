import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;

/// Original background music played at application volume, never system volume.
/// Unsupported platforms and unavailable effects remain explicit to callers.
class OriginalAudio {
  static const channel = MethodChannel('pvz_formation_editor/audio');
  static const backgroundAsset = 'assets/original/audio/background.m4a';
  static final ValueNotifier<String> status = ValueNotifier('uninitialized');
  static final ValueNotifier<String> soundStatus =
      ValueNotifier('uninitialized');
  static const plantingAssets = {
    'plant1': 'assets/original/audio/plant1.mp3',
    'plant2': 'assets/original/audio/plant2.mp3',
    'plant_water': 'assets/original/audio/plant_water.mp3',
  };
  static final _random = math.Random();
  static final _soundSources = <String>{};
  static Future<void>? _soundInitializing;
  static bool _loadingSounds = false;
  static double musicVolume = .25, soundVolume = .5;
  static bool _ready = false;
  static Future<void>? _initializing;

  static Future<void> initialize() => _initializing ??= _initialize();
  static Future<void> _initialize() async {
    status.value = 'loading';
    try {
      final data = await rootBundle.load(backgroundAsset);
      await channel.invokeMethod<void>('initialize', {
        'bytes':
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      });
      _ready = true;
      status.value = 'paused';
    } on MissingPluginException {
      status.value = 'unsupportedPlatform';
    } on FlutterError {
      status.value = 'missingAsset';
    } on PlatformException catch (e) {
      status.value = 'error:${e.code}';
    }
  }

  static double _volume(double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, 'volume', '必须在 0 到 1 之间');
    }
    return value;
  }

  static Future<void> setMusicVolume(double value) async {
    musicVolume = _volume(value);
    await initialize();
    if (!_ready) return;
    try {
      final playing = await channel
          .invokeMethod<bool>('setMusicVolume', {'volume': musicVolume});
      status.value = playing == true
          ? 'playing'
          : musicVolume == 0
              ? 'paused'
              : 'playbackFailed';
    } on MissingPluginException {
      _ready = false;
      status.value = 'unsupportedPlatform';
    } on PlatformException catch (e) {
      status.value = 'error:${e.code}';
    }
  }

  static Future<void> initializeSounds() =>
      _soundInitializing ??= _initializeSounds();

  static Future<void> _initializeSounds() async {
    soundStatus.value = 'loading';
    _loadingSounds = true;
    try {
      for (final entry in plantingAssets.entries) {
        await configurePlantingSound(assetPath: entry.value, source: entry.key);
        if (!_soundSources.contains(entry.key)) return;
      }
      soundStatus.value = 'ready';
    } finally {
      _loadingSounds = false;
    }
  }

  /// Configure one of the source's two land sounds or its water sound.
  static Future<void> configurePlantingSound(
      {String? assetPath, Uint8List? bytes, String source = 'plant1'}) async {
    if (!plantingAssets.containsKey(source)) {
      throw ArgumentError.value(source, 'source');
    }
    if (assetPath == null && bytes == null) {
      soundStatus.value = 'missingAsset';
      return;
    }
    try {
      final loaded = bytes == null ? await rootBundle.load(assetPath!) : null;
      final data = bytes ??
          loaded!.buffer
              .asUint8List(loaded.offsetInBytes, loaded.lengthInBytes);
      await channel.invokeMethod<void>(
          'configurePlantingSound', {'bytes': data, 'source': source});
      _soundSources.add(source);
      soundStatus.value = _loadingSounds ? 'loading' : 'ready';
    } on MissingPluginException {
      soundStatus.value = 'unsupportedPlatform';
    } on FlutterError {
      soundStatus.value = 'missingAsset';
    } on PlatformException catch (e) {
      soundStatus.value = 'error:${e.code}';
    }
  }

  static Future<void> setSoundVolume(double value) async {
    soundVolume = _volume(value);
    await initializeSounds();
    if (soundStatus.value != 'ready') return;
    try {
      await channel
          .invokeMethod<void>('setSoundVolume', {'volume': soundVolume});
    } on MissingPluginException {
      soundStatus.value = 'unsupportedPlatform';
    } on PlatformException catch (e) {
      soundStatus.value = 'error:${e.code}';
    }
  }

  static Future<void> playPlantingSound({bool water = false}) async {
    if (soundVolume == 0) return;
    await initializeSounds();
    if (soundStatus.value != 'ready' || soundVolume == 0) return;
    try {
      final played = await channel.invokeMethod<bool>('playPlantingSound', {
        'volume': soundVolume,
        'source': water ? 'plant_water' : 'plant${1 + _random.nextInt(2)}',
      });
      if (played != true) soundStatus.value = 'playbackFailed';
    } on MissingPluginException {
      soundStatus.value = 'unsupportedPlatform';
    } on PlatformException catch (e) {
      soundStatus.value = 'error:${e.code}';
    }
  }

  static Future<void> dispose() async {
    try {
      if (_ready || _soundSources.isNotEmpty) {
        await channel.invokeMethod<void>('dispose');
      }
    } on MissingPluginException {
      // A platform without this plugin has no native player to dispose.
    } on PlatformException catch (e) {
      status.value = 'error:${e.code}';
      return;
    }
    _ready = false;
    _initializing = null;
    _soundInitializing = null;
    _soundSources.clear();
    musicVolume = 0;
    soundVolume = 0;
    status.value = 'disposed';
    soundStatus.value = 'uninitialized';
  }
}
