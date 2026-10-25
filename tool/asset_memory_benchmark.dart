// Native Release benchmark driver. All variants use this identical entry point,
// separate test databases, the real shared sidebar engine and real UI widgets.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/editor_tabs.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/formation_thumbnail.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';
import 'package:pvz_formation_editor/library/thumbnail_store.dart';
import 'package:pvz_formation_editor/platform/image_memory.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

final root = Directory(Platform.environment['PVZ_ASSET_BENCH_ROOT']!);
final errors = <String>[];
final clock = Stopwatch()..start();
Future<void> delay([int ms = 200]) => Future.delayed(Duration(milliseconds: ms));
void check(bool value, String why) { if (!value) throw StateError(why); }
List<Element> elements(bool Function(Widget) test) {
  final found = <Element>[];
  void walk(Element e) {
    if (test(e.widget)) found.add(e);
    e.debugVisitOnstageChildren(walk);
  }
  final element = WidgetsBinding.instance.rootElement;
  if (element != null) walk(element);
  return found;
}
Future<void> until(bool Function() test, String why, {int seconds = 30}) async {
  final stop = DateTime.now().add(Duration(seconds: seconds));
  while (!test() && DateTime.now().isBefore(stop)) { await delay(50); }
  check(test(), why);
}
dynamic page() => (elements((w) => w is app.EditorPage).first as StatefulElement).state;
Future<void> tapKey(String key) async {
  final found = elements((w) => w.key == ValueKey(key));
  check(found.isNotEmpty, 'Missing UI control $key');
  Widget widget = found.first.widget;
  if (widget is Tooltip) {
    widget = widget.child!;
  }
  if (widget is InkWell) { widget.onTap!(); }
  else if (widget is GestureDetector) { widget.onTap!(); }
  else if (widget is ButtonStyleButton) { widget.onPressed!(); }
  else { throw StateError('Unexpected control $key: ${widget.runtimeType}'); }
  await delay(120);
}
List<ScrollableState> scrolls(Element element) {
  final result = <ScrollableState>[];
  void walk(Element e) {
    if (e is StatefulElement && e.state is ScrollableState) {
      final state = e.state as ScrollableState;
      if (state.position.hasContentDimensions) result.add(state);
    }
    e.debugVisitOnstageChildren(walk);
  }
  walk(element);
  return result;
}
Future<void> sweep(Element element) async {
  for (final scroll in scrolls(element)) {
    final max = scroll.position.maxScrollExtent;
    for (var p = 0.0; p < max; p += 220) {
      scroll.position.jumpTo(p); await delay(120);
    }
    scroll.position.jumpTo(max); await delay(180);
    scroll.position.jumpTo(0); await delay(180);
  }
}
Future<void> write(String path, Object value) async {
  final temporary = File('${root.path}/$path.$pid.tmp');
  await temporary.writeAsString(jsonEncode(value), flush: true);
  for (var attempt = 0; ; attempt++) {
    try {
      await temporary.rename('${root.path}/$path');
      break;
    } on FileSystemException {
      if (attempt >= 49) rethrow;
      await delay(20);
    }
  }
}
Future<Map<String, Object?>> stats() async => {
  'rss': ProcessInfo.currentRss,
  'resources': OriginalAssets.resourceStats(),
  'thumbnailBytes': FormationThumbnail.cachedBytes,
  'generated': ThumbnailStore.generated, 'diskHits': ThumbnailStore.diskHits,
  'documentCache': LibraryPreset.cachedDocumentCount,
  'errors': errors.toList(),
};
Future<void> phase(String name, Future<void> Function() action,
    {int settleSeconds = 5}) async {
  final began = DateTime.now().millisecondsSinceEpoch;
  await write('phase.json', {'phase': name, 'begin': began});
  await action();
  await delay(settleSeconds * 1000);
  final record = {'phase': name, 'begin': began,
    'end': DateTime.now().millisecondsSinceEpoch, ...await stats()};
  await File('${root.path}/events.jsonl').writeAsString('${jsonEncode(record)}\n',
      mode: FileMode.append, flush: true);
}

@pragma('vm:entry-point')
Future<void> toolboxMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  ThumbnailStore.directoryOverride = Directory('${root.path}/thumbnails');
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  await app.toolboxMain();
  unawaited(sidebarLoop());
}
@pragma('vm:entry-point')
Future<void> libraryMain() => app.libraryMain();

