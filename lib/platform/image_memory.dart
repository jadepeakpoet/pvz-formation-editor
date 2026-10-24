import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Flutter's decoded-image cache and Skia's GPU resource cache are independent.
class ImageMemory {
  @visibleForTesting
  static bool configureGpuCache = true;
  static Future<void> configure({bool secondary = false}) async {
    PaintingBinding.instance.imageCache
      ..maximumSizeBytes = 16 << 20
      ..maximumSize = 120;
    if (!configureGpuCache) return;
    try {
      await SystemChannels.skia.invokeMethod<void>(
          'Skia.setResourceCacheMaxBytes', (secondary ? 12 : 24) << 20);
    } on MissingPluginException {
      // Embedders without Skia use their own renderer budget.
    } on PlatformException catch (error) {
      debugPrint('Renderer cache budget: $error');
    }
  }
}
