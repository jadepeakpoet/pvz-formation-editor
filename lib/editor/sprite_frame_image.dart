import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'original_assets.dart';

/// Frame-sized appearance previews using Flutter's bounded image cache.
class SpriteFrameImage extends ImageProvider<SpriteFrameImage> {
  const SpriteFrameImage(this.path, {required this.scale});
  final String path;
  final double scale;

  @override
  Future<SpriteFrameImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    SpriteFrameImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    OriginalAssets.loadFrameImage(
      path,
      scale: scale,
    ).then((image) => ImageInfo(image: image)),
  );

  @override
  bool operator ==(Object other) =>
      other is SpriteFrameImage && other.path == path && other.scale == scale;
  @override
  int get hashCode => Object.hash(path, scale);
}