Future<void> sidebarLoop() async {
  try {
    await until(() => elements((w) => w is app.EditorPage).isNotEmpty,
        'Sidebar editor initialized');
    await write('sidebar-ready.json', {'pid': pid});
    var serial = 0;
    while (true) {
      final file = File('${root.path}/command-${serial + 1}.json');
      if (file.existsSync()) {
        final command = jsonDecode(await file.readAsString()) as Map;
        if (command['serial'] != serial) {
          serial = command['serial'] as int;
          final action = command['action'];
          try {
            final details = <String, Object?>{};
            if (action == 'cards') {
              for (final index in [1,3,4,5]) {
                page().selectToolboxTab(index);
                await delay(350);
                await sweep(elements((w) => w is app.EditorPage).first);
              }
              page().selectToolboxTab(2);
              await delay(500);
              for (final category in ['植物', '僵尸', '物品效果']) {
                if (page().category != category) await tapKey('catalog-category-$category');
                await delay(500);
                await sweep(elements((w) => w is app.EditorPage).first);
              }
              for (final type in ['cob', 'gloom', 'magnet', 'gargantuar', 'dolphin', 'ScaryPot']) {
                page().selectedId = null;
                page().selectedType = type;
                final Future pending = page().chooseAppearance();
                await until(() => elements((w) => w is AlertDialog).isNotEmpty, 'Appearance $type');
                await sweep(elements((w) => w is AlertDialog).first);
                final dialog = elements((w) => w is AlertDialog).first;
                Navigator.of(dialog).pop();
                await pending;
                await delay(200);
              }
              details['categories'] = 3; details['appearanceTypes'] = 6;
              details['otherToolboxTabs'] = 4;
            } else if (action == 'list') {
              final section = command['section'] as String;
              await until(() => elements((w) => w.key == ValueKey('library-section-$section')).isNotEmpty,
                  'Library section $section');
              await tapKey('library-section-$section');
              await delay(600);
              final lists = elements((w) => w.key == const ValueKey('library-results'));
              check(lists.isNotEmpty, 'Real library results list');
              final scroll = scrolls(lists.first).first;
              final seen = <String>{};
              final began = clock.elapsedMilliseconds;
              final passes = command['passes'] as int? ?? 2;
              for (var pass = 0; pass < passes; pass++) {
                final max = scroll.position.maxScrollExtent;
                for (var offset = 0.0; offset <= max + 400; offset += 400) {
                  final pixel = offset.clamp(0.0, max);
                  scroll.position.jumpTo(pass.isEven ? pixel : max - pixel);
                  await delay(100);
                  await until(() => visibleThumbnailsReady(seen),
                      'All visible thumbnails ready: $section pass $pass', seconds: 45);
                }
              }
              scroll.position.jumpTo(0);
              await delay(300);
              await until(() => visibleThumbnailsReady(seen), 'Scroll-back thumbnails');
              details.addAll({'seenThumbnails': seen.length, 'passes': passes,
                'milliseconds': clock.elapsedMilliseconds - began});
              if (section == '预制名阵') check(seen.length >= 363, 'All 363 presets actually displayed');
              if (section == '我的存档') check(seen.length >= 37, 'All 37 user archives actually displayed');
            }
            final dir = ThumbnailStore.directoryOverride!;
            final cache = <String, int>{};
            if (dir.existsSync()) {
              for (final file in dir.listSync().whereType<File>()) {
                final ext = file.path.split('.').last;
                cache[ext] = (cache[ext] ?? 0) + file.lengthSync();
              }
            }
            await write('response-$serial.json', {'ok': true, ...await stats(), ...details, 'diskBytesByFormat': cache});
          } catch (error, stack) {
            await write('response-$serial.json', {'ok': false, 'error': '$error\n$stack'});
          }
        }
      }
      await delay(100);
    }
  } catch (error, stack) {
    await write('sidebar-error.json', {'error': '$error\n$stack'});
  }
}

