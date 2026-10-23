import 'package:flutter/material.dart';
import '../domain/formation.dart';
import '../domain/website_codec.dart';
import 'original_assets.dart';

/// Seed selection overlay. The caller positions it within the main PVZ canvas.
/// Choosing cards only changes seed fields; ROCK closes this overlay.
class OriginalSeedChooser extends StatefulWidget {
  // Reserve the upper/side space for the original imitater dialog, so its
  // cards remain inside hit-test bounds while the main panel stays at y113.
  static const width = 655.0, height = 588.0;
  static const panelTop = 75.0;
  final Formation document;
  final ValueChanged<Formation> onChanged;
  final VoidCallback onClose;
  final bool readOnly;
  const OriginalSeedChooser(
      {super.key,
      required this.document,
      required this.onChanged,
      required this.onClose,
      this.readOnly = false});
  @override
  State<OriginalSeedChooser> createState() => _OriginalSeedChooserState();
}

class _OriginalSeedChooserState extends State<OriginalSeedChooser> {
  bool choosingImitater = false;
  int slot(String type, bool mimic) {
    final doc = widget.document;
    for (var i = 0; i < doc.seedSlots.length; i++) {
      if (doc.seedSlots[i] == type &&
          doc.imitaterSeedSlots.contains(i) == mimic) return i;
    }
    return -1;
  }

  void toggle(String type, bool mimic) {
    if (widget.readOnly) return;
    final doc = widget.document, index = slot(type, mimic);
    final cards = [...doc.seedSlots], gray = <int>{};
    if (index >= 0) {
      cards.removeAt(index);
      for (final i in doc.imitaterSeedSlots) {
        if (i != index) gray.add(i > index ? i - 1 : i);
      }
    } else {
      if (cards.length >= 10 || (mimic && doc.imitaterSeedSlots.isNotEmpty)) {
        return;
      }
      gray.addAll(doc.imitaterSeedSlots);
      if (mimic) gray.add(cards.length);
      cards.add(type);
    }
    widget.onChanged(doc.copy(seedSlots: cards, imitaterSeedSlots: gray));
    if (mimic && mounted) setState(() => choosingImitater = false);
  }

  Widget card(String type, {bool mimic = false}) {
    final selected = slot(type, mimic) >= 0;
    final path = OriginalAssets.cardPath(type, imitater: mimic);
    final normal = OriginalAssets.cardPath(type);
    Widget art;
    final image =
        OriginalAssets.image(path.replaceFirst('assets/original/', ''));
    if (image != null) {
      art = RawImage(
          image: image, fit: BoxFit.fill, filterQuality: FilterQuality.none);
    } else {
      final fallback = RawImage(
          image:
              OriginalAssets.image(normal.replaceFirst('assets/original/', '')),
          fit: BoxFit.fill,
          filterQuality: FilterQuality.none);
      art = mimic
          ? ColorFiltered(
              colorFilter: const ColorFilter.matrix([
                .2126,
                .7152,
                .0722,
                0,
                0,
                .2126,
                .7152,
                .0722,
                0,
                0,
                .2126,
                .7152,
                .0722,
                0,
                0,
                0,
                0,
                0,
                1,
                0
              ]),
              child: fallback)
          : fallback;
    }
    return Semantics(
        button: true,
        selected: selected,
        label: '${mimic ? '模仿者 · ' : ''}${ObjectSpec.byId(type).name}',
        child: Tooltip(
            message: '${mimic ? '模仿者 · ' : ''}${ObjectSpec.byId(type).name}',
            child: GestureDetector(
                key:
                    ValueKey('seed-choice-${mimic ? 'mimic' : 'normal'}-$type'),
                behavior: HitTestBehavior.opaque,
                onTap: widget.readOnly ? null : () => toggle(type, mimic),
                child: ColorFiltered(
                    colorFilter: selected
                        ? const ColorFilter.matrix([
                            .2126,
                            .7152,
                            .0722,
                            0,
                            0,
                            .2126,
                            .7152,
                            .0722,
                            0,
                            0,
                            .2126,
                            .7152,
                            .0722,
                            0,
                            0,
                            0,
                            0,
                            0,
                            1,
                            0
                          ])
                        : const ColorFilter.mode(
                            Colors.transparent, BlendMode.dst),
                    child: SizedBox(
                        width: image?.width.toDouble() ?? 50,
                        height: 70,
                        child: art)))));
  }

  Widget image(String path,
          {BoxFit fit = BoxFit.fill,
          ImageRepeat repeat = ImageRepeat.noRepeat,
          Alignment alignment = Alignment.center}) =>
      RawImage(
          image: OriginalAssets.image('image/$path'),
          fit: fit,
          repeat: repeat,
          alignment: alignment,
          filterQuality: FilterQuality.none);

  Widget grid({required bool mimic}) => Wrap(
          key: ValueKey(mimic ? 'seed-mimic-grid' : 'seed-normal-grid'),
          spacing: mimic ? 1 : 2,
          children: [
            for (final type in WebsiteCodec.plantIds.take(mimic ? 40 : 48))
              card(type, mimic: mimic),
          ]);

