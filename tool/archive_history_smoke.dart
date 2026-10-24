import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/editor/archive_history_dialog.dart';
import 'package:pvz_formation_editor/editor/board_painter.dart';
import 'package:pvz_formation_editor/editor/original_assets.dart';
import 'package:pvz_formation_editor/storage/formation_repository.dart';

class HistoryBinding extends WidgetsFlutterBinding {
  Size viewport = const Size(1000, 760);
  @override
  ViewConfiguration createViewConfigurationFor(RenderView view) =>
      ViewConfiguration(logicalConstraints: BoxConstraints.tight(viewport), physicalConstraints: BoxConstraints.tight(viewport), devicePixelRatio: 1);
}

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

List<Element> find(bool Function(Widget) predicate) {
  final result = <Element>[];
  void visit(Element element) {
    if (predicate(element.widget)) result.add(element);
    element.visitChildren(visit);
  }

  visit(WidgetsBinding.instance.rootElement!);
  return result;
}

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 170));
Future<void> tap(String key) async {
  final target = find((w) => w.key == ValueKey(key)).single;
  await Scrollable.ensureVisible(target, duration: Duration.zero);
  await settle();
  final box = target.renderObject as RenderBox;
  final point = box.localToGlobal(box.size.center(Offset.zero));
  GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: point, buttons: 1));
  GestureBinding.instance
      .handlePointerEvent(PointerUpEvent(pointer: 1, position: point));
  await settle();
}

