import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:io' show ZLibDecoder;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/formation.dart';
import 'image_resources.dart';

/// Original site's local artwork and DOM sprite frame definitions.
class OriginalAssets {
  static final images = ImageResources(maximumBytes: 24 << 20);
  static final Map<String, Uint8List> _hitMasks = {};

  /// Compatibility helper for tools that inspect every appearance of a type.
  /// The editor itself requests only its current frames via ensurePieceImages.
  static Future<void> ensureHitMasks(Iterable<String> types) async {
    await ensureLoaded();
    final pending = <Future<void>>[];
    for (final type in types) {
      for (final part
          in sprites[names[type] ?? type]?['images'] as List? ?? []) {
        if ((part['path'] as String).endsWith('/shadow.png')) continue;
        for (var row = 0; row < (part['rows'] as num).toInt(); row++) {
          for (var col = 0; col < (part['cols'] as num).toInt(); col++) {
            pending.add(_ensureFrameMask(part as Map, row, col));
          }
        }
      }
    }
    await Future.wait(pending);
  }

  static Map<String, Object> resourceStats() => {
        'decodedBytes': images.bytes,
        'decodedImages': images.length,
        'imageKeys': images.keys.toList(),
        'imitationBytes': _grayImages.bytes,
        'imitationImages': _grayImages.length,
        'maskBytes': _hitMasks.values.fold<int>(0, (a, b) => a + b.length),
        'fullSpriteSheets':
            images.keys.where((key) => _frameIndex.containsKey(key)).toList(),
      };

  static final Map<String, dynamic> sprites = {};
  static final _grayImages = ImageResources(maximumBytes: 8 << 20);
  static void releaseColdImages() {
    images.trim(minimumAge: Duration.zero, targetBytes: 0);
    _grayImages.trim(minimumAge: Duration.zero, targetBytes: 0);
  }

  static Future<T> retainImitationDuring<T>(Future<T> Function() work) =>
      _grayImages.retainDuring(work);
  static final Map<String, double> _lights = {};
  static final Map<String, String> kinds = {};
  static final Map<String, Future<void>> _grayLoading = {};

  // Imitation artwork is derived only when a visible sprite requests it. Loading
  // the library should not read back and transform every source texture first.
  // The next revision repaints callers once the exact HSL image is ready.
  static ui.Image? grayImage(String name, String path, {double scale = 1}) {
    final light = _lights[name] ?? 1.9;
    final sourceKey = imageKey(path, scale);
    final key = '$sourceKey:$light';
    final cached = _grayImages[key];
    if (cached != null) return cached;
    final source = images[sourceKey];
    if (source != null) {
      _grayLoading.putIfAbsent(
          key, () => _loadGray(key, path, source.clone(), light));
    }
    return null;
  }

