// Source CardKind behavior: three mutually exclusive, collapsible card groups.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pvz_formation_editor/main.dart' as app;
import 'package:pvz_formation_editor/editor/editor_session.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';
import 'parity_support.dart';

Future<void> main() async {
  ParityBinding();
  await OriginalAssets.ensureLoaded();
  final repo = await FormationRepository.open(':memory:');
  final session = EditorSession(repo, persistDraft: false);
  final boundary = GlobalKey();
  final h = ParityHarness(boundary,
      await Directory('${Directory.systemTemp.path}/pvz-catalog-categories').create(recursive: true));
  FlutterError.onError = h.errors.add;
  runApp(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
          home: app.EditorPage(
              session: session, continueArchive: (_) async {}))));
  await h.settle();
  await h.settle();
  final dynamic page =
      (h.find((w) => w is app.EditorPage) as StatefulElement).state;
  page.selectToolboxTab(2);
  await h.settle();
  final before = session.document.fingerprint;
  List<String> cards() => h
      .all((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('original-card-'))
      .map((e) => (e.widget.key as ValueKey<String>)
          .value
          .substring('original-card-'.length))
      .toList();
  void expectCards(List<String> expected, String reason) {
    final actual = cards();
    h.expect(
        actual.length == expected.length &&
            List.generate(actual.length, (i) => actual[i] == expected[i])
                .every((value) => value),
        '$reason: $actual');
  }

  const plants = [
    'pea',
    'sunflower',
    'cherry',
    'wallnut',
    'potato',
    'snow',
    'chomper',
    'repeater',
    'puff',
    'sunshroom',
    'fume',
    'gravebuster',
    'hypno',
    'scaredy',
    'ice',
    'doom',
    'lily',
    'squash',
    'threepea',
    'tangle',
    'jalapeno',
    'spikeweed',
    'torch',
    'tallnut',
    'seashroom',
    'plantern',
    'cactus',
    'blover',
    'splitpea',
    'starfruit',
    'pumpkin',
    'magnet',
    'cabbage',
    'pot',
    'kernel',
    'coffee',
    'garlic',
    'umbrella',
    'marigold',
    'melon',
    'gatling',
    'doubleSun',
    'gloom',
    'cattail',
    'winter',
    'goldmagnet',
    'spike',
    'cob',
  ];
  const zombies = [
    'zombie',
    'flag',
    'cone',
    'pole',
    'bucket',
    'newspaper',
    'screen',
    'football',
    'dancer',
    'backup',
    'ducky',
    'snorkel',
    'zomboni',
    'dolphin',
    'jack',
    'balloon',
    'digger',
    'pogo',
    'yeti',
    'bungee',
    'ladderZombie',
    'catapult',
    'gargantuar',
    'Redeyed_Gargantuar',
    'imp',
  ];
  const items = [
    'ladder',
    'grave',
    'rake',
    'Stripe',
    'crater',
    'ScaryPot',
    'SnowFlakes',
    'BungeeTarget',
    'Ice',
  ];
  for (final label in ['植物选卡', '僵尸选卡', '物品效果选卡']) {
    h.expect(h.all((w) => w is Text && w.data == label).length == 1,
        'Missing source category button: $label');
  }
  expectCards(plants, 'Plants should be the default expanded group');
  await h.tap('植物选卡');
  expectCards(const [], 'Clicking active group should collapse it');
  await h.tap('僵尸选卡');
  expectCards(zombies, 'Zombie group must use exact source list and order');
  await h.tap('物品效果选卡');
  expectCards(items, 'Items/effects should be one exact source group');
  await h.screenshot('catalog-items');
  await h.tap('物品效果选卡');
  expectCards(const [], 'Items group should also collapse on repeat click');
  await h.tap('植物选卡');
  expectCards(plants, 'Reopening plants must restore their source order');
  h.expect(session.document.fingerprint == before && session.undoDepth == 0,
      'Category browsing must not edit formation or history');
  h.expect(h.errors.isEmpty,
      h.errors.map((error) => error.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS default plant group, exact 48/25/9 source card lists, mutual exclusion, repeat collapse and unchanged board');
  runApp(const SizedBox.shrink());
  await h.settle();
  session.dispose();
  await repo.close();
  exit(0);
}
