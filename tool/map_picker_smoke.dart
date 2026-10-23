import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/map_picker_dialog.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';

class Binding extends WidgetsFlutterBinding {
  Size viewport = const Size(1000, 760);
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(size: viewport, devicePixelRatio: 1);
}

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

List<Element> find(bool Function(Widget) predicate) {
  final result = <Element>[];
  void visit(Element element) {
    if (predicate(element.widget)) result.add(element);
    element.visitChildren(visit);
  }

  visit(WidgetsBinding.instance.rootElement!);
  return result;
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 160));
Future<void> tap(String key) async {
  final element = find((w) => w.key == ValueKey(key)).single;
  await Scrollable.ensureVisible(element, duration: Duration.zero);
  await settle();
  final box = element.renderObject as RenderBox;
  final position = box.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: position, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 1, position: position));
  await settle();
}

Future<void> main() async {
  final binding = Binding();
  await OriginalAssets.ensureLoaded();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  final boundary = GlobalKey();
  Future<MapPickerChoice?>? pending;
  var readOnly = false;
  void mount() {
    runApp(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                colorScheme:
                    ColorScheme.fromSeed(seedColor: const Color(0xff456b4e))),
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        key: const ValueKey('open'),
                        onPressed: () {
                          pending = showMapPickerDialog(context,
                              currentMapId: 'pool', readOnly: readOnly);
                        },
                        child: const Text('Open')))))));
  }

  String previewMap() =>
      ((find((w) => w.key == const ValueKey('map-picker-preview')).single.widget
                  as CustomPaint)
              .painter as BoardPainter)
          .document
          .mapId;
  Future<void> screenshot(String name) async {
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/pvz-map-picker-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  mount();
  await settle();
  await tap('open');
  check(previewMap() == 'pool', 'Current map must be preselected');
  await tap('map-picker-map-roof');
  check(previewMap() == 'roof',
      'Selecting map must update actual painter preview');
  await screenshot('wide');
  await tap('map-picker-cancel');
  check(await pending == null, 'Cancel must not return map change');
  await tap('open');
  await tap('map-picker-map-day');
  await tap('map-picker-keep');
  final keep = await pending;
  check(keep?.mapId == 'day' && keep?.keepPlants == true,
      'Keep action result incorrect');
  await tap('open');
  await tap('map-picker-map-roof');
  await tap('map-picker-reset');
  final reset = await pending;
  check(reset?.mapId == 'roof' && reset?.keepPlants == false,
      'Reset action result incorrect');
  readOnly = true;
  mount();
  await settle();
  await tap('open');
  check(
      (find((w) => w.key == const ValueKey('map-picker-keep')).single.widget
                  as FilledButton)
              .onPressed ==
          null,
      'Readonly keep enabled');
  check(
      (find((w) => w.key == const ValueKey('map-picker-reset')).single.widget
                  as OutlinedButton)
              .onPressed ==
          null,
      'Readonly reset enabled');
  await tap('map-picker-map-night');
  check(previewMap() == 'night', 'Readonly must still allow previews');
  await tap('map-picker-cancel');
  binding.viewport = const Size(360, 640);
  binding.handleMetricsChanged();
  readOnly = false;
  mount();
  await settle();
  await tap('open');
  await tap('map-picker-map-allWater');
  check(previewMap() == 'allWater', 'Narrow scroll map selection failed');
  await screenshot('narrow');
  await tap('map-picker-cancel');
  check(errors.isEmpty, errors.map((e) => e.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS map picker current map, previews, cancel, keep/reset, readonly and 360px layout');
  runApp(const SizedBox.shrink());
  await settle();
  exit(0);
}