bool visibleThumbnailsReady(Set<String> seen) {
  var count = 0, ready = true;
  for (final element in elements((w) => w is FormationThumbnail)) {
    final render = element.renderObject;
    if (render is! RenderBox || !render.attached || !render.hasSize) continue;
    final top = render.localToGlobal(Offset.zero);
    final size = MediaQuery.sizeOf(element);
    if (top.dy + render.size.height <= 0 || top.dy >= size.height) continue;
    element.visitAncestorElements((ancestor) {
      final key = ancestor.widget.key;
      if (key is ValueKey<String> && key.value.startsWith('library-item-')) {
        seen.add(key.value);
        return false;
      }
      return true;
    });
    var hasImage = false;
    void walk(Element child) {
      if (child.widget case RawImage(image: final image?) when image.width == 256 && image.height == 192) {
        hasImage = true;
      }
      child.debugVisitOnstageChildren(walk);
    }
    walk(element);
    count++;
    ready = ready && hasImage;
  }
  return count > 0 && ready;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ThumbnailStore.directoryOverride = Directory('${root.path}/thumbnails');
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  await ImageMemory.configure();
  app.initializeExitHandling();
  try {
    final report = <String, Object?>{};
    final repo = await FormationRepository.open('${root.path}/archives.sqlite');
    final fixtures = jsonDecode(await File(Platform.environment['PVZ_ASSET_BENCH_ARCHIVES']!).readAsString()) as List;
    for (var i = 0; i < fixtures.length; i++) {
      final row = fixtures[i] as Map;
      await repo.saveArchive(id: 'benchmark-$i', name: row['name'] as String,
          document: Map<String, dynamic>.from(row['document'] as Map));
    }
    final initial = EditorSession(repo, document: Formation(mapId: 'day'),
        name: 'Controlled empty formation', persistDraft: false);
    final tabs = EditorTabsController(repo, initial: initial);
    var serial = 0;
    Future<Map> command(String action, [Map<String, Object?> args = const {}]) async {
      serial++;
      await write('command-$serial.json', {'serial': serial, 'action': action, ...args});
      final response = File('${root.path}/response-$serial.json');
      await until(response.existsSync, 'Sidebar command $action', seconds: 480);
      final result = jsonDecode(await response.readAsString()) as Map;
      check(result['ok'] == true, '$result');
      return result;
    }
    await phase('startup', () async {
      await Future.wait([OriginalAssets.ensureLoaded(), LibraryPresets.ensurePreviewIndex()]);
      runApp(MaterialApp(theme: ThemeData(useMaterial3: true),
          home: app.EditorWorkspace(controller: tabs,
              libraryPath: '${root.path}/archives.sqlite', continueArchive: (_) async {})));
      await until(() => WindowBridge.supported, 'Real native window bridge');
      await until(() => File('${root.path}/sidebar-ready.json').existsSync(), 'Real sidebar engine');
      report['windows'] = await WindowBridge.channel.invokeMethod('diagnostics');
      await delay(1500);
    });
    await phase('seed_chooser', () async {
      await page().toggleSeedChooser(true);
      await delay(500);
      await sweep(elements((w) => w.key == const ValueKey('seed-normal-grid')).first);
      await tapKey('seed-choice-normal-pea');
      await tapKey('seed-imitater-open');
      await delay(500);
      await tapKey('seed-choice-mimic-snow');
      for (final type in ['sunflower','lily','pumpkin','cob','gloom','fume','ice','coffee']) {
        await tapKey('seed-choice-normal-$type');
      }
      check(tabs.active.document.seedSlots.length == 10, 'Ten seed slots filled');
      await tapKey('seed-choice-normal-pea');
      await tapKey('seed-choice-normal-repeater');
      check(tabs.active.document.seedSlots.length == 10, 'Seed card replaced');
      await tapKey('seed-lets-rock');
    });
    await phase('cards_and_appearances', () async {
      await WindowBridge.channel.invokeMethod('selectSidebarMode', {'mode':'toolbox','toolboxTab':2});
      report['cards'] = await command('cards');
    });
    await phase('twelve_preset_tabs', () async {
      final indices = <int>[93,154,215,269,333,349,59,81,225,275,350,362];
      for (final index in indices) {
        final preset = LibraryPresets.all[index];
        await tabs.open(EditorSession(repo, document: preset.document,
            name: preset.name, readOnly: true, persistDraft: false), newTab: true);
        await delay(550);
      }
      check(tabs.sessions.length == 13, 'Twelve preset tabs plus initial document');
      for (var round = 0; round < 2; round++) {
        for (var index = 1; index < tabs.sessions.length; index++) {
          await tabs.activate(index); await delay(250);
        }
      }
      report['openTabs'] = tabs.sessions.map((s) => {'name': s.name, 'map': s.document.mapId,
        'pieces': s.document.pieces.length}).toList();
    });
    await phase('my_archives_full_scroll', () async {
      await WindowBridge.selectMode('library');
      report['archives'] = await command('list', {'section': '我的存档', 'passes': 2});
    });
    await phase('presets_full_scroll_cold', () async {
      report['cold'] = await command('list', {'section': '预制名阵', 'passes': 2});
    });
    await phase('presets_full_scroll_warm', () async {
      report['warm'] = await command('list', {'section': '预制名阵', 'passes': 2});
    });
    await phase('library_idle_30s', () async { await delay(25000); });
    await phase('return_to_editor_idle_30s', () async {
      await WindowBridge.channel.invokeMethod('selectSidebarMode', {'mode':'toolbox','toolboxTab':2});
      await tabs.activate(1);
      await delay(25000);
    });
    report['root'] = await stats();
    report['sidebar'] = await command('stats');
    report['status'] = 'complete';
    check(errors.isEmpty && (report['sidebar'] as Map)['errors'] is List &&
        ((report['sidebar'] as Map)['errors'] as List).isEmpty, 'No Flutter errors');
    await tabs.flushAll();
    await write('complete.json', report);
  } catch (error, stack) {
    await write('failed.json', {'error': '$error\n$stack', 'errors': errors});
  }
}
