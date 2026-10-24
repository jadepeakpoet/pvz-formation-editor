import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../domain/formation.dart';
import '../editor/board_painter.dart';

/// List cells retain a small raster preview instead of painting full sprite
/// sheets on every frame. Jobs leaving the viewport are skipped before decode.
class FormationThumbnail extends StatefulWidget {
  const FormationThumbnail({super.key, required this.document});
  final Formation document;
  static final _cache = <String, Uint8List>{};
  static final _pending = <String, Future<Uint8List?>>{};
  static Future<void> _tail = Future.value();
  static int _bytes = 0;
  static final _interests = <String, int>{};
  static const maximumBytes = 8 << 20;
  static int get cachedBytes => _bytes;
  static void clearCache() {
    _cache.clear();
    _bytes = 0;
  }

  @override
  State<FormationThumbnail> createState() => _FormationThumbnailState();
}

class _FormationThumbnailState extends State<FormationThumbnail> {
  Future<Uint8List?>? image;
  String? _key;
  void _releaseInterest() {
    final key = _key;
    if (key == null) return;
    final count = (FormationThumbnail._interests[key] ?? 1) - 1;
    if (count == 0) {
      FormationThumbnail._interests.remove(key);
    } else {
      FormationThumbnail._interests[key] = count;
    }
    _key = null;
  }

  @override
  void dispose() {
    _releaseInterest();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(FormationThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.fingerprint != widget.document.fingerprint) _load();
  }

  void _load() {
    final document = widget.document;
    final key = document.fingerprint;
    _releaseInterest();
    _key = key;
    FormationThumbnail._interests
        .update(key, (count) => count + 1, ifAbsent: () => 1);
    final cached = FormationThumbnail._cache.remove(key);
    if (cached != null) {
      FormationThumbnail._cache[key] = cached;
      image = Future.value(cached);
      return;
    }
    image = FormationThumbnail._pending.putIfAbsent(key, () {
      final job = FormationThumbnail._tail.then<Uint8List?>((_) async {
        if (!FormationThumbnail._interests.containsKey(key)) return null;
        final bytes = await exportPng(document, multiplier: .32);
        FormationThumbnail._cache[key] = bytes;
        FormationThumbnail._bytes += bytes.length;
        while (FormationThumbnail._bytes > FormationThumbnail.maximumBytes) {
          final oldest = FormationThumbnail._cache.keys.first;
          FormationThumbnail._bytes -=
              FormationThumbnail._cache.remove(oldest)!.length;
        }
        return bytes;
      });
      FormationThumbnail._tail =
          job.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      return job.whenComplete(() => FormationThumbnail._pending.remove(key));
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
      future: image,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(child: Icon(Icons.grass, color: Colors.grey));
        }
        return Image.memory(bytes,
            fit: BoxFit.contain,
            cacheWidth: 256,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true);
      });
}
