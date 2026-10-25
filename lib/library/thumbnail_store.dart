import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import '../domain/formation.dart';
import '../domain/zombie_layout.dart';

/// Versioned thumbnail files. Cache failure never changes or blocks archives.
class ThumbnailStore {
  /// Disk caching is opt-in for resource-strategy comparisons.
  static const diskCacheEnabled = bool.fromEnvironment(
      'PVZ_THUMBNAIL_DISK_CACHE', defaultValue: false);
  static Directory? directoryOverride;
  static Future<Directory?>? _root;
  static int diskHits = 0,
      generated = 0,
      skipped = 0,
      memoryHits = 0;
  static int _writes = 0;
  static Future<void>? _sweep;
  static const rendererVersion = 3;
  static const maximumDiskBytes = 64 << 20;
  static const maximumFiles = 2048;
  static String key(Formation document) => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'renderer': rendererVersion,
            'size': [256, 192],
            if (ZombieLayout.contains(document)) 'zombieAnchors': 1,
            'map': document.mapId,
            'objects': [
              for (final piece in document.pieces)
                Map<String, dynamic>.from(piece.toJson())
                  ..remove('id')
                  // Frame already captures the visible sleep/awake appearance.
                  ..remove('asleep'),
            ],
          }),
        ),
      )
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

  static Future<ui.Image?> read(String key) async {
    if (!diskCacheEnabled) return null;
    File? file;
    try {
      final dir = await directory();
      if (dir == null) return null;
      file = File('${dir.path}/$key.webp');
      if (!await file.exists()) file = File('${dir.path}/$key.png');
      if (!await file.exists()) return null;
      final size = await file.length();
      if (size > 1 << 20 || size < 24) {
        await file.delete();
        return null;
      }
      final bytes = await file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width != 256 || descriptor.height != 192) {
          await file.delete();
          return null;
        }
        final codec = await descriptor.instantiateCodec();
        try {
          final image = (await codec.getNextFrame()).image;
          diskHits++;
          unawaited(file.setLastModified(DateTime.now()).catchError((_) => file));
          return image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
        buffer.dispose();
      }
    } catch (error) {
      debugPrint('Thumbnail cache read failed: $error');
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
      return null;
    }
  }

  static Future<void> write(String key, Uint8List bytes, {String extension = 'webp'}) async {
    if (!diskCacheEnabled) return;
    if (extension != 'webp' && extension != 'png') throw ArgumentError.value(extension);
    File? temporary;
    try {
      final dir = await directory();
      if (dir == null) return;
      final file = File('${dir.path}/$key.$extension');
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
