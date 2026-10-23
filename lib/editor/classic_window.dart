import '../platform/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// A desktop-style window whose title remains reachable while its body scrolls.
class ClassicWindow extends StatelessWidget {
  final String title;
  final double width, height;
  final Widget child;
  final ValueChanged<Offset> onDrag;
  final VoidCallback? onClose;
  final Key? dragKey;
  const ClassicWindow(
      {super.key,
      required this.title,
      required this.width,
      required this.height,
      required this.child,
      required this.onDrag,
      this.onClose,
      this.dragKey});

  @override
  Widget build(BuildContext context) => Material(
      elevation: 8,
      color: const Color(0xffc4d5e3),
      child: Container(
          width: width,
          height: height,
          decoration:
              BoxDecoration(border: Border.all(color: const Color(0xff34495d))),
          child: Column(children: [
            Container(
                height: 29,
                color: const Color(0xffb6c8d9),
                child: Row(children: [
                  Expanded(
                      child: RawGestureDetector(
                          key: dragKey,
                          behavior: HitTestBehavior.opaque,
                          gestures: {
                            EagerGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                        EagerGestureRecognizer>(
                                    EagerGestureRecognizer.new, (_) {}),
                          },
                          child: Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerMove: (event) {
                                if (event.buttons == 1) onDrag(event.delta);
                              },
                              child: MouseRegion(
                                  cursor: SystemMouseCursors.move,
                                  child: Container(
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.only(left: 7),
                                      child: Text(AppLanguage.text(title),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight:
                                                  FontWeight.bold))))))),
                  if (onClose != null)
                    SizedBox(
                        width: 28,
                        child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            tooltip: AppLanguage.text('关闭$title'),
                            onPressed: onClose,
                            icon: const Icon(Icons.close))),
                ])),
            Expanded(child: child),
          ])));
}
