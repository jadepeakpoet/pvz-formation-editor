import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../domain/formation.dart';

/// Versioned, reproducible PNGs. Cache failure never changes or blocks archives.
class ThumbnailStore {
  static Directory? directoryOverride;
  static Future<Directory?>? _root;
  static int bundledHits = 0,
      diskHits = 0,
      generated = 0,
      skipped = 0,
      memoryHits = 0;
  static int _writes = 0;
  static Future<void>? _sweep;
  static const rendererVersion = 3;
  static const maximumDiskBytes = 64 << 20;
  static const maximumFiles = 2048;
  static String key(Formation document) => sha256
      .convert(utf8.encode(jsonEncode({
        'renderer': rendererVersion,
        'size': [256, 192],
        'map': document.mapId,
        'objects': [
          for (final piece in document.pieces)
            Map<String, dynamic>.from(piece.toJson())..remove('id')
        ],
      })))
      .toString();
  static Future<Directory?> directory() async {
    if (directoryOverride != null) {
      await directoryOverride!.create(recursive: true);
      return directoryOverride;
    }
    return _root ??= (() async {
      try {
        final base = await getApplicationCacheDirectory();
        final dir = Directory('${base.path}/formation-thumbnails/v3-256');
        await dir.create(recursive: true);
        return dir;
      } catch (_) {
        return null;
      }
    })();
  }

  static final preparationProgress = ValueNotifier<double?>(null);
  static Future<void> primeBuiltins() async {
    final dir = await directory();
    if (dir == null) return;
    final marker = File('${dir.path}/ready-v3');
    if (await marker.exists()) return;
    try {
      preparationProgress.value = 0;
      final index = jsonDecode(await rootBundle
          .loadString('assets/original/thumbnails/index.json')) as Map;
      final keys = Set<String>.from(index['keys'] as List);
      final keyPattern = RegExp(r'^[0-9a-f]{64}$');
      if (index['version'] != 3 ||
          keys.any((key) => !keyPattern.hasMatch(key))) {
        throw const FormatException('Preview index');
      }
      // The compressed files are already local in flutter_assets. No startup
      // copy or decode of the 363 previews is necessary.
      _bundledKeys = Future.value(keys);
      preparationProgress.value = 1;
      await marker.writeAsString('3:${keys.length}', flush: true);
    } catch (error) {
      debugPrint('Thumbnail cache preparation: $error');
    } finally {
      preparationProgress.value = null;
    }
  }

  static Future<Set<String>>? _bundledKeys;
  static Future<ui.Image> _decodePreview(Uint8List encoded) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width != 256 || descriptor.height != 192) {
        throw const FormatException('Preview dimensions');
      }
      final codec = await descriptor.instantiateCodec();
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
  }

  static Future<ui.Image?> _readBundled(String key) async {
    try {
      final keys = await (_bundledKeys ??= (() async {
        final data = jsonDecode(await rootBundle
            .loadString('assets/original/thumbnails/index.json')) as Map;
        return Set<String>.from(data['keys'] as List);
      })());
      if (!keys.contains(key)) return null;
      final data =
          await rootBundle.load('assets/original/thumbnails/$key.webp');
      final image = await _decodePreview(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      bundledHits++;
      return image;
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image?> read(String key) async {
    final bundled = await _readBundled(key);
    if (bundled != null) return bundled;
    File? file;
    try {
      final dir = await directory();
      if (dir == null) return null;
      file = File('${dir.path}/$key.png');
      if (!await file.exists()) return null;
      final size = await file.length();
      if (size > 1 << 20 || size < 24) {
        await file.delete();
        return null;
      }
      final bytes = await file.readAsBytes();
      final header = ByteData.sublistView(bytes);
      if (header.getUint32(0) != 0x89504e47 ||
          header.getUint32(16) != 256 ||
          header.getUint32(20) != 192) {
        await file.delete();
        return null;
      }
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final image = (await codec.getNextFrame()).image;
        diskHits++;
        unawaited(file.setLastModified(DateTime.now()).catchError((_) => file));
        return image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
      return null;
    }
  }

  static Future<void> write(String key, Uint8List bytes) async {
    File? temporary;
    try {
      final dir = await directory();
      if (dir == null) return;
      final file = File('${dir.path}/$key.png');
      if (await file.exists()) return;
      temporary = File('${file.path}.$pid.tmp');
      await temporary.writeAsBytes(bytes, flush: false);
      await temporary.rename(file.path);
      if (++_writes % 32 == 1) unawaited(trim());
    } catch (_) {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
    }
  }

  static Future<void> trim() => _sweep ??= _trim().whenComplete(() {
        _sweep = null;
      });
  static Future<void> _trim() async {
    try {
      final dir = await directory();
      if (dir == null) return;
      final entries = <(File, FileStat)>[];
      var bytes = 0;
      await for (final entry in dir.list()) {
        if (entry is File &&
            (entry.path.endsWith('.png') || entry.path.endsWith('.webp'))) {
          final stat = await entry.stat();
          bytes += stat.size;
          entries.add((entry, stat));
        }
      }
      entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      var count = entries.length;
      for (final item in entries) {
        if (bytes <= maximumDiskBytes && count <= maximumFiles) break;
        try {
          await item.$1.delete();
          bytes -= item.$2.size;
          count--;
        } catch (_) {}
      }
    } catch (_) {}
  }
}
