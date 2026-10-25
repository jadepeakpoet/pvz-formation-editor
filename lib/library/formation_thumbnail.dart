import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../domain/formation.dart';
import '../editor/board_painter.dart';
import '../editor/image_resources.dart';
import '../editor/resource_image.dart';
import 'thumbnail_store.dart';

/// Visible cells pin their image. Cold entries are evictable; all previews also
/// live on disk, so scrolling back does not render the formation again.
class FormationThumbnail extends StatefulWidget {
  const FormationThumbnail(
      {super.key, this.document, this.cacheKey, this.documentLoader})
      : assert(document != null || cacheKey != null);
  final Formation? document;
  final String? cacheKey;
  final Formation Function()? documentLoader;
  static final images = ImageResources(
      maximumBytes: 4 << 20,
      evictionDelay: Duration.zero,
      minimumAge: Duration.zero);
  static final _pending = <String, Future<ui.Image?>>{};
  static Future<void> _tail = Future.value();
  static final _interests = <String, int>{};
  static int get cachedBytes => images.bytes;
  static void clearCache() =>
      images.trim(minimumAge: Duration.zero, targetBytes: 0);
  @override
  State<FormationThumbnail> createState() => _FormationThumbnailState();
}

class _FormationThumbnailState extends State<FormationThumbnail> {
  Future<ui.Image?>? image;
  String? _key;
  bool _tickerEnabled = true;
  void _releaseInterest() {
    final key = _key;
    if (key == null) return;
    final n = (FormationThumbnail._interests[key] ?? 1) - 1;
    if (n <= 0) {
      FormationThumbnail._interests.remove(key);
    } else {
      FormationThumbnail._interests[key] = n;
    }
    FormationThumbnail.images.unpin(key);
    _key = null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.of(context);
    if (enabled != _tickerEnabled) {
      _tickerEnabled = enabled;
      if (enabled) {
        _load();
      } else {
        _releaseInterest();
        image = null;
      }
    }
  }

  @override
  void didUpdateWidget(FormationThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tickerEnabled &&
        (oldWidget.cacheKey != widget.cacheKey ||
            !identical(oldWidget.document, widget.document))) {
      if ((widget.cacheKey ?? ThumbnailStore.key(widget.document!)) != _key) {
        _load();
      }
    }
  }

  @override
  void dispose() {
    _releaseInterest();
    super.dispose();
  }

  void _load() {
    final document = widget.document;
    final loader = widget.documentLoader;
    final key = widget.cacheKey ?? ThumbnailStore.key(document!);
    _releaseInterest();
    _key = key;
    FormationThumbnail.images.pin(key);
    FormationThumbnail._interests.update(key, (n) => n + 1, ifAbsent: () => 1);
    final cached = FormationThumbnail.images[key];
    if (cached != null) {
      ThumbnailStore.memoryHits++;
      image = Future.value(cached);
      return;
    }
    image = FormationThumbnail._pending.putIfAbsent(key, () {
      bool needed() => FormationThumbnail._interests.containsKey(key);
      final job = FormationThumbnail._tail.then<ui.Image?>((_) async {
        if (!needed()) {
          ThumbnailStore.skipped++;
          return null;
        }
        var result = await ThumbnailStore.read(key);
        if (!needed()) {
          result?.dispose();
          ThumbnailStore.skipped++;
          return null;
        }
        if (result == null) {
          final source = document ?? loader?.call();
          if (source == null) throw StateError('Preview document unavailable');
          result = await renderThumbnail(source, isNeeded: needed);
          if (result == null || !needed()) {
            result?.dispose();
            ThumbnailStore.skipped++;
            return null;
          }
          ThumbnailStore.generated++;
          FormationThumbnail.images[key] = result;
          // Display immediately; encoding/writing never delays the ready Future.
          unawaited(_persist(key, result.clone()));
        } else {
          FormationThumbnail.images[key] = result;
        }
        return result;
      });
      FormationThumbnail._tail =
          job.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      return job.whenComplete(() {
        FormationThumbnail._pending.remove(key);
      });
    });
  }

  static Future<void> _persist(String key, ui.Image image) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data != null) {
        await ThumbnailStore.write(key,
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }
    } catch (_) {
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => !_tickerEnabled
      ? const SizedBox.shrink()
      : FutureBuilder<ui.Image?>(
          key: ValueKey(_key),
          future: image,
          builder: (context, snapshot) {
            final value = snapshot.data;
            if (value == null) {
              return const Center(child: Icon(Icons.grass, color: Colors.grey));
            }
            return ResourceImage(
                image: value,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.low);
          });
}
