// Real engine pointer interactions. No native window or original-site pixel claim.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/seed_chooser.dart';

class Binding extends WidgetsFlutterBinding {
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      const ViewConfiguration(size: Size(800, 650), devicePixelRatio: 1);
}

void check(bool value, String why) {
  if (!value) throw StateError(why);
}

Element? find(bool Function(Widget) predicate) {
  Element? result;
  void walk(Element e) {
    if (predicate(e.widget)) result = e;
    e.visitChildren(walk);
  }

  walk(WidgetsBinding.instance.rootElement!);
  return result;
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 120));
Future<void> tap(String key) async {
  final element = find((w) => w.key == ValueKey(key));
  check(element != null, 'Missing $key');
  await Scrollable.ensureVisible(element!,
      duration: Duration.zero, alignment: .5);
  await settle();
  final box = element.renderObject as RenderBox,
      p = box.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: p, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 1, position: p));
  await settle();
}

Future<void> main() async {
  Binding();
  await OriginalAssets.ensureLoaded();
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  final doc = ValueNotifier(Formation(
      mapId: 'roof',
      sunValue: 777,
      fogColumns: 2,
      pieces: [Piece(id: 'existing', type: 'pot', row: 1, col: 2, layer: 0)]));
  final original = doc.value.toJson(), key = GlobalKey();
  var changes = 0, closes = 0, readOnly = false;
  final results = <String>[];
  Future<void> mount() async {
    runApp(MaterialApp(
        home: Scaffold(
            body: Center(
                child: ValueListenableBuilder<Formation>(
                    valueListenable: doc,
                    builder: (context, value, _) => RepaintBoundary(
                        key: key,
                        child: OriginalSeedChooser(
                            document: value,
                            readOnly: readOnly,
                            onChanged: (next) {
                              changes++;
                              doc.value = next;
                            },
                            onClose: () => closes++)))))));
    await settle();
    await settle();
  }

  Future<void> shot(String name) async {
    final render =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/pvz-seed-chooser-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  try {
    await mount();
    check(find((w) => w is RawImage && w.image != null) != null,
        'Original card artwork loaded');
    await shot('normal');
    await tap('seed-choice-normal-pea');
    check(doc.value.seedSlots.single == 'pea', 'Normal add');
    await tap('seed-choice-normal-pea');
    check(doc.value.seedSlots.isEmpty, 'Normal second click removes');
    results.add('normal add and second-click removal');
    await tap('seed-choice-normal-pea');
    await tap('seed-imitater-open');
    check(
        find((w) => w.key == const ValueKey('seed-choice-mimic-gatling')) ==
            null,
        'Upgrades excluded from mimic chooser');
    await shot('imitater');
    await tap('seed-choice-mimic-pea');
    check(
        doc.value.seedSlots.join(',') == 'pea,pea' &&
            doc.value.imitaterSeedSlots.single == 1,
        'Normal and mimic same plant coexist');
    check(find((w) => w.key == const ValueKey('seed-normal-grid')) != null,
        'Mimic choice returns to normal chooser');
    results.add(
        'base-only mimic chooser; same plant normal+gray; closes mimic overlay');
    await tap('seed-choice-normal-pea');
    check(
        doc.value.seedSlots.single == 'pea' &&
            doc.value.imitaterSeedSlots.single == 0,
        'Removal shifts gray index');
    results.add('normal removal preserves and shifts gray index');
    await tap('seed-imitater-open');
    check(
        doc.value.seedSlots.single == 'pea' &&
            doc.value.imitaterSeedSlots.single == 0 &&
            find((w) => w.key == const ValueKey('seed-mimic-grid')) == null,
        'Selected mimic entry must wait for top-bank return');
    results.add('selected mimic entry stays disabled until top-bank return');
    doc.value = doc.value.copy(
        seedSlots: WebsiteCodec.plantIds.take(10).toList(),
        imitaterSeedSlots: {});
    await settle();
    final before = changes;
    await tap('seed-choice-normal-fume');
    check(changes == before && doc.value.seedSlots.length == 10,
        'Eleventh card cannot be added');
    final button = find((w) => w.key == const ValueKey('seed-imitater-open'))!
        .widget as GestureDetector;
    check(button.onTap == null, 'Mimic cannot open when full');
    await tap('seed-choice-normal-pea');
    check(
        doc.value.seedSlots.length == 9, 'Full chooser still permits removal');
    results
        .add('ten-card limit, blocked eleventh and mimic, removal while full');
    final copy = doc.value.toJson()
      ..['seedSlots'] = original['seedSlots']
      ..['imitaterSeedSlots'] = original['imitaterSeedSlots'];
    // Optional empty imitater field follows the model's existing JSON convention.
    if (!original.containsKey('imitaterSeedSlots')) {
      copy.remove('imitaterSeedSlots');
    }
    check(jsonEncode(copy) == jsonEncode(original),
        'Unrelated document fields preserved');
    results.add('map, sun, fog, pieces and other document fields unchanged');
    readOnly = true;
    await mount();
    final readBefore = changes;
    await tap('seed-choice-normal-pea');
    check(changes == readBefore, 'Read-only selection blocked');
    check(
        (find((w) => w.key == const ValueKey('seed-imitater-open'))!.widget
                    as GestureDetector)
                .onTap ==
            null,
        'Read-only mimic blocked');
    results.add('read-only selection and mimic guards');
    final valueBefore = doc.value.toJson();
    await tap('seed-lets-rock');
    check(
        closes == 1 &&
            jsonEncode(doc.value.toJson()) == jsonEncode(valueBefore),
        'ROCK only closes overlay');
    results.add('ROCK close callback only, no document or route changes');
    check(errors.isEmpty, 'Flutter errors: $errors');
    await File('/tmp/pvz-seed-chooser-report.json').writeAsString(jsonEncode({
      'pass': results,
      'errors': errors,
      'scope':
          'standalone widget, real Flutter pointers, source visual parity not evaluated'
    }));
    stdout.writeln('PASS ${results.length}: ${results.join('; ')}');
    exit(0);
  } catch (e, stack) {
    stderr.writeln('$e\n$stack\n$errors');
    exit(1);
  }
}
