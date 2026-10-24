import 'dart:io';
import 'package:pvz_formation_editor/main.dart' as app;
import 'live_preset_apply_smoke.dart' as presets;
import 'mushroom_live_smoke.dart' as plants;
import 'windows_native_smoke.dart' as windows;
import 'windows_memory_close_smoke.dart' as memory;
import 'native_file_dialog_smoke.dart' as files;

String? get scenario => Platform.environment['PVZ_ACCEPTANCE_CASE'];

@pragma('vm:entry-point')
Future<void> toolboxMain() => scenario == 'memory-close'
    ? memory.toolboxMain() : app.toolboxMain();

@pragma('vm:entry-point')
Future<void> libraryMain() => scenario == 'memory-close'
    ? memory.libraryMain() : app.libraryMain();

Future<void> main() async {
  switch (scenario) {
    case 'presets': await presets.main();
    case 'plants': await plants.main();
    case 'windows': await windows.main();
    case 'memory-close': await memory.main();
    case 'file-dialogs': await files.main();
    default: throw ArgumentError('Select PVZ_ACCEPTANCE_CASE');
  }
}
