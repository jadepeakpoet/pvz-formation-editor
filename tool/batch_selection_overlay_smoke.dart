import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/batch_selection_overlay.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';

class Binding extends WidgetsFlutterBinding {
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      const ViewConfiguration(size: Size(800, 600), devicePixelRatio: 1);
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
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
    Future<void>.delayed(const Duration(milliseconds: 120));

Future<void> tapAt(Offset position) async {
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: position, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 1, position: position));
  await settle();
}

Future<void> tap(String key) async {
  final box =
      find((w) => w.key == ValueKey(key)).single.renderObject as RenderBox;
  await tapAt(box.localToGlobal(box.size.center(Offset.zero)));
}

Future<void> main() async {
  Binding();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  var document = Formation(mapId: 'pool');
  final before = document.fingerprint;
  var rows = <int>{}, columns = <int>{};
  var boardTaps = 0;
  late StateSetter update;
  runApp(
      MaterialApp(home: Material(child: StatefulBuilder(builder: (_, setState) {
    update = setState;
    return Stack(children: [
      Positioned.fill(
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => boardTaps++,
              child: const ColoredBox(color: Colors.black))),
      Positioned.fill(
          child: BatchSelectionOverlay(
              document: document,
              selectedRows: rows,
              selectedColumns: columns,
              onRowsChanged: (value) => update(() => rows = value),
              onColumnsChanged: (value) => update(() => columns = value))),
    ]);
  }))));
  await settle();
  check(find((w) => w is Checkbox).length == 17,
      'Pool should expose six row, nine column and two all selectors');
  final target = find((w) => w.key == const ValueKey('batch-row-1-target'))
      .single
      .renderObject as RenderBox;
  check(target.size == const Size(44, 44),
      'Row checkbox hit area should be 44px');
  final visual = find((w) => w.key == const ValueKey('batch-row-1'))
      .single
      .renderObject as RenderBox;
  final visualSize =
      visual.localToGlobal(visual.size.bottomRight(Offset.zero)) -
          visual.localToGlobal(Offset.zero);
  check((visualSize.dx - 39).abs() < .01 && (visualSize.dy - 39).abs() < .01,
      'Checkbox should match the source 3x native size');
  await tapAt(target.localToGlobal(const Offset(2, 22)));
  check(rows.contains(1), 'Click near the hit-area edge should select the row');
  await tap('batch-row-1');
  check(rows.isEmpty, 'Checkbox should toggle once per click');
  await tap('batch-row-1');
  check(rows.length == 1 && rows.contains(1) && columns.isEmpty,
      'Row selector changed the wrong axis');
  await tap('batch-col-2');
  check(columns.length == 1 && columns.contains(2) && rows.contains(1),
      'Column selector must retain independent row choice');
  await tap('batch-row-all');
  check(rows.length == 6 && columns.length == 1,
      'All rows must leave column selection unchanged');
  await tap('batch-row-all');
  check(rows.isEmpty && columns.length == 1, 'All rows failed to clear');
  await tap('batch-col-all');
  check(columns.length == 9 && rows.isEmpty, 'All columns failed to select');
  await tap('batch-col-all');
  check(columns.isEmpty, 'All columns failed to clear');
  await tapAt(BoardGeometry(document).cellCenter(2, 4));
  check(boardTaps == 1 && rows.isEmpty && columns.isEmpty,
      'Unselected canvas must pass pointer through without changing axes');
  check(document.fingerprint == before, 'Selection mutated formation');

  // Only row/column intersections are outlined, without a white fill.
  final geometry = BoardGeometry(document);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.black, BlendMode.src);
  BatchSelectionMaskPainter(
      document: document,
      selectedRows: {1},
      selectedColumns: {2}).paint(canvas, geometry.size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(800, 600);
  final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  List<int> pixel(Offset point) {
    final offset = (point.dy.floor() * 800 + point.dx.floor()) * 4;
    return [for (var i = 0; i < 3; i++) rgba!.getUint8(offset + i)];
  }

  bool black(Offset point) => pixel(point).every((c) => c == 0);
  final edge = geometry.cellCenter(1, 2) - Offset(0, geometry.cellHeight / 2);
  final color = pixel(edge);
  check(color[0] == 255 && color[1] == 213 && color[2] == 79,
      'Selected cell boundary should be yellow');
  check(
      black(geometry.cellCenter(1, 2)) &&
          black(geometry.cellCenter(1, 4)) &&
          black(geometry.cellCenter(3, 2)),
      'Selection should not cover plant interiors or unselected axes');
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('/tmp/pvz-batch-selection-mask.png')
      .writeAsBytes(png!.buffer.asUint8List());
  image.dispose();
  picture.dispose();

  for (final mapId in ['day', 'roof', 'day6', 'roof6']) {
    update(() {
      document = Formation(mapId: mapId);
      rows = {};
      columns = {};
    });
    await settle();
    await tap('batch-row-all');
    await tap('batch-col-all');
    check(rows.length == document.map.rows && columns.length == 9,
        'Axis count/geometry failed on $mapId');
  }
  check(errors.isEmpty, errors.map((e) => e.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS row/column toggles, independent all selectors, pointer pass-through, immutable document, 39px controls with 44px hit targets, yellow intersection outlines and five/six-row/roof geometry');
  runApp(const SizedBox.shrink());
  await settle();
  exit(0);
}
