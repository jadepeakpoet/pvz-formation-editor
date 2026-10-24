import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pvz_formation_editor/widgets/app_dropdown.dart';

class Binding extends WidgetsFlutterBinding {
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(logicalConstraints: BoxConstraints.tight(Size(360, 640)), physicalConstraints: BoxConstraints.tight(Size(360, 640)), devicePixelRatio: 1);
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

List<Element> find(bool Function(Widget) predicate) {
  final found = <Element>[];
  void walk(Element element) {
    if (predicate(element.widget)) found.add(element);
    element.visitChildren(walk);
  }

  walk(WidgetsBinding.instance.rootElement!);
  return found;
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 250));
Future<void> tap(Element element) async {
  final box = element.renderObject as RenderBox;
  final position = box.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: position, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 1, position: position));
  await settle();
}

Future<void> main() async {
  Binding();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  var value = 'a', changes = 0;
  runApp(
      MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
    return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          SizedBox(
              width: 140,
              child: AppDropdown<String>(
                  key: const ValueKey('enabled'),
                  value: value,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'a',
                        child: Text(
                            'A very long selected option in a narrow field')),
                    DropdownMenuItem(value: 'b', child: Text('Option B')),
                  ],
                  onChanged: (next) => setState(() {
                        value = next!;
                        changes++;
                      }))),
          const SizedBox(height: 12),
          const AppDropdown<String>(
              key: ValueKey('disabled'),
              value: 'a',
              items: [DropdownMenuItem(value: 'a', child: Text('Disabled'))],
              onChanged: null),
        ]));
  }))));
  await settle();
  final enabled = find((w) => w.key == const ValueKey('enabled')).single;
  final dropdown = enabled.widget as DropdownButton<String>;
  check(
      dropdown.onChanged != null &&
          dropdown.menuMaxHeight == 320 &&
          dropdown.borderRadius == BorderRadius.circular(8) &&
          dropdown.dropdownColor == const Color(0xfffcfdf9),
      'Dropdown menu style missing');
  check((enabled.renderObject as RenderBox).size.width <= 140,
      'Long selected text exceeded narrow field');
  await tap(enabled);
  final option =
      find((w) => w is DropdownMenuItem<String> && w.value == 'b').single;
  await tap(option);
  await settle();
  check(value == 'b' && changes == 1,
      'Dropdown did not select actual menu option');
  final disabled = find((w) => w.key == const ValueKey('disabled')).single;
  check((disabled.widget as DropdownButton<String>).onChanged == null,
      'Disabled dropdown became interactive');
  await tap(disabled);
  check(find((w) => w is DropdownMenuItem<String>).isEmpty && changes == 1,
      'Disabled field opened a menu or changed selection');
  check(errors.isEmpty, errors.map((e) => e.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS styled dropdown narrow/long option, native menu selection, preserved key and disabled behavior');
  runApp(const SizedBox.shrink());
  await settle();
  exit(0);
}