Future<void> main() async {
  final binding = HistoryBinding();
  await OriginalAssets.ensureLoaded();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  final boundary = GlobalKey();
  final currentDocument = Formation(mapId: 'day', pieces: [
    Piece(id: 'current-plant', type: 'pea', row: 1, col: 1, layer: 10),
  ]);
  final oldDocument = Formation(mapId: 'pool', pieces: [
    Piece(id: 'old-plant', type: 'sunflower', row: 1, col: 1, layer: 10),
  ]);
  final current = ArchiveRecord(
      id: 'archive',
      name: 'Current formation',
      document: currentDocument.toJson(),
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 23));
  final old = ArchiveVersion(
      id: 'old',
      archiveId: 'archive',
      name: 'Old formation',
      note: '',
      tags: [],
      document: oldDocument.toJson(),
      createdAt: DateTime(2026, 10, 10));
  final unrelated = ArchiveVersion(
      id: 'foreign',
      archiveId: 'other',
      name: 'Other archive',
      note: '',
      tags: [],
      document: oldDocument.toJson(),
      createdAt: DateTime(2026, 10, 9));
  final removed = ArchiveVersion(
      id: 'removed-map',
      archiveId: current.id,
      name: 'Legacy formation',
      note: '',
      tags: [],
      document: {
        ...oldDocument.toJson(),
        'map': 'custom',
        'board': {'rows': 8, 'columns': 12}
      },
      createdAt: DateTime(2026, 10, 8));
  final initial = (current: current, versions: [old, unrelated, removed]);
  var mode = 'restore';
  var restoreCalls = 0;
  String? restoredId;
  Completer<ArchiveHistorySnapshot>? pending;
  void mount() {
    runApp(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
                colorScheme:
                    ColorScheme.fromSeed(seedColor: const Color(0xff456b4e))),
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        key: const ValueKey('open-history'),
                        child: const Text('Open'),
                        onPressed: () => showArchiveHistoryDialog(context,
                            snapshot: initial,
                            onRestore: mode == 'readonly'
                                ? null
                                : (version) async {
                                    restoreCalls++;
                                    restoredId = version.id;
                                    if (mode == 'error') {
                                      throw StateError('restore failed');
                                    }
                                    pending =
                                        Completer<ArchiveHistorySnapshot>();
                                    return pending!.future;
                                  })))))));
  }

  Formation preview() =>
      ((find((w) => w.key == const ValueKey('archive-history-preview'))
                  .single
                  .widget as CustomPaint)
              .painter as BoardPainter)
          .document;
  FilledButton restoreButton() =>
      find((w) => w.key == const ValueKey('archive-history-restore'))
          .single
          .widget as FilledButton;
  Future<void> screenshot(String kind) async {
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/pvz-archive-history-$kind.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  Future<void> close() async {
    await tap('archive-history-close');
    await settle();
  }

  mount();
  await settle();
  await tap('open-history');
  check(
      preview().fingerprint == currentDocument.fingerprint &&
          restoreButton().onPressed == null,
      'Current version must be first and cannot restore itself');
  check(
      find((w) => w.key == const ValueKey('archive-history-version-foreign'))
          .isEmpty,
      'Other archive versions must not be displayed');
  await tap('archive-history-version-old');
  check(preview().fingerprint == oldDocument.fingerprint && restoreCalls == 0,
      'Selecting history should preview without restoring');
  check(current.document.toString() == currentDocument.toJson().toString(),
      'Preview mutated current document');
  await screenshot('wide');
  await tap('archive-history-restore');
  check(
      restoreCalls == 1 &&
          restoredId == 'old' &&
          restoreButton().onPressed == null,
      'Restore should call selected version once and disable repeated operations');
  final dialog =
      find((w) => w.key == const ValueKey('archive-history-dialog')).single;
  await Navigator.of(dialog).maybePop();
  await settle();
  check(
      find((w) => w.key == const ValueKey('archive-history-dialog')).isNotEmpty,
      'Busy restore must block dismissal');
  check(
      (find((w) => w.key == const ValueKey('archive-history-close'))
                  .single
                  .widget as TextButton)
              .onPressed ==
          null,
      'Close must be disabled while restoring');
  final previous = ArchiveVersion(
      id: 'previous-current',
      archiveId: current.id,
      name: current.name,
      note: '',
      tags: [],
      document: current.document,
      createdAt: DateTime(2026, 10, 24));
  pending!.complete((
    current: ArchiveRecord(
        id: current.id,
        name: old.name,
        document: old.document,
        createdAt: current.createdAt,
        updatedAt: DateTime(2026, 10, 24)),
    versions: [previous, old]
  ));
  await settle();
  check(
      preview().fingerprint == oldDocument.fingerprint &&
          restoreButton().onPressed == null,
      'Restored current version must become selected top row');
  check(
      find((w) => w.key == const ValueKey('archive-history-version-old'))
                  .length ==
              1 &&
          find((w) =>
                  w.key ==
                  const ValueKey(
                      'archive-history-version-previous-current')).length ==
              1,
      'Existing history and previous current version must remain available');
  final currentBox =
      find((w) => w.key == const ValueKey('archive-history-current'))
          .single
          .renderObject as RenderBox;
  final previousBox = find((w) =>
          w.key == const ValueKey('archive-history-version-previous-current'))
      .single
      .renderObject as RenderBox;
  check(
      currentBox.localToGlobal(Offset.zero).dy <
          previousBox.localToGlobal(Offset.zero).dy,
      'New current version must appear above old versions');
  await close();

  mode = 'error';
  await tap('open-history');
  await tap('archive-history-version-old');
  await tap('archive-history-restore');
  check(
      find((w) => w is Text && (w.data ?? '').contains('restore failed'))
              .isNotEmpty &&
          preview().fingerprint == oldDocument.fingerprint &&
          restoreButton().onPressed != null,
      'Restore error must remain visible and preserve selected preview for retry');
  await close();

  mode = 'restore';
  await tap('open-history');
  final beforeRemoved = restoreCalls;
  await tap('archive-history-version-removed-map');
  check(
      find((w) => w.key == const ValueKey('archive-history-unsupported-map'))
              .isNotEmpty &&
          restoreButton().onPressed == null &&
          restoreCalls == beforeRemoved,
      'Removed maps must remain listed without being previewed or restored');
  await tap('archive-history-current');
  check(preview().fingerprint == currentDocument.fingerprint,
      'An unsupported old map must not break the valid current preview');
  await close();

  mode = 'readonly';
  binding.viewport = const Size(360, 640);
  binding.handleMetricsChanged();
  await tap('open-history');
  await tap('archive-history-version-old');
  check(
      preview().fingerprint == oldDocument.fingerprint &&
          restoreButton().onPressed == null,
      'Readonly history must allow previews without restoration');
  await screenshot('narrow');
  await close();
  check(errors.isEmpty,
      errors.map((error) => error.exceptionAsString()).join('\n'));
  stdout.writeln(
      'PASS archive history preview/current-first, append result, busy/cancel guard, errors, readonly,360px');
  runApp(const SizedBox.shrink());
  await settle();
  exit(0);
}
