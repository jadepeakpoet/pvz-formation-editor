import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/original_catalog.dart';

/// Original site's local artwork and DOM sprite frame definitions.
class OriginalAssets {
  static final Map<String, ui.Image> images = {};
  static final Map<String, Uint8List> _hitMasks = {};
  static final Map<String, Future<void>> _hitLoading = {};

  /// Compact one-bit silhouettes, loaded only for objects in the editor.
  static Future<void> ensureHitMasks(Iterable<String> types) async {
    await ensureLoaded();
    final paths = <String>{
      for (final type in types)
        for (final part
            in sprites[names[type] ?? type]?['images'] as List? ?? [])
          if (!(part['path'] as String).endsWith('/shadow.png'))
            part['path'] as String
    };
    await Future.wait(
        paths.map((path) => _hitLoading.putIfAbsent(path, () async {
              final source = images[path];
              if (source == null) return;
              final raw =
                  await source.toByteData(format: ui.ImageByteFormat.rawRgba);
              if (raw == null) return;
              final rgba =
                  raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
              final mask = Uint8List((source.width * source.height + 7) ~/ 8);
              for (var pixel = 0;
                  pixel < source.width * source.height;
                  pixel++) {
                if (rgba[pixel * 4 + 3] >= 16) {
                  mask[pixel >> 3] |= 1 << (pixel & 7);
                }
              }
              _hitMasks[path] = mask;
              revision.value++;
            })));
  }

  static bool opaqueAt(String path, int x, int y) {
    final source = images[path];
    final mask = _hitMasks[path];
    if (source == null ||
        mask == null ||
        x < 0 ||
        y < 0 ||
        x >= source.width ||
        y >= source.height) return false;
    final pixel = y * source.width + x;
    return mask[pixel >> 3] & (1 << (pixel & 7)) != 0;
  }

  static final Map<String, dynamic> sprites = {};
  static final Map<String, ui.Image> _grayImages = {};
  static final Map<String, double> _lights = {};
  static final Map<String, String> kinds = {};
  static final Map<String, Future<void>> _grayLoading = {};

  // Imitation artwork is derived only when a visible sprite requests it. Loading
  // the library should not read back and transform every source texture first.
  // The next revision repaints callers once the exact HSL image is ready.
  static ui.Image? grayImage(String name, String path) {
    final light = _lights[name] ?? 1.9;
    final key = '$path:$light';
    final cached = _grayImages[key];
    if (cached != null) return cached;
    final source = images[path];
    if (source != null) {
      _grayLoading.putIfAbsent(key, () => _loadGray(key, path, source, light));
    }
    return null;
  }

  /// Prepare only the imitation types required for a one-shot image export.
  /// Interactive painters use [grayImage] and repaint when generation finishes.
  static Future<void> ensureImitationImages(Iterable<String> types) async {
    await ensureLoaded();
    final requested = <String>{};
    for (final type in types) {
      final name = names[type] ?? type;
      requested.add(name);
      if (name == 'Pumpkin') requested.add('Pumpkin_back');
      if (name == 'ScaryPot') requested.add('ScaryPot_back');
    }
    final pending = <Future<void>>[];
    for (final name in requested) {
      for (final part in sprites[name]?['images'] as List? ?? const []) {
        final path = part['path'] as String;
        grayImage(name, path);
        final loading = _grayLoading['$path:${_lights[name] ?? 1.9}'];
        if (loading != null) pending.add(loading);
      }
    }
    await Future.wait(pending);
  }

