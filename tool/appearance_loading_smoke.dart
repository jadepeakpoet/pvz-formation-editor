import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/editor/sprite_presentation.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

bool same(Uint8List a, Uint8List b) =>
    a.length == b.length &&
    Iterable.generate(a.length).every((i) => a[i] == b[i]);

Future<Uint8List> render(Piece piece, SpritePresentation presentation) async {
  final document = Formation(
    mapId: 'day',
    pieces: [piece],
    display: {'卡槽': false, '阳光': false, '网格': false, '坐标': false},
  );
  final size = BoardGeometry(document).size;
  final recorder = ui.PictureRecorder();
  BoardPainter(
    document: document,
    spritePresentation: presentation,
    background: false,
    helpers: false,
    paintSunValue: false,
  ).paint(ui.Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.ceil(), size.height.ceil());
  try {
    final bytes = (await image.toByteData())!;
    return Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final errors = <String>[];
  FlutterError.onError = (e) => errors.add(e.exceptionAsString());
  try {
    await OriginalAssets.ensureLoaded();
    final old = Piece(id: 'nut', type: 'wallnut', row: 1, col: 1, layer: 10);
    final next = old.copy(frameCol: 2);
    final gate = Completer<void>();
    final loaded = Completer<void>();
    var loads = 0;
    final presentation = SpritePresentation(
      load: (piece) async {
        loads++;
        await gate.future;
        await OriginalAssets.ensurePieceImages([piece]);
        loaded.complete();
      },
    );
    await OriginalAssets.ensurePieceImages([old]);
    check(!OriginalAssets.pieceImagesReady(next), 'Target starts cold');
    final before = await render(old, presentation);
    final waiting = await render(next, presentation);
    check(
      same(before, waiting),
      'Cold target preserves the exact prior pixels',
    );
    OriginalAssets.images.trim(minimumAge: Duration.zero, targetBytes: 0);
    check(
      same(before, await render(next, presentation)),
      'Cache pressure preserves the outgoing frame while loading',
    );
    check(loads == 1, 'Repeated paints coalesce the same frame request');
    check(next.frameCol == 2, 'Presentation never changes the edited model');
    gate.complete();
    await loaded.future;
    final after = await render(next, presentation);
    check(
      !same(before, after),
      'Ready target switches to the requested appearance',
    );
    presentation.clear();
    OriginalAssets.images.trim(minimumAge: Duration.zero, targetBytes: 0);
    check(OriginalAssets.images.isEmpty, 'Transition leases are released');

    final ready = <int>{0};
    final requests = <int, Completer<void>>{};
    var held = 0;
    final rapid = SpritePresentation(
      isReady: (p) => ready.contains(p.frameCol),
      load: (p) => (requests[p.frameCol] ??= Completer<void>()).future,
      retain: (_) {
        held++;
        return () {
          held--;
        };
      },
    );
    rapid.resolve(old);
    check(
      rapid.resolve(next)!.frameCol == 0 && held == 1,
      'First pending appearance retains the prior frame',
    );
    final latest = old.copy(frameCol: 3, col: 4, flipped: true);
    check(
      rapid.resolve(latest)!.frameCol == 0 && held == 1,
      'Rapid changes keep a single outgoing lease',
    );
    ready.add(2);
    requests[2]!.complete();
    await Future<void>.delayed(Duration.zero);
    final pending = rapid.resolve(latest)!;
    check(
      pending.frameCol == 0 && pending.col == 4 && pending.flipped,
      'Out-of-order completion never shows a stale frame or undoes movement',
    );
    ready.add(3);
    requests[3]!.complete();
    await Future<void>.delayed(Duration.zero);
    check(
      rapid.resolve(latest)!.frameCol == 3 && held == 0,
      'Latest requested appearance wins and releases retained images',
    );
    ready.remove(2);
    rapid.resolve(next);
    rapid.retainOnly(const []);
    check(held == 0, 'Removing a plant releases pending transition resources');
    rapid.clear();

    final mimic = old.copy(effects: {'模仿者'});
    await OriginalAssets.ensurePieceImages([old]);
    check(
      !OriginalAssets.pieceImagesReady(mimic),
      'Imitation waits for its recolored layers as well as normal images',
    );
    await OriginalAssets.ensurePieceImages([mimic]);
    check(
      OriginalAssets.pieceImagesReady(mimic),
      'All imitation layers become ready',
    );
    final gloom = Piece(
      id: 'gloom',
      type: 'gloom',
      row: 1,
      col: 2,
      layer: 10,
      frameRow: 1,
    );
    check(
      !OriginalAssets.pieceImagesReady(gloom),
      'Multi-part plant is not prematurely considered ready',
    );
    await OriginalAssets.ensurePieceImages([gloom]);
    check(
      OriginalAssets.pieceImagesReady(gloom),
      'Body and addon layers load together',
    );
    check(
      (OriginalAssets.resourceStats()['fullSpriteSheets'] as List).isEmpty,
      'Transitions use sliced frames, never full sprite sheets',
    );
    check(errors.isEmpty, 'No framework errors: $errors');
    stdout.writeln(
      jsonEncode({
        'status': 'pass',
        'pixelIdenticalWhileLoading': true,
        'rapidChangesLatestWins': true,
        'outgoingImagesReleased': true,
        'imitationAndAddonsReady': true,
        'errors': errors,
      }),
    );
    exit(0);
  } catch (e, st) {
    stderr.writeln('$e\n$st\n$errors');
    exit(1);
  }
}
