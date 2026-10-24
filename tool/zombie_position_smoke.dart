import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/website_codec.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/library/library_presets.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OriginalAssets.ensureLoaded();
  for (final index in [59, 81, 303]) {
    final document = LibraryPresets.all[index].document;
    final copy = WebsiteCodec.decode(WebsiteCodec.encode(document));
    for (var i = 0; i < document.pieces.length; i++) {
      final original = BoardGeometry(document).pieceCenter(document.pieces[i]);
      final restored = BoardGeometry(copy).pieceCenter(copy.pieces[i]);
      check((original - restored).distance < .001,
          'Preset $index object $i changes position on code round trip');
    }
    final first = await exportPng(document, multiplier: .32);
    final second = await exportPng(copy, multiplier: .32);
    check(first.length == second.length &&
        Iterable<int>.generate(first.length).every((i) => first[i] == second[i]),
        'Preset $index has inconsistent exported pixels');
  }
  final dolphin = LibraryPresets.all[59].document;
  final piece = dolphin.pieces.singleWhere((p) => p.type == 'dolphin');
  check(BoardGeometry(dolphin).pieceCenter(piece) == const Offset(287, 262.5),
      'Legacy dolphin must use its left X and zombie row anchor');
  stdout.writeln('PASS: three complete layouts retain positions and rendered pixels');
  exit(0);
}