  Widget imitaterDialog() => Positioned(
      left: 148,
      top: 0,
      width: 505,
      height: 580,
      child: Stack(children: [
        const Positioned(
            left: 107,
            top: 142,
            width: 278,
            height: 324,
            child: ColoredBox(color: Color(0xff212431))),
        Positioned(
            left: 0,
            top: 45,
            width: 107,
            height: 97,
            child: image('dialog_topleft.png')),
        Positioned(
            left: 107,
            top: 45,
            width: 278,
            height: 97,
            child: image('dialog_topmiddle.png',
                fit: BoxFit.none, repeat: ImageRepeat.repeatX)),
        Positioned(
            left: 385,
            top: 45,
            width: 120,
            height: 97,
            child: image('dialog_topright.png')),
        Positioned(
            left: 0,
            top: 142,
            width: 107,
            height: 324,
            child: image('dialog_centerleft.png',
                fit: BoxFit.none,
                repeat: ImageRepeat.repeatY,
                alignment: Alignment.topRight)),
        Positioned(
            left: 385,
            top: 142,
            width: 120,
            height: 324,
            child: image('dialog_centerright.png',
                fit: BoxFit.none,
                repeat: ImageRepeat.repeatY,
                alignment: Alignment.topLeft)),
        Positioned(
            left: 0,
            top: 466,
            width: 107,
            height: 114,
            child: image('dialog_bottomleft.png',
                fit: BoxFit.none, alignment: Alignment.topRight)),
        Positioned(
            left: 107,
            top: 466,
            width: 278,
            height: 114,
            child: image('dialog_bottommiddle.png',
                fit: BoxFit.none,
                repeat: ImageRepeat.repeatX,
                alignment: Alignment.topLeft)),
        Positioned(
            left: 385,
            top: 466,
            width: 120,
            height: 114,
            child: image('dialog_bottomright.png')),
        Positioned(
            left: 152.5,
            top: 0,
            width: 187,
            height: 64,
            child: image('dialog_header.png')),
        const Positioned(
            left: 45,
            top: 80,
            width: 400,
            height: 30,
            child: Text('Choose a Seed to Copy',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Color(0xffd7a41b),
                    fontSize: 26,
                    height: 1,
                    fontFamily: 'Continuum Bold',
                    fontWeight: FontWeight.bold))),
        Positioned(
            left: 45,
            top: 116,
            width: 417.5,
            height: 350,
            child: grid(mimic: true)),
        Positioned(
            right: 8,
            top: 48,
            width: 28,
            height: 28,
            child: IconButton(
                key: const ValueKey('seed-mimic-back'),
                tooltip: '返回',
                padding: EdgeInsets.zero,
                iconSize: 18,
                color: const Color(0xffd7a41b),
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => choosingImitater = false))),
      ]));

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final canImitate = !widget.readOnly &&
        doc.seedSlots.length < 10 &&
        doc.imitaterSeedSlots.isEmpty;
    return SizedBox(
        width: OriginalSeedChooser.width,
        height: OriginalSeedChooser.height,
        child: Stack(children: [
          Positioned(
              left: 0,
              top: OriginalSeedChooser.panelTop,
              width: 465,
              height: 513,
              child: image('SeedChooser_Background.png')),
          const Positioned(
              left: 0,
              top: OriginalSeedChooser.panelTop,
              width: 465,
              height: 36,
              child: Text('CHOOSE YOUR PLANTS!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xffd7a41b),
                      fontSize: 20,
                      height: 1.6,
                      fontWeight: FontWeight.w400))),
          Positioned(
              left: 25.25,
              top: OriginalSeedChooser.panelTop + 36,
              width: 416.5,
              height: 420,
              child: grid(mimic: false)),
          Positioned(
              left: 157.5,
              top: OriginalSeedChooser.panelTop + 462,
              width: 150,
              height: 35,
              child: ElevatedButton(
                  key: const ValueKey('seed-lets-rock'),
                  onPressed: widget.onClose,
                  style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: const Color(0xff8f431b),
                      foregroundColor: const Color(0xffce9b36),
                      shape: const RoundedRectangleBorder(),
                      side:
                          const BorderSide(color: Color(0xffb5592e), width: 2)),
                  child: const Text("Let's ROCK!",
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)))),
          Positioned(
              left: 458,
              top: OriginalSeedChooser.panelTop + 415,
              width: 66,
              height: 93,
              child: image('SeedChooser_ImitaterAddOn.png')),
          Positioned(
              left: 463,
              top: OriginalSeedChooser.panelTop + 427,
              width: 50,
              height: 70,
              child: Tooltip(
                  message: doc.imitaterSeedSlots.isNotEmpty
                      ? '已选择一张模仿者，请点击顶部卡片退回'
                      : '模仿者',
                  child: GestureDetector(
                      key: const ValueKey('seed-imitater-open'),
                      behavior: HitTestBehavior.opaque,
                      onTap: canImitate
                          ? () => setState(() => choosingImitater = true)
                          : null,
                      child: image('Card/Imitater.png')))),
          if (choosingImitater) imitaterDialog(),
        ]));
  }
}
