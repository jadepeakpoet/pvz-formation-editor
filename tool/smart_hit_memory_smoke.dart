import 'dart:io';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/shovel_targets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OriginalAssets.ensureLoaded();
  final document = Formation(pieces: List.generate(5000, (i) => Piece(
      id: '$i', type: 'pea', row: i % 6, col: i % 9, layer: 10)));
  final before = OriginalAssets.images.bytes;
  for (var i = 0; i < 100; i++) {
    ShovelTargets.at(document, const Offset(-100, -100), '智能');
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));
  if (OriginalAssets.images.bytes != before) {
    throw StateError('Hit testing must not decode plant textures');
  }
  stdout.writeln('PASS repeated dense hit testing schedules no plant image decoding');
  exit(0);
}
