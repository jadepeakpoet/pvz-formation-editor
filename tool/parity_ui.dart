// ignore_for_file: curly_braces_in_flow_control_structures
// Compile/run like tool/ui_smoke.dart; output directory: PVZ_PARITY_OUTPUT.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pvz_formation_editor/main.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/domain/original_catalog.dart';
import 'package:pvz_formation_editor/platform/original_audio.dart';
import 'package:pvz_formation_editor/domain/object_filter.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/seed_chooser.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  final output = Directory(
      Platform.environment['PVZ_PARITY_OUTPUT'] ?? '/tmp/pvz-parity-ui');
  await output.create(recursive: true);
  final key = GlobalKey();
  final h = ParityHarness(key, output);
  FlutterError.onError = h.errors.add;
  h.environmentState = () => {
        'music': OriginalAudio.status.value,
        'plantingSound': OriginalAudio.soundStatus.value,
        'nativeAudioAudibility': 'notTestedInHeadlessEngine',
        'filePlatform': 'mockNativeDialogs; realTemporaryFiles',
        'clipboard': 'inMemoryMock',
        'externalNavigation': 'inMemoryMock; native navigation not executed'
      };
  late Directory temp;
  final saved = <Map<dynamic, dynamic>>[];
  Future<Uint8List> savedBytes() async {
    final immediate = saved.last['bytes'] as Uint8List?;
    if (immediate != null) return immediate;
    final file = File(saved.last['path'] as String);
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    while (!await file.exists() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    return file.readAsBytes();
  }

  Uint8List? picked;
  String clipboard = '';
  final externalUrls = <String>[];
  ParityBinding.handlers['pvz_formation_editor/files'] = (call) async {
    if (call.method == 'chooseSavePath') {
      final args = Map<dynamic, dynamic>.from(call.arguments as Map);
      final path = '${temp.path}/export-${saved.length}-${args['name']}';
      saved.add({...args, 'path': path});
      return path;
    }
    if (call.method == 'pickFormation')
      return picked == null ? null : {'path': null, 'bytes': picked};
    if (call.method == 'saveFile') {
      saved.add(Map<dynamic, dynamic>.from(call.arguments as Map));
      return '/memory/${saved.last['name']}';
    }
    if (call.method == 'pickProject') return picked;
    if (call.method == 'openExternal') {
      externalUrls.add((call.arguments as Map)['url'] as String);
      return true;
    }
    throw MissingPluginException();
  };
  ParityBinding.handlers[SystemChannels.platform.name] = (call) async {
    if (call.method == 'Clipboard.setData')
      clipboard = (call.arguments as Map)['text'] as String;
    if (call.method == 'Clipboard.getData') return {'text': clipboard};
    return null;
  };
  await OriginalAssets.ensureLoaded();
  temp = await Directory.systemTemp.createTemp('pvz-parity-data-');
  final repo = await FormationRepository.open('${temp.path}/test.sqlite');
  final session = EditorSession(repo);
  h.caseObservations = (id) => {
        'mapId': session.document.mapId,
        'objectCount': session.document.pieces.length,
        'sunValue': session.document.sunValue,
        'fogColumns': session.document.fogColumns,
        'display': session.document.display,
        'seedSlots': session.document.seedSlots,
        if (session.document.pieces.length <= 10)
          'pieces': [
            for (final p in session.document.pieces)
              {
                'type': p.type,
                'row': p.row,
                'col': p.col,
                'frameRow': p.frameRow,
                'frameCol': p.frameCol,
                'opacity': p.opacity,
                'effects': p.effects.toList(),
                'flipX': p.flipped,
                'flipY': p.flippedVertical
              }
          ]
      };
  Future<void> mount() async {
    runApp(RepaintBoundary(
        key: key,
        child: MaterialApp(
            key: UniqueKey(),
            theme: ThemeData(
                useMaterial3: true,
                colorScheme:
                    ColorScheme.fromSeed(seedColor: const Color(0xff456b4e))),
            home: EditorPage(
                key: UniqueKey(),
                session: session,
                continueArchive: (_) async {}))));
    await h.settle();
    await h.settle();
  }

  Future<void> fresh([String tab = '图鉴选卡']) async {
    session.execute('UI case fixture', Formation());
    await mount();
    await h.tap(tab);
  }

  Future<void> cell([int row = 0, int col = 0]) async {
    final e = h.find((w) => w is CustomPaint && w.painter is BoardPainter);
    final box = e.renderObject as RenderBox;
    await h.tapAt(box
        .localToGlobal(BoardGeometry(session.document).cellCenter(row, col)));
  }

  Future<void> seed() async {
    await h.tap('豌豆射手');
    await cell();
    h.expect(session.document.pieces.any((p) => p.type == 'pea'),
        'Card click and board click must plant pea');
  }

  bool? controlState(Widget w) {
    if (w is Radio) return w.value == w.groupValue;
    if (w is RadioListTile) return w.value == w.groupValue;
    if (w is Checkbox) return w.value;
    if (w is Switch) return w.value;
    if (w is CheckboxListTile) return w.value;
    if (w is SwitchListTile) return w.value;
    if (w is ChoiceChip) return w.selected;
    return null;
  }

  bool? selectedElement(Element e) {
    bool? result = controlState(e.widget);
    void visit(Element child) {
      result ??= controlState(child.widget);
      child.debugVisitOnstageChildren(visit);
    }

    e.debugVisitOnstageChildren(visit);
    return result;
  }

  try {
    await mount();
    for (final tab in ['卡槽选卡', '懒人布局', '图鉴选卡', '镜像窗口', '载入导出', '选项设置']) {
      await h.run('tab.$tab', '六个主标签：$tab', () async {
        await h.tap(tab);
        final expected = <String, String>{
          '卡槽选卡': '卡槽：点击卡片添加，点击 × 移除',
          '懒人布局': '一键布局',
          '图鉴选卡': '铲除范围：',
          '镜像窗口': '镜像窗口（最多三个独立快照）',
          '载入导出': '1.载入和导出布阵字符串',
          '选项设置': '更换地图 '
        }[tab]!;
        h.expect(
            tab == '镜像窗口'
                ? h
                    .all((w) => w.key == const ValueKey('original-clone-0'))
                    .isNotEmpty
                : h.all((w) => w is Text && w.data == expected).isNotEmpty,
            'Tab did not show its own controls');
      });
    }
    for (final map in BoardMap.all.where((m) => m.originalIndex != null)) {
      await h.run('map.${map.id}', '原站地图选择再应用：${map.name}', () async {
        await fresh('选项设置');
        final before = session.document.fingerprint;
        await h.choose<String>(map.id,
            where: (w) => w.key == const ValueKey('original-lMap'));
        h.expect(session.document.fingerprint == before,
            'Selecting a map must not change document before apply');
        await h.tapElement(
            h.find((w) => w.key == const ValueKey('original-btnMap-reset')));
        h.expect(
            session.document.mapId == map.id && session.document.pieces.isEmpty,
            'Map reset/apply policy differs');
      });
    }
    for (final keep in [false, true]) {
      await h.run('map.policy.${keep ? 'keep' : 'reset'}',
          '原站双换图按钮：${keep ? '保留' : '清空'}植物', () async {
        await fresh();
        await seed();
        await cell(5, 0);
        await h.tap('选项设置');
        final before = session.document.fingerprint;
        await h.choose<String>('day',
            where: (w) => w.key == const ValueKey('original-lMap'));
        h.expect(session.document.fingerprint == before,
            'Pending map selection changed source board');
        await h.tapElement(h.find((w) =>
            w.key == ValueKey('original-btnMap-${keep ? 'keep' : 'reset'}')));
        h.expect(
            session.document.mapId == 'day' &&
                session.document.pieces.length == (keep ? 1 : 0),
            'Map application did not preserve/remove mapped objects correctly');
      });
    }
    for (final map in BoardMap.all.where((m) => m.originalIndex != null)) {
      await h.run('map-download.${map.id}', '下载原站地图原文件：${map.name}', () async {
        await fresh('选项设置');
        final documentBefore = session.document.fingerprint;
        await h.choose<String>(map.id,
            where: (w) => w.key == const ValueKey('original-lMap'));
        final before = saved.length;
        await h.tapElement(
            h.find((w) => w.key == const ValueKey('original-imgBack')));
        h.expect(saved.length == before + 1,
            'Map download did not reach file platform');
        h.expect(saved.last['name'] == map.background,
            'Downloaded map name differs from original target');
        final raw =
            await rootBundle.load('assets/original/image/${map.background}');
        final expected =
                raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
            actual = await savedBytes();
        var equal = actual.length == expected.length;
        for (var i = 0; equal && i < actual.length; i++) {
          equal = actual[i] == expected[i];
        }
        h.expect(
            equal, 'Downloaded map bytes differ from original bundled file');
        final codec = await ui.instantiateImageCodec(actual);
        final image = (await codec.getNextFrame()).image;
        h.expect(image.width > 0 && image.height > 0,
            'Downloaded file is not a decodable map image');
        image.dispose();
        codec.dispose();
        h.expect(session.document.fingerprint == documentBefore,
            'Downloading staged map changed board');
      });
    }
    for (final category in ['植物', '僵尸', '物品', '特效']) {
      await h.run('category.$category', '分类切换与所有卡片可达性：$category', () async {
        await fresh();
        await h.tap(category);
        h.expect(
            ObjectSpec.all.where((s) => s.category == category).every((s) =>
                h.all((w) => w is Tooltip && w.message == s.name).isNotEmpty),
            'Category does not expose all cards');
      });
    }
    for (final spec in ObjectSpec.all) {
      await h.run('card.${spec.id}', '卡片选择并实际布置：${spec.name}', () async {
        await fresh();
        await h.tap(spec.category);
        final keyed =
            h.all((w) => w.key == ValueKey('original-card-${spec.id}'));
        final card = keyed.isNotEmpty
            ? keyed.single
            : h.find((w) =>
                w is Tooltip &&
                w.message == spec.name &&
                w.child is InkWell &&
                (w.child as InkWell).child is Container &&
                ((w.child as InkWell).child as Container).margin == null);
        await h.tapElement(card);
        await cell();
        if (spec.id == 'Imitater') {
          h.expect(session.document.pieces.isEmpty,
              'Standalone imitater on empty ground must do nothing');
          session.execute(
              'Imitater existing plant fixture',
              Formation(pieces: [
                Piece(
                    id: 'imitate-target',
                    type: 'pea',
                    row: 0,
                    col: 0,
                    layer: 10)
              ]));
          await h.settle();
          await cell();
          h.expect(
              session.document.pieces.single.type == 'pea' &&
                  session.document.pieces.single.effects.contains('模仿者'),
              'Standalone imitater must change the existing plant');
        } else {
          h.expect(session.document.pieces.any((p) => p.type == spec.id),
              'Card ${spec.name} did not place');
        }
      });
    }
    await h.run('card.new-selection-clears-old-object', '选新卡后外表及效果只作用新种植',
        () async {
      await fresh();
      await seed();
      await h.tap('单个选择');
      await cell();
      final beforeSelectingNewCard = session.document.pieces.first;
      await h.tap('向日葵');
      await h.tap('默认外表');
      await h.tap('1-2');
      await h.tap('冰冻');
      await cell(0, 1);
      final old = session.document.pieces.firstWhere((p) => p.type == 'pea'),
          next =
              session.document.pieces.firstWhere((p) => p.type == 'sunflower');
      h.expect(
          old.frameCol == beforeSelectingNewCard.frameCol &&
              old.frameRow == beforeSelectingNewCard.frameRow &&
              old.effects.isEmpty,
          'Selecting a new card edited the previously selected object');
      h.expect(next.frameCol == 1 && next.effects.contains('冰冻'),
          'New card did not retain planting appearance/effects');
    });
    for (final group in <(String, List<OriginalPreset>, int)>[
      ('formation', OriginalCatalog.formations, 0),
      ('cob', OriginalCatalog.cobLayouts, 1),
      ('gloom', OriginalCatalog.gloomLayouts, 2)
    ]) {
      for (final preset in group.$2) {
        await h.run(
            'preset.${group.$1}.${preset.index}', '布局下拉全部选项：${preset.name}',
            () async {
          await fresh('懒人布局');
          final before = session.document.fingerprint;
          final label = group.$1 == 'formation'
              ? '阵型'
              : group.$1 == 'cob'
                  ? '炮位'
                  : '无炮';
          await h.tapElement(
              h.find((w) => w.key == ValueKey('preset-selector-$label')));
          h.expect(session.document.fingerprint == before,
              'Opening picker edited board');
          final field =
              h.find((w) => w.key == const ValueKey('library-search'));
          Element? editable;
          void visit(Element e) {
            if (e.widget is EditableText) editable = e;
            e.debugVisitOnstageChildren(visit);
          }

          visit(field);
          await h.enterText(editable!, preset.name);
          final id = group.$1 == 'formation'
              ? 'original-${preset.index}'
              : '$label-${preset.index}';
          await h.tapElement(
              h.find((w) => w.key == ValueKey('library-item-preset:$id')));
          final expected = preset.decode(mapId: 'pool');
          h.expect(session.name == preset.name,
              'Preset did not update current document title');
          h.expect(session.document.pieces.length == expected.pieces.length,
              'Preset piece count differs');
          h.expect(
              WebsiteCodec.encode(session.document) ==
                  WebsiteCodec.encode(expected),
              'Applied preset geometry/effects/frames differ from selected source');
          h.expect(
              h
                  .all(
                      (w) => w.key == const ValueKey('formation-preset-picker'))
                  .isNotEmpty,
              'Picker must remain inside toolbox after selection');
        });
      }
    }
    for (final label in ['阵型', '炮位', '无炮']) {
      await h.run('preset.back.$label', '内嵌列表返回：$label', () async {
        await fresh('懒人布局');
        final before = session.document.fingerprint;
        await h.tapElement(
            h.find((w) => w.key == ValueKey('preset-selector-$label')));
        await h.tapElement(
            h.find((w) => w.key == const ValueKey('preset-picker-back')));
        h.expect(
            h
                    .all((w) => w.key == ValueKey('preset-selector-$label'))
                    .isNotEmpty &&
                session.document.fingerprint == before,
            'Picker back lost layout or edited document');
      });
    }
    for (var frame = 1; frame <= 3; frame++) {
      await h.run('appearance.manual.$frame', '手动外表帧 $frame', () async {
        await fresh();
        await seed();
        await h.tap('单个选择');
        await cell();
        await h.tap('默认外表');
        await h.tap('1-$frame');
        h.expect(session.document.pieces.first.frameCol == frame - 1,
            'Appearance did not update selected object');
      });
    }
    for (var mode = 0; mode < 8; mode++) {
      await h.run('grow-mode.$mode', '原站默认外表策略 $mode', () async {
        await fresh();
        final menu = h.all((w) =>
            w is DropdownButton<int> &&
            w.key == const ValueKey('original-sGrowSelect'));
        if (menu.isEmpty)
          throw UnimplementedError(
              'Original sGrowSelect default appearance strategy is not exposed');
        await h.choose<int>(mode,
            where: (w) => w.key == const ValueKey('original-sGrowSelect'));
        await h.tap('南瓜头');
        if (mode == 0) await h.tap('2-2');
        await cell();
        final planted = session.document.pieces.single;
        final expectedRow = mode == 0
            ? 1
            : mode < 2
                ? 0
                : (mode - 2) ~/ 2;
        h.expect(planted.type == 'pumpkin' && planted.frameRow == expectedRow,
            'Appearance strategy chose wrong row');
        h.expect(planted.frameCol >= 0 && planted.frameCol < 3,
            'Random appearance column out of range');
        if (mode == 0)
          h.expect(planted.frameCol == 1, 'Manual appearance choice was lost');
        if (mode >= 3 && mode.isOdd)
          h.expect(planted.frameCol == 0,
              'First-column strategy did not choose first frame');
      });
    }
    for (final family in ['cMusic', 'cAudio']) {
      for (var level = 0; level < 5; level++) {
        await h.run('original.$family$level',
            '原站${family == 'cMusic' ? '音乐' : '音效'}音量档 $level', () async {
          await fresh('选项设置');
          final target =
              h.all((w) => w.key == ValueKey('original-$family$level'));
          if (target.isEmpty)
            throw UnimplementedError(
                'Original volume control $family$level not exposed');
          await h.tapElement(target.single);
          h.expect(
              selectedElement(h.find(
                      (w) => w.key == ValueKey('original-$family$level'))) ==
                  true,
              'Volume level did not become selected');
          h.expect(
              (family == 'cMusic'
                      ? OriginalAudio.musicVolume
                      : OriginalAudio.soundVolume) ==
                  level / 4,
              'Volume UI did not update audio service level');
        });
      }
    }
    for (var skin = 1; skin <= 3; skin++) {
      await h.run('original.rWindow$skin', '原站窗口样式 $skin', () async {
        await fresh('选项设置');
        final target = h.all((w) => w.key == ValueKey('original-rWindow$skin'));
        if (target.isEmpty)
          throw UnimplementedError('Original window skin $skin not exposed');
        await h.tapElement(target.single);
        h.expect(
            selectedElement(h
                    .find((w) => w.key == ValueKey('original-rWindow$skin'))) ==
                true,
            'Window skin did not become selected');
      });
    }
    for (final entry in <(String, String, String)>[
      ('cMirrorBack', '镜像窗口', '显示阵型背景'),
      ('cPokerBack', '镜像窗口', '植吧扑克等宽'),
      ('imgBack', '选项设置', '下载地图'),
      ('lets-rock', '卡槽选卡', "Let's ROCK!"),
      ('help', '懒人布局', '?')
    ]) {
      await h.run('original.${entry.$1}', '原站控件：${entry.$3}', () async {
        await fresh(entry.$2);
        if (entry.$1 == 'lets-rock') {
          await h.tapElement(
              h.find((w) => w.key == const ValueKey('original-seed-chooser')));
          h.expect(h.all((w) => w is OriginalSeedChooser).length == 1,
              'Seed chooser overlay did not open');
          await h.tapElement(h.find(
              (w) => w.key == const ValueKey('seed-choice-normal-sunflower')));
          await h.screenshot('original.lets-rock.open');
        }
        final targets = h.all((w) =>
            w.key ==
            (entry.$1 == 'lets-rock'
                ? const ValueKey('seed-lets-rock')
                : ValueKey('original-${entry.$1}')));
        if (targets.isEmpty)
          throw UnimplementedError(
              'Original control ${entry.$1}: ${entry.$3} is not exposed');
        final beforeState = controlState(targets.single.widget);
        final savedBefore = saved.length;
        await h.tapElement(targets.single);
        if (entry.$1 == 'cPokerBack' || entry.$1 == 'cMirrorBack')
          h.expect(
              controlState(h
                      .find((w) => w.key == ValueKey('original-${entry.$1}'))
                      .widget) ==
                  !beforeState!,
              'Original mirror/export setting did not toggle');
        if (entry.$1 == 'cMirrorBack' || entry.$1 == 'cPokerBack') {
          final create =
              h.all((w) => w.key == const ValueKey('original-clone-3'));
          if (create.isEmpty)
            throw UnimplementedError(
                'Source mirror creation controls are required to verify shared export settings');
          await h.tapElement(create.single);
          if (entry.$1 == 'cMirrorBack') {
            final mirror = (h
                    .all((w) => w is CustomPaint && w.painter is BoardPainter)
                    .last
                    .widget as CustomPaint)
                .painter as BoardPainter;
            h.expect(mirror.background == !beforeState!,
                'Mirror did not inherit source background setting');
          } else {
            final box = h
                .all((w) => w is CustomPaint && w.painter is BoardPainter)
                .last
                .renderObject as RenderBox;
            final width = box.localToGlobal(Offset(box.size.width, 0)).dx -
                box.localToGlobal(Offset.zero).dx;
            h.expect((width - (!beforeState! ? 917 : 800) * .5).abs() < .5,
                'Mirror visual width does not reflect poker/game width at half scale');
          }
        }
        if (entry.$1 == 'imgBack')
          h.expect(saved.length == savedBefore + 1,
              'Map download did not save a file');
        if (entry.$1 == 'lets-rock')
          h.expect(
              h.all((w) => w is OriginalSeedChooser).isEmpty &&
                  h
                      .all((w) => w is Text && (w.data ?? '').startsWith('卡槽：'))
                      .isNotEmpty &&
                  session.document.seedSlots.contains('sunflower'),
              'Lets ROCK must only close overlay and retain toolbox tab and selected card');
        if (entry.$1 == 'help') {
          h.expect(h.all((w) => w is AlertDialog).isNotEmpty,
              'Help did not open its information dialog');
          h.expect(
              h
                  .all((w) =>
                      w is Text && (w.data ?? '').contains('使用带参数的网址可以直接显示阵型'))
                  .isNotEmpty,
              'Help text differs from source');
          await h.screenshot('original.help.open');
          await h.tap('确定');
          await Future<void>.delayed(const Duration(milliseconds: 350));
          h.expect(h.all((w) => w is AlertDialog).isEmpty,
              'Help close button failed');
        }
      });
    }
    for (final link in <(String, String, String)>[
      ('载入导出', 'toolkit', 'https://pvz.lmintlcx.com/'),
      ('镜像窗口', 'poker', 'https://tieba.baidu.com/p/5272254427'),
      ('载入导出', 'poker', 'https://tieba.baidu.com/p/5272254427')
    ]) {
      await h.run('link.${link.$2}.${link.$1}', '原站外链平台协议：${link.$2}（不执行原生导航）',
          () async {
        await fresh(link.$1);
        final before = externalUrls.length,
            documentBefore = session.document.fingerprint;
        await h.tapElement(
            h.find((w) => w.key == ValueKey('original-link-${link.$2}')));
        h.expect(
            externalUrls.length == before + 1 && externalUrls.last == link.$3,
            'External navigation URL differs from source');
        h.expect(session.document.fingerprint == documentBefore,
            'External link changed board');
      });
    }
    for (final effect in ['模仿者', '冰冻', '魅惑', '高亮', '阴影', '灰烬', '半透明']) {
      await h.run('effect.$effect', '效果开关：$effect', () async {
        await fresh();
        await seed();
        await h.tap('单个选择');
        await cell();
        await h.tap(effect);
        if (effect == '模仿者') await cell();
        h.expect(session.document.pieces.first.effects.contains(effect),
            'Effect must apply to selected piece');
        final encoded = WebsiteCodec.encode(session.document),
            fields = encoded.split(',')[1].trim().split(RegExp(r'\s+'));
        final gray = <String, String>{
          '模仿者': '1',
          '冰冻': '0010',
          '魅惑': '1000',
          '高亮': '0001',
          '阴影': '0000dropshadow',
          '灰烬': '0000black',
          '半透明': '0'
        }[effect];
        h.expect(fields[5] == gray,
            'UI effect exported the wrong original gray field');
        h.expect(fields[6] == (effect == '半透明' ? '0.5' : '1'),
            'Opacity must occupy its independent original field');
        h.expect(
            session.document.pieces.single.opacity ==
                (effect == '半透明' ? .5 : 1),
            'UI opacity differs from effect state');
        await h.screenshot('effect.$effect.enabled');
        final applied = session.document.fingerprint;
        await h.tap(effect);
        if (effect == '模仿者') {
          h.expect(session.document.fingerprint == applied,
              'Cancelling imitater tool must preserve planted effects');
          session.undo();
        }
        h.expect(!session.document.pieces.first.effects.contains(effect),
            'Effect must toggle off');
      });
    }
    for (final first in ['模仿者', '阴影', '灰烬']) {
      for (final second in ['模仿者', '阴影', '灰烬']) {
        if (first == second) continue;
        await h
            .run('effect.exclusive.$first.$second', '原站互斥滤镜：$first → $second',
                () async {
          await fresh();
          await seed();
          await h.tap('单个选择');
          await cell();
          await h.tap(first);
          if (first == '模仿者') {
            await cell();
            await h.tap('单个选择');
            await cell();
          }
          await h.tap(second);
          if (second == '模仿者') await cell();
          final p = session.document.pieces.single;
          h.expect(p.effects.contains(second) && !p.effects.contains(first),
              'Selecting a filter did not replace the previous exclusive filter');
          final fields = WebsiteCodec.encode(session.document)
              .split(',')[1]
              .trim()
              .split(RegExp(r'\s+'));
          h.expect(
              fields[5] ==
                  {
                    '模仿者': '1',
                    '阴影': '0000dropshadow',
                    '灰烬': '0000black'
                  }[second],
              'Exclusive filter export differs from source gray protocol');
        });
      }
    }
    await h.run('effect.compatible-stack', '原站可叠加颜色与独立半透明组合', () async {
      await fresh();
      await seed();
      await h.tap('单个选择');
      await cell();
      for (final effect in ['冰冻', '魅惑', '高亮', '灰烬', '半透明']) {
        await h.tap(effect);
      }
      final fields = WebsiteCodec.encode(session.document)
          .split(',')[1]
          .trim()
          .split(RegExp(r'\s+'));
      h.expect(fields[5] == '1011black' && fields[6] == '0.5',
          'Combined mask/filter/opacity encoding differs from verified source protocol');
      final decoded = WebsiteCodec.decode(WebsiteCodec.encode(session.document))
          .pieces
          .single;
      h.expect(
          decoded.opacity == .5 &&
              decoded.effects.containsAll(['冰冻', '魅惑', '高亮', '灰烬']),
          'Combined source string did not restore color/filter and opacity');
    });
    for (final flip in ['左右翻转', '上下翻转']) {
      await h.run('flip.$flip', '翻转开关：$flip', () async {
        await fresh();
        await seed();
        await h.tap('单个选择');
        await cell();
        await h.tap(flip);
        final p = session.document.pieces.first;
        h.expect(flip == '左右翻转' ? p.flipped : p.flippedVertical,
            'Flip must update selected piece');
        await h.screenshot('flip.$flip.enabled');
        await h.tap(flip);
        final restored = session.document.pieces.first;
        h.expect(flip == '左右翻转' ? !restored.flipped : !restored.flippedVertical,
            'Flip must restore');
      });
    }
    for (final filter in ['最上层', ...ObjectFilter.options]) {
      await h.run('shovel.$filter', '铲除范围：$filter', () async {
        await fresh();
        final fixture = [
          for (final type in [
            'lily',
            'pea',
            'pumpkin',
            'coffee',
            'ladder',
            'grave',
            'rake',
            'zombie',
            'explosion'
          ])
            Piece(
                id: 'fixture-$type',
                type: type,
                row: 0,
                col: 0,
                layer: ObjectSpec.byId(type).layer)
        ];
        session.execute('Shovel mixed-layer fixture',
            session.document.copy(pieces: fixture));
        await h.settle();
        await h.choose<String>(filter,
            where: (w) => w.items!.length == ObjectFilter.options.length + 2);
        await h.tap('铲子');
        await cell();
        if (filter == '最上层') {
          h.expect(session.document.pieces.length == fixture.length - 1,
              'Top-layer shovel must remove exactly one object');
          final removed = fixture.firstWhere(
              (p) => !session.document.pieces.any((q) => q.id == p.id));
          h.expect(fixture.every((p) => p.layer <= removed.layer),
              'Top-layer shovel removed lower layer');
        } else {
          final expected = fixture
              .where((p) =>
                  !ObjectFilter.matches(p, filter) &&
                  !(p.type == 'ladder' &&
                      fixture.any((q) =>
                          q.type == 'pumpkin' &&
                          ObjectFilter.matches(q, filter))))
              .map((p) => p.id)
              .toSet();
          final actual = session.document.pieces.map((p) => p.id).toSet();
          h.expect(
              actual.length == expected.length && actual.containsAll(expected),
              'Shovel must remove every matching layer and preserve other layers');
        }
      });
    }
    for (final filter in [
      '普通植物',
      '南瓜',
      '容器',
      '梯子',
      '咖啡豆',
      '钉耙',
      '墓碑',
      '物品及特效',
      '僵尸'
    ]) {
      await h.run('batch-filter.$filter', '原站独立批量铲除范围：$filter', () async {
        await fresh();
        final fixture = [
          for (final col in [0, 1])
            for (final type in [
              'lily',
              'pea',
              'pumpkin',
              'coffee',
              'ladder',
              'grave',
              'rake',
              'zombie',
              'explosion'
            ])
              Piece(
                  id: 'batch-$col-$type',
                  type: type,
                  row: 0,
                  col: col,
                  layer: ObjectSpec.byId(type).layer)
        ];
        session.execute('Batch mixed selected/unselected fixture',
            session.document.copy(pieces: fixture));
        await h.settle();
        await h.tap('批量选择');
        await cell();
        await h.tap('懒人布局');
        await h.tapElement(
            h.find((w) => w is Text && (w.data ?? '').startsWith('批量操作 ·')));
        await h.choose<String>(filter,
            where: (w) => w.key == const ValueKey('original-rBatchClear'));
        await h.tap('按类型铲除');
        final expected = fixture
            .where((p) =>
                p.col != 0 ||
                (!ObjectFilter.matches(p, filter) &&
                    !(p.type == 'ladder' &&
                        fixture.any((q) =>
                            q.col == 0 &&
                            q.type == 'pumpkin' &&
                            ObjectFilter.matches(q, filter)))))
            .map((p) => p.id)
            .toSet();
        final actual = session.document.pieces.map((p) => p.id).toSet();
        h.expect(
            actual.length == expected.length && actual.containsAll(expected),
            'Batch filter deleted wrong layers or unselected cells');
      });
    }
    for (final shortcut in [
      '陆路',
      '水路',
      '后置炮',
      '前置炮',
      '超前置炮',
      '底线炮',
      '水路前场',
      '水路56列',
      '重置批量选择'
    ]) {
      await h.run('quick.$shortcut', '批量快捷选择：$shortcut', () async {
        await fresh();
        await h.tap('懒人布局');
        await h.tapElement(
            h.find((w) => w is Text && (w.data ?? '').startsWith('批量操作 ·')));
        await h.tap(shortcut);
        final painter = (h
                .find((w) => w is CustomPaint && w.painter is BoardPainter)
                .widget as CustomPaint)
            .painter as BoardPainter;
        final rows = shortcut.startsWith('水路') ? [2, 3] : [0, 1, 4, 5];
        final columns = switch (shortcut) {
          '后置炮' => [3],
          '前置炮' => [4],
          '超前置炮' => [6],
          '底线炮' => [0],
          '水路前场' => [6, 7, 8],
          '水路56列' => [4, 5],
          _ => List.generate(9, (i) => i)
        };
        final expected = shortcut == '重置批量选择'
            ? <(int, int)>{}
            : {
                for (final r in rows)
                  for (final c in columns) (r, c)
              };
        h.expect(
            painter.selectedCells.length == expected.length &&
                painter.selectedCells.containsAll(expected),
            'Quick selection coordinates differ from original pool shortcuts');
      });
    }
    for (final label in ['按类型铲除', '铲除全部植物', '批量种植', '批量模仿', '完成批量操作']) {
      await h.run('batch.$label', '批量操作按钮：$label', () async {
        await fresh();
        await seed();
        if (label == '批量种植') await h.tap('向日葵');
        await h.tap('批量选择');
        await cell();
        await h.tap('懒人布局');
        await h.tapElement(
            h.find((w) => w is Text && (w.data ?? '').startsWith('批量操作 ·')));
        await h.tap(label);
        if (label == '按类型铲除' || label == '铲除全部植物')
          h.expect(session.document.pieces.isEmpty,
              'Batch deletion did not remove selected cell');
        if (label == '批量种植')
          h.expect(session.document.pieces.any((p) => p.type == 'sunflower'),
              'Batch planting did not replace cell');
        if (label == '批量模仿')
          h.expect(session.document.pieces.single.effects.contains('模仿者'),
              'Batch imitation did not apply');
        if (label == '完成批量操作') {
          final painter = (h
                  .find((w) => w is CustomPaint && w.painter is BoardPainter)
                  .widget as CustomPaint)
              .painter as BoardPainter;
          h.expect(
              painter.selectedCells.isEmpty, 'Finish did not clear selection');
        }
      });
    }
    await h.run('board.clear', '一键清空，不二次确认，支持撤销与重做', () async {
      await fresh();
      await seed();
      final before = session.document.fingerprint;
      await h.tap('清空');
      h.expect(h.all((w) => w is AlertDialog).isEmpty,
          'Clear must execute without confirmation');
      h.expect(session.document.pieces.isEmpty && session.canUndo,
          'Clear did not empty board or preserve undo');
      session.undo();
      h.expect(
          session.document.fingerprint == before, 'Undo clear lost content');
      session.redo();
      h.expect(session.document.pieces.isEmpty, 'Redo clear did not execute');
    });
    await h.run('board.delete-selected', '删除选中对象按钮', () async {
      await fresh();
      await seed();
      await h.tap('单个选择');
      await cell();
      await h.tap('删除选中对象');
      h.expect(
          session.document.pieces.isEmpty, 'Selected object deletion failed');
    });
    await h.run('search.card', '底部搜索卡片已移除，原分类卡片仍可用', () async {
      await fresh();
      h.expect(h.all((w) => w is Text && w.data == '搜索卡片').isEmpty,
          'Removed search expansion remains visible');
      h.expect(
          h
                  .all((w) => w.key == const ValueKey('original-card-pea'))
                  .isNotEmpty &&
              h
                  .all(
                      (w) => w.key == const ValueKey('original-card-sunflower'))
                  .isNotEmpty,
          'Removing search must retain normal category cards');
    });
    for (final action in ['花盆', '荷叶', '搭梯', '碾花盆', '炸荷叶', '破南瓜']) {
      await h.run('action.$action', '一键布局：$action', () async {
        await fresh();
        await h.tap('坚果墙');
        await cell();
        await h.tap('南瓜头');
        await cell();
        await h.tap('豌豆射手');
        await cell(2, 1);
        if (action == '碾花盆' || action == '炸荷叶') {
          await h.tap('花盆');
          await cell();
          await h.tap('睡莲');
          await cell(2, 1);
        }
        final before = session.document.fingerprint;
        await h.tap('懒人布局');
        await h.tap(action);
        if (action == '花盆')
          h.expect(
              session.document.pieces
                  .any((p) => p.type == 'pot' && p.row == 0 && p.col == 0),
              'Support action did not add flowerpot');
        if (action == '荷叶')
          h.expect(
              session.document.pieces
                  .any((p) => p.type == 'lily' && p.row == 2 && p.col == 1),
              'Support action did not add lily');
        if (action == '搭梯')
          h.expect(session.document.pieces.any((p) => p.type == 'ladder'),
              'Ladder action did not add ladder to pumpkin-covered wallnut');
        if (action == '破南瓜')
          h.expect(
              session.document.pieces
                      .firstWhere((p) => p.type == 'pumpkin')
                      .frameRow ==
                  2,
              'Broken pumpkin appearance did not change');
        if (action == '碾花盆' || action == '炸荷叶')
          h.expect(session.document.fingerprint == before,
              'Original no-op support action unexpectedly changed supports');
      });
    }

    for (final scope in ['南瓜', '荷叶', '花盆', '非紫卡植物', '全部植物']) {
      await h.run('imitate.$scope', '一键模仿：$scope', () async {
        await fresh();
        var column = 0;
        for (final card in ['南瓜头', '睡莲', '花盆', '豌豆射手']) {
          await h.tap(card);
          await cell(0, column++);
        }
        await h.tap('懒人布局');
        await h.tap(scope, index: scope == '荷叶' || scope == '花盆' ? 1 : 0);
        h.expect(session.document.pieces.any((p) => p.effects.contains('模仿者')),
            'Imitation must change fixture');
      });
    }
    for (final display in Formation().display.keys) {
      await h.run('display.$display', '显示选项：$display', () async {
        await fresh('选项设置');
        final before = session.document.display[display]!;
        final id = <String, String>{
          '泥土': 'cSoil',
          '阳光': 'rSeed',
          '卡槽': 'rSeed',
          '小推车': 'rClear',
          '脑子': 'rBrain',
          '继续标识': 'rCtc'
        }[display];
        if (id != null) {
          await h.tapElement(h.find((w) => w.key == ValueKey('original-$id')));
          h.expect(session.document.display[display] == !before,
              'Display checkbox did not toggle');
          await h.screenshot('display.$display.toggled');
          await h.tapElement(h.find((w) => w.key == ValueKey('original-$id')));
        } else if (display == '迷雾') {
          await h.choose<int>(1,
              where: (w) => w.key == const ValueKey('original-lFog'));
          h.expect(session.document.display['迷雾'] == true,
              'Fog selection did not enable fog rendering');
          await h.screenshot('display.$display.toggled');
          await h.choose<int>(0,
              where: (w) => w.key == const ValueKey('original-lFog'));
        } else {
          await h.tap('对象属性与扩展工具');
          await Future<void>.delayed(const Duration(milliseconds: 350));
          await h.tapElement(h.find((w) =>
              w is SwitchListTile &&
              w.title is Text &&
              (w.title as Text).data == display));
          h.expect(session.document.display[display] == !before,
              'Extended display toggle did not update');
          await h.screenshot('display.$display.toggled');
          await h.tapElement(h.find((w) =>
              w is SwitchListTile &&
              w.title is Text &&
              (w.title as Text).data == display));
        }
        h.expect(session.document.display[display] == before,
            'Display option did not restore');
      });
    }
    for (var fog = 0; fog <= 10; fog++) {
      await h.run('fog.$fog', '原站迷雾列数：$fog', () async {
        await fresh('选项设置');
        await h.choose<int>(fog,
            where: (w) => w.key == const ValueKey('original-lFog'));
        h.expect(
            session.document.fogColumns == fog &&
                session.document.display['迷雾'] == (fog > 0),
            'Fog count and visible state disagree');
      });
    }
    for (final input in ['12345', '100000000', 'abc', '-1']) {
      final valid = input == '12345';
      await h.run(
          'sun.${valid ? 'valid' : input == '100000000' ? 'invalid' : input == 'abc' ? 'nonnumeric' : 'negative'}',
          '阳光输入及改阳光按钮：$input', () async {
        await fresh('选项设置');
        await h.enterText(h.find((w) => w is EditableText), input);
        h.expect(session.document.sunValue == 9990,
            'Typing sunshine must wait for apply button');
        await h.tapElement(
            h.find((w) => w.key == const ValueKey('original-bSun')));
        h.expect(session.document.sunValue == (valid ? 12345 : 9990),
            'Sun input validation/application differs');
        if (!valid)
          h.expect(
              h
                  .all((w) => w is Text && (w.data ?? '').contains('请输入范围内'))
                  .isNotEmpty,
              'Invalid sun input has no feedback');
      });
    }
    await h.run('original.change-map', '原站更换地图按钮导航设置', () async {
      await fresh();
      await h.tapElement(
          h.find((w) => w.key == const ValueKey('original-change-map')));
      h.expect(
          h.all((w) => w.key == const ValueKey('original-lMap')).isNotEmpty,
          'Change-map button did not open settings');
    });
    await h.run('original.transfer-clear', '清空输入保留实时输出且无清空输出按钮', () async {
      await fresh();
      await seed();
      await h.tap('载入导出');
      final output = h
          .find((w) => w.key == const ValueKey('formation-live-output'))
          .widget as TextField;
      final input =
          h.all((w) => w is EditableText).first.widget as EditableText;
      input.controller.text = 'nonempty-input';
      final before = output.controller!.text, fp = session.document.fingerprint;
      await h.tap('清空输入');
      h.expect(
          input.controller.text.isEmpty && output.controller!.text == before,
          'Clearing input changed automatic output');
      h.expect(
          h
              .all((w) => w is Text && (w.data == '清空输出' || w.data == '清空'))
              .isEmpty,
          'Output clear control remains');
      h.expect(
          session.document.fingerprint == fp, 'Clearing input changed board');
    });
    await h.run('transfer.roundtrip', '实时Toolkit输出、复制与载入', () async {
      await fresh();
      await seed();
      await h.tap('载入导出');
      final output = h
          .find((w) => w.key == const ValueKey('formation-live-output'))
          .widget as TextField;
      final input =
          h.all((w) => w is EditableText).first.widget as EditableText;
      final text = output.controller!.text;
      h.expect(
          output.readOnly && FormationExchange.decode(text).pieces.length == 1,
          'Automatic output must encode current placement and be readonly');
      await h
          .tapElement(h.find((w) => w.key == const ValueKey('formation-copy')));
      h.expect(clipboard == text, 'Copy must write exact automatic output');
      input.controller.text = text;
      await h.tap('载入');
      h.expect(session.document.pieces.length == 1, 'Load must restore board');
      await h.tap('清空输入');
      h.expect(
          input.controller.text.isEmpty && output.controller!.text.isNotEmpty,
          'Clearing input must preserve live output');
    });
    await h.run('transfer.invalid', '无效字符串保留当前阵型', () async {
      await fresh('载入导出');
      final fingerprint = session.document.fingerprint;
      (h.find((w) => w is EditableText).widget as EditableText)
          .controller
          .text = 'invalid-array-string';
      await h.tap('载入');
      h.expect(session.document.fingerprint == fingerprint,
          'Invalid load mutated document');
      h.expect(
          h.all((w) => w is Text && (w.data ?? '').contains('载入失败')).isNotEmpty,
          'Missing failure feedback');
    });
    for (final poker in [false, true]) {
      for (final ratio in [1.0, .75, 2 / 3, .5]) {
        for (final background in [true, false]) {
          await h.run(
              'export.${poker ? 'poker' : 'png'}.${ratio.toStringAsFixed(3)}.$background',
              'PNG倍率 $ratio 背景 $background 扑克等宽 $poker（内存文件平台）', () async {
            await fresh();
            await seed();
            await h.tap('载入导出');
            await h.choose<double>(ratio);
            if (!background)
              await h.tapElement(h.find((w) =>
                  w is Checkbox &&
                  w.key != const ValueKey('original-cPokerBack')));
            if (poker)
              await h.tapElement(h
                  .find((w) => w.key == const ValueKey('original-cPokerBack')));
            final before = saved.length;
            await h.tap('导出 PNG 图片');
            await h.settle();
            h.expect(saved.length == before + 1,
                'PNG export did not call file platform');
            final bytes = await savedBytes();
            final codec = await ui.instantiateImageCodec(bytes);
            final image = (await codec.getNextFrame()).image;
            h.expect(
                image.width == ((poker ? 917 : 800) * ratio).round() &&
                    image.height == (600 * ratio).round(),
                'Wrong PNG dimensions');
            final rgba =
                await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            h.expect(rgba!.getUint8(3) == (background ? 255 : 0),
                'PNG corner alpha does not match background toggle');
            h.expect(
                saved.last['mime'] == 'image/png', 'PNG MIME type differs');
            await File(
                    '${output.path}/export-${poker ? 'poker' : 'game'}-${ratio.toStringAsFixed(3)}-$background.png')
                .writeAsBytes(bytes);
            image.dispose();
            codec.dispose();
          });
        }
      }
    }
    await h.run('card.capacity-remove', '卡槽10张上限与删除', () async {
      await fresh('卡槽选卡');
      final plants =
          ObjectSpec.all.where((s) => s.category == '植物').take(11).toList();
      for (final card in plants) {
        await h.tap(card.name);
      }
      h.expect(
          session.document.seedSlots.length == 10, 'Card capacity must be ten');
      await h.tap('× ');
      h.expect(
          session.document.seedSlots.length == 9, 'Remove must delete a slot');
    });
    const sourceMirrorScales = [1.0, .75, 2 / 3, .5, 1.5, 2.0];
    for (var index = 0; index < sourceMirrorScales.length; index++) {
      final scale = sourceMirrorScales[index];
      await h.run('mirror.create.$index', '原站直接创建镜像按钮：$scale', () async {
        await fresh('镜像窗口');
        final button = h.all((w) => w.key == ValueKey('original-clone-$index'));
        if (button.isEmpty)
          throw UnimplementedError(
              'Original mirror creation button $index is not exposed');
        await h.tapElement(button.single);
        final menu = h
            .find((w) =>
                w is DropdownButton<double> &&
                w.key == const ValueKey('mirror-scale-0'))
            .widget as DropdownButton<double>;
        h.expect(
            menu.value == scale, 'Direct mirror creation chose wrong scale');
        h.expect(
            h
                    .all((w) => w is CustomPaint && w.painter is BoardPainter)
                    .length ==
                2,
            'Direct creation did not add a mirror');
      });
    }
    for (final scale in [1.0, .75, 2 / 3, .5, 1.5, 2.0]) {
      await h.run('mirror.scale.${scale.toStringAsFixed(3)}', '镜像倍率：$scale',
          () async {
        await fresh('镜像窗口');
        await h.tap('创建镜像');
        await h.choose<double>(scale,
            where: (w) => w.key == const ValueKey('mirror-scale-0'));
        await h.tapElement(h.find((w) =>
            w is Checkbox && w.key == const ValueKey('mirror-background-0')));
        await h.screenshot('mirror.scale.${scale.toStringAsFixed(3)}.open');
        await h.tapElement(
            h.find((w) => w is IconButton && w.tooltip == '关闭镜像 1'));
        h.expect(
            h.all((w) => w.key == const ValueKey('mirror-scale-0')).isEmpty,
            'Mirror close failed');
      });
    }
    await h.run('mirror.snapshot', '镜像快照不随源变化', () async {
      await fresh();
      await seed();
      await h.tap('镜像窗口');
      await h.tap('创建镜像');
      await h.tap('图鉴选卡');
      await h.tap('清空');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      h.expect(session.document.pieces.isEmpty, 'Source clear did not execute');
      final painters = h
          .all((w) => w is CustomPaint && w.painter is BoardPainter)
          .map((e) => (e.widget as CustomPaint).painter as BoardPainter)
          .toList();
      h.expect(
          painters.length == 2 && painters.last.document.pieces.length == 1,
          'Mirror snapshot changed with source');
    });
    await h.run('mirror.export', '导出镜像（内存文件平台）', () async {
      await fresh();
      await seed();
      await h.tap('镜像窗口');
      await h.tap('创建镜像');
      final before = saved.length;
      await h.tap('导出镜像 1');
      h.expect(saved.length == before + 1, 'Mirror export did not save PNG');
      final codec = await ui.instantiateImageCodec(await savedBytes());
      final image = (await codec.getNextFrame()).image;
      h.expect(image.width == 400 && image.height == 300,
          'Default mirror export wrong size');
      image.dispose();
      codec.dispose();
    });
    await h.run('mirror.export.poker', '扑克宽镜像导出应为917倍率宽', () async {
      await fresh('镜像窗口');
      await h.tapElement(
          h.find((w) => w.key == const ValueKey('original-cPokerBack')));
      await h.tapElement(
          h.find((w) => w.key == const ValueKey('original-clone-3')));
      final before = saved.length;
      await h.tap('导出镜像 1');
      h.expect(saved.length == before + 1, 'Poker mirror export did not save');
      final codec = await ui.instantiateImageCodec(await savedBytes());
      final image = (await codec.getNextFrame()).image;
      h.expect(image.width == (917 * .5).round() && image.height == 300,
          'Poker mirror PNG width/height differs');
      image.dispose();
      codec.dispose();
    });
    await h.run('mirror.limit', '镜像三个上限', () async {
      await fresh('镜像窗口');
      for (var i = 0; i < 4; i++) {
        await h.tap('创建镜像');
      }
      h.expect(
          h
                  .all((w) =>
                      w is DropdownButton<double> &&
                      w.key.toString().contains('mirror-scale'))
                  .length ==
              3,
          'Mirror count must cap at three');
    });
    await h.run('transfer.pvzf1', '旧PVZF1仍可载入但不再显示获取按钮', () async {
      await fresh();
      await seed();
      final legacy = ProjectCodec.appString(session.document);
      session.execute(
          'legacy fixture clear', session.document.copy(pieces: []));
      await h.tap('载入导出');
      (h.all((w) => w is EditableText).first.widget as EditableText)
          .controller
          .text = legacy;
      await h.tap('载入');
      h.expect(session.document.pieces.length == 1,
          'Legacy PVZF1 input no longer accepted');
      h.expect(h.all((w) => w is Text && w.data == '获取 PVZF1').isEmpty,
          'Legacy output button remains');
    });
    await h.run('transfer.project', '项目导出并重新导入（内存文件平台）', () async {
      await fresh();
      await seed();
      await h.tap('载入导出');
      final before = session.document.fingerprint;
      await h.tap('导出 / 另存阵图');
      await h.tap(FormationFormat.project.label);
      await h.tap('选择保存位置');
      h.expect(saved.isNotEmpty, 'Project did not save');
      picked = await savedBytes();
      await h.tap('导入阵图文件');
      if (h.all((w) => w is Text && w.data == '确认').isNotEmpty)
        await h.tap('确认');
      h.expect(
          session.document.fingerprint == before, 'Project roundtrip differs');
    });
    await h.run('history.undo', '撤销按钮', () async {
      await fresh();
      await seed();
      await h.tap('撤销');
      h.expect(session.document.pieces.isEmpty, 'Undo did not revert planting');
    });
    await h.run('history.redo', '重做按钮', () async {
      await fresh();
      await seed();
      await h.tap('撤销');
      await h.tap('重做');
      h.expect(
          session.document.pieces.length == 1, 'Redo did not restore planting');
    });
    await h.run('session.flush-fromDraft', '自动存档落盘与重开，关闭后不保留撤销栈', () async {
      await fresh();
      await seed();
      await session.flush();
      final archive = (await repo.listArchives())
          .firstWhere((a) => a.id == session.sourceArchiveId);
      final document = Formation.fromJson(archive.document);
      final restored = EditorSession(repo,
          document: document,
          id: archive.id,
          name: archive.name,
          sourceArchiveId: archive.id,
          savedFingerprint: document.fingerprint);
      h.expect(restored.document.fingerprint == session.document.fingerprint,
          'Persisted archive differs');
      h.expect(
          restored.sourceArchiveId == session.sourceArchiveId &&
              !restored.canUndo &&
              (await repo.listDrafts()).isEmpty,
          'Reopened archive identity/history differs or legacy drafts remain');
      restored.dispose();
    });
    await h.run('session.readOnly', '只读模式禁止命令和撤销重做', () async {
      await fresh();
      await seed();
      final before = session.document.fingerprint;
      session.readOnly = true;
      h.expect(!session.execute('forbidden', Formation()),
          'Readonly execute was allowed');
      session.undo();
      session.redo();
      h.expect(
          session.document.fingerprint == before &&
              !session.canUndo &&
              !session.canRedo,
          'Readonly state changed');
      await mount();
      await h.tap('种植');
      await cell(0, 1);
      h.expect(
          session.document.fingerprint == before, 'Readonly UI modified board');
      session.readOnly = false;
    });
  } catch (e, stack) {
    stderr.writeln('Harness fatal: $e\n$stack');
    h.cases.add({
      'id': 'harness.fatal',
      'status': 'fail',
      'error': '$e',
      'stack': '$stack'
    });
  } finally {
    await h.report();
    await session.flush();
    await repo.close();
    stdout.writeln('Report: ${output.path}/report.json');
    exit(h.cases.any((c) => c['status'] != 'pass') ? 1 : 0);
  }
}