  /// Prepare only the imitation types required for a one-shot image export.
  /// Interactive painters use [grayImage] and repaint when generation finishes.
  static Future<void> ensureImitationImages(Iterable<String> types) async {
    await ensureTypes(types);
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
      // toByteData already returns an independent writable readback buffer.
      final pixels =
          raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
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
      source.dispose();
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
      'assets/original/image/Card/${type == 'grave' ? 'Tombstone' : names[type] ?? type}${imitater ? '_i' : ''}.png';
  static final Map<String, Future<void>> _imageLoading = {};
  static final _sourceSizes = <String, ui.Size>{};
  static ui.Size? sourceSize(String path) => _sourceSizes[path];
  static String imageKey(String path, double scale) =>
      scale == 1 ? path : "$path@${scale.toStringAsFixed(3)}";
  static ui.Image? image(String path, {double scale = 1}) {
    final cached = images[imageKey(path, scale)];
    if (cached == null) unawaited(_loadImage(path, scale: scale));
    return cached;
  }

  static final _frameIndex = <String, dynamic>{};
  static String spriteFramePath(Map part, int row, int col) {
    final path = part['path'] as String;
    final entry = _frameIndex[path] as Map?;
    if (entry == null) return path;
    final index = (row % (entry['rows'] as int)) * (entry['cols'] as int) +
        col % (entry['cols'] as int);
    return 'frames/${(entry['frames'] as List)[index]}.png';
  }

  static ui.Image? spriteImage(Map part, int row, int col,
      {double scale = 1, String? imitation}) {
    final path = spriteFramePath(part, row, col);
    final normal = image(path, scale: scale);
    return imitation == null
        ? normal
        : grayImage(imitation, path, scale: scale) ?? normal;
  }

  static Iterable<(String, Map)> _spriteParts(String type) sync* {
    final name = names[type] ?? type;
    for (final variant in [
      name,
      '${name}_back',
      if (name == 'Gloomshroom') 'GloomPuff'
    ]) {
      for (final part in sprites[variant]?['images'] as List? ?? []) {
        yield (variant, part as Map);
      }
    }
  }

  /// A visual state becomes presentable only when all of its layers are ready.
  static bool pieceImagesReady(Piece piece) {
    for (final (variant, part) in _spriteParts(piece.type)) {
      final key = spriteFramePath(part, piece.frameRow, piece.frameCol);
      if (images[key] == null) return false;
      if (piece.effects.contains('模仿者') && variant != 'GloomPuff' &&
          _grayImages['$key:${_lights[variant] ?? 1.9}'] == null) {
        return false;
      }
    }
    return true;
  }

  /// Protect the outgoing appearance only for the duration of a frame change.
  static VoidCallback retainPieceImages(Piece piece) {
    final normal = <String>{};
    final gray = <String>{};
    for (final (variant, part) in _spriteParts(piece.type)) {
      final key = spriteFramePath(part, piece.frameRow, piece.frameCol);
      normal.add(key);
      if (piece.effects.contains('模仿者') && variant != 'GloomPuff') {
        gray.add('$key:${_lights[variant] ?? 1.9}');
      }
    }
    for (final key in normal) { images.pin(key); }
    for (final key in gray) { _grayImages.pin(key); }
    var released = false;
    return () {
      if (released) return;
      released = true;
      for (final key in normal) { images.unpin(key); }
      for (final key in gray) { _grayImages.unpin(key); }
    };
  }

  static Future<void> _ensureSprite(String type, int row, int col,
      {double scale = 1, bool imitation = false, bool hitMasks = false}) async {
    final name = names[type] ?? type;
    for (final variant in [
      name,
      '${name}_back',
      if (name == 'Gloomshroom') 'GloomPuff'
    ]) {
      for (final part in sprites[variant]?['images'] as List? ?? []) {
        final path = spriteFramePath(part as Map, row, col);
        await _loadImage(path, scale: scale);
        if (imitation && variant != 'GloomPuff') {
          grayImage(variant, path, scale: scale);
          await _grayLoading[
              '${imageKey(path, scale)}:${_lights[variant] ?? 1.9}'];
        }
        if (hitMasks && !(part['path'] as String).endsWith('/shadow.png')) {
          await _ensureFrameMask(part, row, col);
        }
      }
    }
  }

  static Future<void> ensurePieceImages(Iterable<Piece> pieces,
      {double scale = 1, bool hitMasks = false}) async {
    await ensureLoaded();
    await Future.wait(pieces.map((piece) => _ensureSprite(
        piece.type, piece.frameRow, piece.frameCol,
        scale: scale,
        imitation: piece.effects.contains('\u6a21\u4eff\u8005'),
        hitMasks: hitMasks)));
  }

  static Future<void> ensureSpriteTypes(Iterable<String> types,
      {double scale = 1}) async {
    await ensureLoaded();
    await Future.wait(
        types.map((type) => _ensureSprite(type, 0, 0, scale: scale)));
  }

  static final _frameMaskLoading = <String, Future<void>>{};
  static Future<void> _ensureFrameMask(Map part, int row, int col) {
    final path = spriteFramePath(part, row, col);
    return _frameMaskLoading.putIfAbsent(path, () async {
      final data = await rootBundle
          .load('assets/original/${path.replaceFirst('.png', '.mask')}');
      _hitMasks[path] = Uint8List.fromList(ZLibDecoder().convert(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
      revision.value++;
    });
  }

  static bool frameOpaqueAt(Map part, int row, int col, int x, int y) {
    final path = spriteFramePath(part, row, col);
    final mask = _hitMasks[path];
    if (mask == null) {
      unawaited(_ensureFrameMask(part, row, col));
      return false;
    }
    final width = (part['rw'] as num).toInt(),
        height = (part['rh'] as num).toInt();
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    final pixel = y * width + x;
    return mask[pixel >> 3] & (1 << (pixel & 7)) != 0;
  }

  static Future<void> ensureMapImages(String mapName,
      {double scale = 1}) async {
    await ensureLoaded();
    await Future.wait((maps[mapName] as List? ?? [])
        .map((layer) => _loadImage(layer['path'] as String, scale: scale)));
  }

  static void releaseTypeSheets(String type) {
    final name = names[type] ?? type;
    for (final variant in [
      name,
      '${name}_back',
      if (name == 'Gloomshroom') 'GloomPuff'
    ]) {
      for (final part in sprites[variant]?['images'] as List? ?? []) {
        images.remove(part['path'] as String);
      }
    }
  }

  static Future<void> ensureTypes(Iterable<String> types) async {
    await ensureLoaded();
    final paths = <String>{};
    for (final type in types) {
      final name = names[type] ?? type;
      for (final variant in [
        name,
        '${name}_back',
        if (name == 'Gloomshroom') 'GloomPuff'
      ]) {
        for (final part in sprites[variant]?['images'] as List? ?? []) {
          paths.add(part['path'] as String);
        }
      }
    }
    await Future.wait(paths.map(_loadImage));
  }

  static final _decodeSlots =
      List<Future<void>>.generate(4, (_) => Future.value());
  static int _decodeSlot = 0;
  static Future<void> _loadImage(String path, {double scale = 1}) {
    final key = imageKey(path, scale);
    if (images.containsKey(key)) return Future.value();
    return _imageLoading.putIfAbsent(key, () {
      final slot = _decodeSlot++ % _decodeSlots.length;
      final job = _decodeSlots[slot].then((_) async {
        try {
          final data = await rootBundle.load('assets/original/$path');
          final buffer = await ui.ImmutableBuffer.fromUint8List(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
          final descriptor = await ui.ImageDescriptor.encoded(buffer);
          try {
            _sourceSizes[path] = ui.Size(
                descriptor.width.toDouble(), descriptor.height.toDouble());
            final codec = await descriptor.instantiateCodec(
                targetWidth: (descriptor.width * scale).ceil(),
                targetHeight: (descriptor.height * scale).ceil());
            try {
              images[key] = (await codec.getNextFrame()).image;
            } finally {
              codec.dispose();
            }
          } finally {
            descriptor.dispose();
            buffer.dispose();
          }
          revision.value++;
        } catch (error) {
          debugPrint('Original artwork $path: $error');
        } finally {
          _imageLoading.remove(key);
        }
      });
      _decodeSlots[slot] = job;
      return job;
    });
  }

  static Future<void> ensureLoaded() => _loading ??= _load();
  static Future<void> _load() async {
    final continuum = FontLoader('Continuum Bold')
      ..addFont(rootBundle.load('assets/original/fonts/ContinuumBold.ttf'));
    await continuum.load();
    maps.addAll(
        jsonDecode(await rootBundle.loadString('assets/original/maps.json'))
            as Map<String, dynamic>);
    _frameIndex.addAll(jsonDecode(
            await rootBundle.loadString('assets/original/frames/index.json'))
        as Map<String, dynamic>);
    sprites.addAll(
        jsonDecode(await rootBundle.loadString('assets/original/sprites.json'))
            as Map<String, dynamic>);

    final styles = jsonDecode(
            await rootBundle.loadString('assets/original/frames/styles.json'))
        as Map;
    for (final entry in styles.entries) {
      final style = entry.value as Map;
      _lights[entry.key as String] = (style['light'] as num).toDouble();
      if (style['kind'] != null) {
        kinds[entry.key as String] = style['kind'] as String;
      }
    }
    revision.value++;
  }

  static Future<void> ensureBoardImages(
      String mapName, Iterable<String> seedTypes) async {
    await ensureLoaded();
    final paths = <String>{
      for (final layer in maps[mapName] as List? ?? []) layer['path'] as String,
      'image/Seed.png',
      'image/Button.png',
      'image/brain.png',
      'image/Shovel.png',
      'image/fog.jpg',
      'image/fog_.jpg',
      for (final type in seedTypes)
        cardPath(type).replaceFirst('assets/original/', ''),
      for (final type in seedTypes)
        cardPath(type, imitater: true).replaceFirst('assets/original/', ''),
    };
    for (var i = 0; i < paths.length; i += 4) {
      await Future.wait(paths.skip(i).take(4).map(_loadImage));
    }
  }
}
