import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/map_picker_dialog.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';

class Binding extends WidgetsFlutterBinding {
  Size viewport = const Size(1000, 760);
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(logicalConstraints: BoxConstraints.tight(viewport), physicalConstraints: BoxConstraints.tight(viewport), devicePixelRatio: 1);
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
  var useDefaults = false;
  final keepPlants = ValueNotifier<bool>(false);
  var keepChanges = 0;
  var completed = false;
  final source = Formation(mapId: 'pool', sunValue: 1234, pieces: [
    Piece(
        id: 'keep-pea',
        type: 'pea',
        row: 1,
        col: 1,
        layer: 10,
        effects: {'模仿者'}),
    Piece(id: 'sixth-row', type: 'pumpkin', row: 5, col: 8, layer: 20),
  ]);
  final before = jsonEncode(source.toJson());
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
                          pending = useDefaults ? showMapPickerDialog(context,
                              currentMapId: source.mapId, currentFormation: source) : showMapPickerDialog(context,
                              currentMapId: source.mapId,
                              currentFormation: source,
                              keepPlants: keepPlants.value,
                              keepPlantsListenable: keepPlants,
                              onKeepPlantsChanged: (value) {
                            keepChanges++;
                            keepPlants.value = value;
                          }, readOnly: readOnly);
                          pending!.then((_) => completed = true);
                        },
                        child: const Text('Open')))))));
  }

  Formation previewDocument() =>
      ((find((w) => w.key == const ValueKey('map-picker-preview')).single.widget
                  as CustomPaint)
              .painter as BoardPainter)
          .document;
  String previewMap() => previewDocument().mapId;
  void checkAllPreviews(bool retained) {
    final painters = find((w) => w is CustomPaint && w.painter is BoardPainter)
        .map((element) =>
            (element.widget as CustomPaint).painter as BoardPainter);
    check(painters.length > 10, 'Map thumbnail previews not found');
    for (final painter in painters) {
      final expected = retained
          ? source.pieces
              .where((piece) => source.fits(piece, painter.document.map))
              .map((piece) => piece.id)
              .toList()
          : <String>[];
      check(
          jsonEncode(
                  painter.document.pieces.map((piece) => piece.id).toList()) ==
              jsonEncode(expected),
          'Preview retained wrong pieces on ${painter.document.mapId}');
      check(painter.document.display.isEmpty && !painter.helpers,
          'Preview must not include editor helper overlays');
    }
    check(jsonEncode(source.toJson()) == before,
        'Preview mutated source formation');
  }

  Future<void> screenshot(String name) async {
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${Directory.systemTemp.path}/pvz-map-picker-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

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
  Checkbox keepCheckbox() =>
      find((w) => w.key == const ValueKey('map-picker-keep-plants'))
          .single
          .widget as Checkbox;
  check(keepCheckbox().value == false && keepCheckbox().onChanged != null,
      'Keep checkbox must reflect caller false and allow edits');
  checkAllPreviews(false);
  final cancelBox = find((w) => w.key == const ValueKey('map-picker-cancel'))
      .single
      .renderObject as RenderBox;
  final previewBox = find((w) => w.key == const ValueKey('map-picker-preview'))
      .single
      .renderObject as RenderBox;
  final mapBox = find((w) => w.key == const ValueKey('map-picker-map-pool'))
      .single
      .renderObject as RenderBox;
  check(
      cancelBox.localToGlobal(Offset.zero).dy <
          previewBox.localToGlobal(Offset.zero).dy,
      'Cancel must be in top header');
  check(
      previewBox.localToGlobal(Offset.zero).dx <
          mapBox.localToGlobal(Offset.zero).dx,
      'Wide preview must be to left of map list');
  await hover('map-picker-map-roof');
  check(previewMap() == 'roof' && !completed,
      'Hover must preview without applying');
  checkAllPreviews(false);
  await screenshot('wide');
  await tap('map-picker-keep-plants');
  check(keepPlants.value && keepChanges == 1 && keepCheckbox().value == true,
      'Internal checkbox must synchronize external state');
  checkAllPreviews(true);
  check(previewMap() == 'roof',
      'Keep synchronization must preserve selected preview');
  keepPlants.value = false;
  await settle();
  check(keepCheckbox().value == false && previewMap() == 'roof',
      'External notifier update must synchronize checkbox without resetting preview');
  checkAllPreviews(false);
  await tap('map-picker-keep-plants');
  check(keepPlants.value && keepChanges == 2, 'Second internal toggle failed');
  await tap('map-picker-cancel');
  check(await pending == null && keepPlants.value,
      'Cancel must not apply map or roll back synchronized option');
  await tap('open');
  check(keepCheckbox().value == true,
      'Reopening must inherit synchronized option');
  await tap('map-picker-cancel');
  keepPlants.value = false;
  await tap('open');
  await tap('map-picker-map-day');
  final reset = await pending;
  check(reset?.mapId == 'day' && reset?.keepPlants == false && completed,
      'Click must immediately select map with caller default false');
  await settle();
  check(find((w) => w.key == const ValueKey('map-picker-dialog')).isEmpty,
      'Map click must close dialog without second confirmation');
  keepPlants.value = true;
  mount();
  await settle();
  await tap('open');
  check(previewDocument().pieces.length == 2,
      'Retained current map preview must include existing plants');
  checkAllPreviews(true);
  await hover('map-picker-map-roof');
  check(
      previewDocument().pieces.single.id == 'keep-pea' &&
          previewDocument().pieces.single.effects.contains('模仿者'),
      'Roof preview must filter sixth row and retain plant appearance');
  checkAllPreviews(true);
  await screenshot('retained');
  keepPlants.value = false;
  await settle();
  checkAllPreviews(false);
  await tap('map-picker-keep-plants');
  check(keepPlants.value && keepCheckbox().value == true,
      'Internal toggle before apply must sync');
  await tap('map-picker-map-roof');
  final keep = await pending;
  check(keep?.mapId == 'roof' && keep?.keepPlants == true,
      'Caller keep choice must travel in immediate result');
  readOnly = true;
  mount();
  await settle();
  await tap('open');
  check(keepCheckbox().onChanged == null && keepCheckbox().value == true,
      'Readonly keep checkbox must reflect synchronized value and be disabled');
  await tap('map-picker-keep-plants');
  check(keepPlants.value, 'Readonly checkbox must not mutate external option');
  await tap('map-picker-map-night');
  check(
      previewMap() == 'night' &&
          !completed &&
          find((w) => w.key == const ValueKey('map-picker-dialog')).isNotEmpty,
      'Readonly click must only preview without applying');
  checkAllPreviews(true);
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
  check(previewDocument().pieces.length == 2,
      'Six-row narrow preview must retain both existing plants');
  await screenshot('narrow');
  await tap('map-picker-map-allWater');
  final narrow = await pending;
  check(narrow?.mapId == 'allWater' && narrow?.keepPlants == true,
      'Narrow immediate result failed');
  check(jsonEncode(source.toJson()) == before,
      'Dialog flow must not mutate supplied formation');
  useDefaults = true;
  await tap('open');
  check(keepCheckbox().value == true && previewDocument().pieces.length == 2,
      'Default map dialog must retain plants without explicit options');
  await tap('map-picker-cancel');
  check(await pending == null, 'Cancel the default map dialog');
  check(errors.isEmpty, errors.map((e) => e.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS bidirectional keep synchronization, cancel preserves option, live retained previews, bounds filtering, source unchanged, immediate choice, readonly and 360px layout');
  runApp(const SizedBox.shrink());
  await settle();
  keepPlants.dispose();
  exit(0);
}
