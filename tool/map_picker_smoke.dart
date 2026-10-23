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
  var completed = false;
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
                          completed = false;
                          pending = showMapPickerDialog(context,
                              currentMapId: 'pool', readOnly: readOnly);
                          pending!.then((_) => completed = true);
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

  Checkbox keepCheckbox() =>
      find((w) => w.key == const ValueKey('map-picker-keep-plants'))
          .single
          .widget as Checkbox;
  Future<void> hover(String key) async {
    final element = find((w) => w.key == ValueKey(key)).single;
    await Scrollable.ensureVisible(element, duration: Duration.zero);
    await settle();
    final box = element.renderObject as RenderBox;
    final position = box.localToGlobal(box.size.center(Offset.zero));
    GestureBinding.instance.handlePointerEvent(PointerAddedEvent(
        pointer: 100, kind: ui.PointerDeviceKind.mouse, position: position));
    GestureBinding.instance.handlePointerEvent(PointerHoverEvent(
        pointer: 100, kind: ui.PointerDeviceKind.mouse, position: position));
    await settle();
    GestureBinding.instance.handlePointerEvent(PointerRemovedEvent(
        pointer: 100, kind: ui.PointerDeviceKind.mouse, position: position));
    await settle();
  }

  mount();
  await settle();
  await tap('open');
  check(previewMap() == 'pool', 'Current map must be preselected');
  check(keepCheckbox().value == false, 'Keep plants must default unchecked');
  final cancelBox = find((w) => w.key == const ValueKey('map-picker-cancel'))
      .single
      .renderObject as RenderBox;
  final previewBox = find((w) => w.key == const ValueKey('map-picker-preview'))
      .single
      .renderObject as RenderBox;
  check(
      cancelBox.localToGlobal(Offset.zero).dy <
          previewBox.localToGlobal(Offset.zero).dy,
      'Cancel must be in top header');
  await hover('map-picker-map-roof');
  check(previewMap() == 'roof' && !completed,
      'Hover must preview without applying');
  await screenshot('wide');
  await tap('map-picker-cancel');
  check(await pending == null, 'Cancel must not return map change');
  await tap('open');
  await tap('map-picker-map-day');
  final reset = await pending;
  check(reset?.mapId == 'day' && reset?.keepPlants == false && completed,
      'Click must immediately select map with clear-plants default');
  await settle();
  check(find((w) => w.key == const ValueKey('map-picker-dialog')).isEmpty,
      'Map click must close dialog without second confirmation');
  await tap('open');
  await tap('map-picker-keep-plants');
  check(keepCheckbox().value == true, 'Keep plants toggle failed');
  await tap('map-picker-map-roof');
  final keep = await pending;
  check(keep?.mapId == 'roof' && keep?.keepPlants == true,
      'Keep checkbox must travel in immediate result');
  await tap('open');
  check(keepCheckbox().value == false,
      'Keep checkbox must reset on each opening');
  await tap('map-picker-cancel');
  readOnly = true;
  mount();
  await settle();
  await tap('open');
  check(keepCheckbox().onChanged == null && keepCheckbox().value == false,
      'Readonly keep checkbox must be disabled');
  await tap('map-picker-map-night');
  check(
      previewMap() == 'night' &&
          !completed &&
          find((w) => w.key == const ValueKey('map-picker-dialog')).isNotEmpty,
      'Readonly click must only preview without applying');
  await tap('map-picker-cancel');
  check(await pending == null, 'Readonly cancellation result must be null');
  binding.viewport = const Size(360, 640);
  binding.handleMetricsChanged();
  readOnly = false;
  mount();
  await settle();
  await tap('open');
  await hover('map-picker-map-allWater');
  check(previewMap() == 'allWater' && !completed,
      'Narrow scroll hover preview failed');
  await screenshot('narrow');
  await tap('map-picker-map-allWater');
  final narrow = await pending;
  check(narrow?.mapId == 'allWater' && narrow?.keepPlants == false,
      'Narrow immediate result failed');
  check(errors.isEmpty, errors.map((e) => e.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS immediate map choice, unchecked default, keep checkbox, hover preview, top cancel, readonly and 360px layout');
  runApp(const SizedBox.shrink());
  await settle();
  exit(0);
}