  static Future<void> _loadGray(
      String key, String path, ui.Image source, double light) async {
    try {
      final raw = await source.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (raw == null) throw StateError('Cannot read original sprite $path');
      final pixels = Uint8List.fromList(
          raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes));
      // Source imitation uses HSL lightness and the template multiplier.
      // Retain its premultiplied-alpha clamp; a color matrix is not equivalent.
      for (var i = 0; i < pixels.length; i += 4) {
        final high =
            math.max(pixels[i], math.max(pixels[i + 1], pixels[i + 2]));
        final low = math.min(pixels[i], math.min(pixels[i + 1], pixels[i + 2]));
        final gray = ((high + low) * light / 2).round().clamp(0, pixels[i + 3]);
        pixels[i] = pixels[i + 1] = pixels[i + 2] = gray;
      }
      final decoded = Completer<ui.Image>();
      ui.decodeImageFromPixels(pixels, source.width, source.height,
          ui.PixelFormat.rgba8888, decoded.complete);
      _grayImages[key] = await decoded.future;
      revision.value++;
    } catch (error) {
      debugPrint('Original imitation artwork $path: $error');
    } finally {
      _grayLoading.remove(key);
    }
  }

  static final Map<String, dynamic> maps = {};
  static final ValueNotifier<int> revision = ValueNotifier(0);
  static Future<void>? _loading;
  static const names = <String, String>{
    'lily': 'Lilypad',
    'pot': 'Pot',
    'pea': 'Peashooter',
    'sunflower': 'Sunflower',
    'doubleSun': 'Twinsunflower',
    'repeater': 'Repeater',
    'gatling': 'Gatlingpea',
    'snow': 'Snowpea',
    'wallnut': 'Wallnut',
    'tallnut': 'Tallnut',
    'pumpkin': 'Pumpkin',
    'coffee': 'Coffeebean',
    'cob': 'Cobcannon',
    'gloom': 'Gloomshroom',
    'fume': 'Fumeshroom',
    'ice': 'Iceshroom',
    'doom': 'Doomshroom',
    'cattail': 'Cattail',
    'umbrella': 'Umbrellaleaf',
    'spike': 'Spikerock',
    'garlic': 'Garlic',
    'melon': 'Melonpult',
    'winter': 'Wintermelon',
    'cherry': 'Cherrybomb',
    'potato': 'Potatomine',
    'chomper': 'Chomper',
    'puff': 'Puffshroom',
    'sunshroom': 'Sunshroom',
    'gravebuster': 'Gravebuster',
    'hypno': 'Hypnoshroom',
    'scaredy': 'Scaredyshroom',
    'squash': 'Squash',
    'threepea': 'Threepeater',
    'tangle': 'Tanglekelp',
    'jalapeno': 'Jalapeno',
    'spikeweed': 'Caltrop',
    'torch': 'Torchwood',
    'seashroom': 'Seashroom',
    'plantern': 'Plantern',
    'cactus': 'Cactus',
    'blover': 'Blover',
    'splitpea': 'Splitpea',
    'starfruit': 'Starfruit',
    'magnet': 'Magnetshroom',
    'cabbage': 'Cabbagepult',
    'kernel': 'Cornpult',
    'goldmagnet': 'GoldMagnet',
    'marigold': 'Marigold',
    'zombie': 'Zombie',
    'cone': 'ConeheadZombie',
    'bucket': 'BucketheadZombie',
    'gargantuar': 'Gargantuar',
    'flag': 'FlagZombie',
    'pole': 'PoleVaultingZombie',
    'newspaper': 'NewspaperZombie',
    'screen': 'ScreenDoorZombie',
    'football': 'FootballZombie',
    'dancer': 'DancingZombie',
    'backup': 'BackupDancer',
    'ducky': 'DuckyTubeZombie',
    'snorkel': 'SnorkelZombie',
    'zomboni': 'Zomboni',
    'dolphin': 'DolphinRiderZombie',
    'jack': 'JackinTheBoxZombie',
    'balloon': 'BalloonZombie',
    'digger': 'DiggerZombie',
    'pogo': 'PogoZombie',
    'yeti': 'ZombieYeti',
    'bungee': 'BungiZombie',
    'ladderZombie': 'LadderZombie',
    'catapult': 'Catapult',
    'imp': 'Imp',
    'rake': 'Rake',
    'grave': 'Tombstones',
    'ladder': 'Ladder',
    'crater': 'Crater',
    'iceTrail': 'ice',
  };
  static String cardPath(String type, {bool imitater = false}) =>
      'assets/original/image/Card/${names[type] ?? type}${imitater ? '_i' : ''}.png';
  static ui.Image? image(String path) => images[path];
  static Future<void> ensureLoaded() => _loading ??= _load();
  static Future<void> _load() async {
    final continuum = FontLoader('Continuum Bold')
      ..addFont(rootBundle.load('assets/original/fonts/ContinuumBold.ttf'));
    await continuum.load();
    maps.addAll(
        jsonDecode(await rootBundle.loadString('assets/original/maps.json'))
            as Map<String, dynamic>);
    sprites.addAll(
        jsonDecode(await rootBundle.loadString('assets/original/sprites.json'))
            as Map<String, dynamic>);
    await _loadImages();
    // The original imitation filter uses HSL lightness, then the template's
    // light multiplier. Its min/max operation cannot be a linear color matrix.
    for (final template in OriginalCatalog.templates) {
      final name = (template['id'] as String).substring(1);
      final match =
          RegExp(r'\blight="([^"]+)"').firstMatch(template['html'] as String);
      final kind =
          RegExp(r'\bpkind="([^"]+)"').firstMatch(template['html'] as String);
      if (kind != null) kinds[name] = kind.group(1)!;
      _lights[name] = double.tryParse(match?.group(1) ?? '') ?? 1.9;
    }
    revision.value++;
  }

  static Future<void> _loadImages() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('assets/original/manifest.json'))
            as List;
    await Future.wait(manifest
        .whereType<String>()
        .where((path) =>
            RegExp(r'\.(png|jpg|gif)$', caseSensitive: false).hasMatch(path))
        .map((path) async {
      try {
        final data = await rootBundle.load('assets/original/$path');
        final codec = await ui.instantiateImageCodec(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
        try {
          images[path] = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } catch (error) {
        debugPrint('Original artwork $path: $error');
      }
    }));
  }
}
