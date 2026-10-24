import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const MethodChannel('pvz_formation_editor/lifecycle')
      .setMethodCallHandler((_) async => true);
  runApp(const ColoredBox(color: Color(0xffeeeeee)));
}
