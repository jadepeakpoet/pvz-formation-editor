import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A mounted widget owns a handle independently of the evictable image cache.
class ResourceImage extends StatefulWidget {
  const ResourceImage(
      {super.key,
      this.image,
      this.fit,
      this.alignment = Alignment.center,
      this.repeat = ImageRepeat.noRepeat,
      this.filterQuality = FilterQuality.low});
  final ui.Image? image;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageRepeat repeat;
  final FilterQuality filterQuality;
  @override
  State<ResourceImage> createState() => _ResourceImageState();
}

class _ResourceImageState extends State<ResourceImage> {
  ui.Image? _image;
  @override
  void initState() {
    super.initState();
    _image = widget.image?.clone();
  }

  @override
  void didUpdateWidget(ResourceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.image, widget.image)) {
      _image?.dispose();
      _image = widget.image?.clone();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawImage(
      image: _image,
      fit: widget.fit,
      alignment: widget.alignment,
      repeat: widget.repeat,
      filterQuality: widget.filterQuality);
}
