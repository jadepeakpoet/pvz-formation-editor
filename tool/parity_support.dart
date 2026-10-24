// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/editor/classic_window.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';

class ParityBinding extends WidgetsFlutterBinding {
  static final handlers = <String, Future<dynamic> Function(MethodCall)>{};
  @override
  BinaryMessenger createBinaryMessenger() =>
      ParityMessenger(super.createBinaryMessenger());
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(logicalConstraints: BoxConstraints.tight(Size(1240, 800)), physicalConstraints: BoxConstraints.tight(Size(1240, 800)), devicePixelRatio: 1);
}

class ParityHarness {
  final GlobalKey boundary;
  final Directory output;
  final cases = <Map<String, dynamic>>[];
  final declaredCases = <String, String>{};
  final errors = <FlutterErrorDetails>[];
  final evidence = <String>[];
  Map<String, dynamic> Function()? environmentState;
  Map<String, dynamic> Function(String id)? caseObservations;
  ParityHarness(this.boundary, this.output);
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 100));
  List<Element> all(bool Function(Widget) predicate) {
    final found = <Element>[];
    void walk(Element e) {
      if (predicate(e.widget)) found.add(e);
      e.debugVisitOnstageChildren(walk);
    }

    walk(WidgetsBinding.instance.rootElement!);
    return found;
  }

  Element find(bool Function(Widget) predicate, [int index = 0]) {
    final found = all(predicate);
    if (found.length <= index)
      throw StateError('UI target missing (index $index)');
    return found[index];
  }

  void expect(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<void> tapElement(Element e) async {
    await Scrollable.ensureVisible(e, duration: Duration.zero, alignment: .5);
    await settle();
    final box = e.renderObject;
    if (box is! RenderBox || !box.hasSize)
      throw StateError('Target is not laid out');
    await tapAt(box.localToGlobal(box.size.center(Offset.zero)));
  }

  Future<void> tapAt(Offset p) async {
    GestureBinding.instance.handlePointerEvent(
        PointerDownEvent(pointer: 1, position: p, buttons: 1));
    GestureBinding.instance
        .handlePointerEvent(PointerUpEvent(pointer: 1, position: p));
    await settle();
  }

  Future<void> tap(String text, {int index = 0}) async {
    final matches = all((w) =>
        (w is Tooltip && w.message == text) || (w is Text && w.data == text));
    if (matches.length <= index)
      throw StateError('Missing clickable label: $text [$index]');
    await tapElement(matches[index]);
  }

  Future<void> enterText(Element element, String text) async {
    await tapElement(element);
    if (element is! StatefulElement || element.state is! EditableTextState)
      throw StateError('Expected EditableTextState');
    (element.state as EditableTextState).updateEditingValue(TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length)));
    await settle();
  }

  Future<void> choose<T>(T value,
      {int index = 0,
      bool verify = true,
      bool Function(DropdownButton<T>)? where}) async {
    final e = find(
        (w) => w is DropdownButton<T> && (where == null || where(w)), index);
    final menu = e.widget as DropdownButton<T>;
    final option = menu.items!.firstWhere((i) => i.value == value);
    String? label;
    void get(Widget w) {
      if (w is Text) label = w.data;
    }

    get(option.child);
    if (label == null) throw StateError('Dropdown option has no text');
    await tapElement(e);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    var items = all((w) => w is Text && w.data == label);
    if (items.isEmpty) {
      final scrollable = all((w) => w is Scrollable).last as StatefulElement;
      final position = (scrollable.state as ScrollableState).position;
      final optionIndex = menu.items!.indexWhere((i) => i.value == value);
      position.jumpTo((optionIndex * (menu.itemHeight ?? 48) -
              position.viewportDimension / 2)
          .clamp(position.minScrollExtent, position.maxScrollExtent));
      await settle();
      items = all((w) => w is Text && w.data == label);
    }
    if (items.isEmpty)
      throw StateError('Dropdown option is not reachable: $label');
    await tapElement(items.last);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (verify)
      expect(
          (find((w) => w is DropdownButton<T> && (where == null || where(w)),
                          index)
                      .widget as DropdownButton<T>)
                  .value ==
              value,
          'Dropdown did not select $value');
  }

  Future<String> screenshot(String id) async {
    await settle();
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final path = '${output.path}/${Uri.encodeComponent(id)}.png';
    await File(path).writeAsBytes(data!.buffer.asUint8List());
    evidence.add(path);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final title = find((w) => w.key == const ValueKey('toolbox-drag'));
    Element? toolboxElement;
    title.visitAncestorElements((e) {
      if (e.widget is ClassicWindow) {
        toolboxElement = e;
        return false;
      }
      return true;
    });
    if (toolboxElement == null)
      throw StateError('Toolbox drag handle has no ClassicWindow ancestor');
    final toolbox = toolboxElement!.renderObject as RenderBox;
    final origin = toolbox.localToGlobal(Offset.zero);
    final width = toolbox.size.width.ceil(),
        height = toolbox.size.height.ceil();
    canvas.drawImageRect(image, origin & toolbox.size,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()), Paint());
    final picture = recorder.endRecording();
    final crop = await picture.toImage(width, height);
    final cropData = await crop.toByteData(format: ui.ImageByteFormat.png);
    await File(path.replaceFirst('.png', '-toolbox.png'))
        .writeAsBytes(cropData!.buffer.asUint8List());
    final board = find((w) => w is CustomPaint && w.painter is BoardPainter)
        .renderObject as RenderBox;
    final desktopOrigin =
        board.localToGlobal(Offset.zero) - const Offset(3, 27);
    final desktopRecorder = ui.PictureRecorder();
    final desktopCanvas = Canvas(desktopRecorder);
    desktopCanvas.drawImageRect(image, desktopOrigin & const Size(1224, 640),
        const Rect.fromLTWH(0, 0, 1224, 640), Paint());
    final desktopPicture = desktopRecorder.endRecording();
    final desktop = await desktopPicture.toImage(1224, 640);
    final desktopData =
        await desktop.toByteData(format: ui.ImageByteFormat.png);
    await File(path.replaceFirst('.png', '-desktop.png'))
        .writeAsBytes(desktopData!.buffer.asUint8List());
    desktop.dispose();
    desktopPicture.dispose();
    crop.dispose();
    picture.dispose();
    image.dispose();
    return path;
  }

  Future<void> run(
      String id, String description, Future<void> Function() body) async {
    if (declaredCases.containsKey(id))
      throw StateError('Duplicate case ID: $id');
    declaredCases[id] = description;
    final shardCount =
        int.parse(Platform.environment['PVZ_PARITY_SHARD_COUNT'] ?? '1');
    final shardIndex =
        int.parse(Platform.environment['PVZ_PARITY_SHARD_INDEX'] ?? '0');
    if (shardCount < 1 || shardIndex < 0 || shardIndex >= shardCount) {
      throw ArgumentError('Invalid parity shard index/count');
    }
    final stableHash =
        id.codeUnits.fold<int>(0, (hash, c) => ((hash * 31) + c) & 0x7fffffff);
    if (stableHash % shardCount != shardIndex) return;
    final filter = Platform.environment['PVZ_PARITY_FILTER'];
    if (filter != null && !RegExp(filter).hasMatch(id)) return;
    final before = errors.length;
    evidence.clear();
    final row = <String, dynamic>{
      'id': id,
      'description': description,
      'status': 'pass'
    };
    try {
      await body();
      if (errors.length > before)
        throw StateError(
            errors.skip(before).map((e) => e.exceptionAsString()).join('\n'));
    } catch (e, stack) {
      row['status'] = e is UnimplementedError ? 'notImplemented' : 'fail';
      row['error'] = '$e';
      row['stack'] = '$stack';
    }
    try {
      row['screenshot'] = await screenshot(id);
    } catch (e) {
      row['screenshotError'] = '$e';
      if (evidence.isNotEmpty) row['screenshot'] = evidence.last;
      row['status'] = 'fail';
    }
    row['screenshots'] = List<String>.from(evidence);
    row['observations'] = caseObservations?.call(id);
    cases.add(row);
    stdout.writeln(
        '${row['status']}: $id ${row['error'] ?? row['screenshotError'] ?? ''}');
    await report();
  }

  Future<void> report() async {
    await File('${output.path}/report.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'viewport': {'width': 1240, 'height': 800},
      'crops': {
        'toolbox': 'actual ClassicWindow render bounds',
        'desktop':
            '1224x640 at actual board origin minus original board offset (3,27); no scaling'
      },
      'engine': 'flutter_tester',
      'environmentState': environmentState?.call(),
      'suite': {
        'filter': Platform.environment['PVZ_PARITY_FILTER'],
        'shardCount': Platform.environment['PVZ_PARITY_SHARD_COUNT'] ?? '1',
        'shardIndex': Platform.environment['PVZ_PARITY_SHARD_INDEX'] ?? '0',
        'declared': declaredCases.length,
        'executed': cases.length,
        'caseManifest': declaredCases
      },
      'interaction':
          'real pointer events; Scrollable.ensureVisible for offscreen targets',
      'cases': cases,
      'summary': {
        for (final s in ['pass', 'fail', 'notImplemented'])
          s: cases.where((c) => c['status'] == s).length
      }
    }));
  }
}

class ParityMessenger extends BinaryMessenger {
  final BinaryMessenger delegate;
  ParityMessenger(this.delegate);
  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    final handler = ParityBinding.handlers[channel];
    if (handler == null) return delegate.send(channel, message);
    final MethodCodec codec = channel == SystemChannels.platform.name
        ? const JSONMethodCodec()
        : const StandardMethodCodec();
    return handler(codec.decodeMethodCall(message))
        .then(codec.encodeSuccessEnvelope);
  }

  @override
  void setMessageHandler(
          String channel, Future<ByteData?>? Function(ByteData?)? handler) =>
      delegate.setMessageHandler(channel, handler);
  @override
  Future<void> handlePlatformMessage(String channel, ByteData? data,
          ui.PlatformMessageResponseCallback? callback) =>
      // ignore: deprecated_member_use
      delegate.handlePlatformMessage(channel, data, callback);
}
