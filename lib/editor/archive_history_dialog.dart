import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../domain/formation.dart';
import '../platform/app_language.dart';
import '../storage/formation_repository.dart';
import 'board_painter.dart';

typedef ArchiveHistorySnapshot = ({
  ArchiveRecord current,
  List<ArchiveVersion> versions,
});

Future<void> showArchiveHistoryDialog(BuildContext context,
        {required ArchiveHistorySnapshot snapshot,
        Future<ArchiveHistorySnapshot> Function(ArchiveVersion)? onRestore}) =>
    showDialog<void>(
        context: context,
        builder: (_) =>
            _ArchiveHistoryDialog(snapshot: snapshot, onRestore: onRestore));

class _ArchiveHistoryDialog extends StatefulWidget {
  final ArchiveHistorySnapshot snapshot;
  final Future<ArchiveHistorySnapshot> Function(ArchiveVersion)? onRestore;
  const _ArchiveHistoryDialog({required this.snapshot, this.onRestore});
  @override
  State<_ArchiveHistoryDialog> createState() => _ArchiveHistoryDialogState();
}

class _ArchiveHistoryDialogState extends State<_ArchiveHistoryDialog> {
  late ArchiveHistorySnapshot snapshot = widget.snapshot;
  final versionScroll = ScrollController();
  String? selectedId;
  bool busy = false;
  String? error;

  List<ArchiveVersion> get versions => snapshot.versions
      .where((version) => version.archiveId == snapshot.current.id)
      .toList();
  ArchiveVersion? get selected {
    for (final version in versions) {
      if (version.id == selectedId) return version;
    }
    return null;
  }

  String timestamp(DateTime value) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  void select(String? id) {
    if (busy) return;
    setState(() {
      selectedId = id;
      error = null;
    });
  }

  Future<void> restore() async {
    final version = selected;
    final callback = widget.onRestore;
    if (busy || version == null || callback == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final updated = await callback(version);
      if (updated.current.id != snapshot.current.id) {
        throw StateError('历史版本不属于当前存档');
      }
      if (!mounted) return;
      setState(() {
        snapshot = updated;
        selectedId = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && versionScroll.hasClients) versionScroll.jumpTo(0);
      });
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget versionRow({
    required Key key,
    required String name,
    required DateTime date,
    required String label,
    required bool active,
    required VoidCallback choose,
  }) =>
      Semantics(
          selected: active,
          button: true,
          child: InkWell(
              key: key,
              onTap: busy ? null : choose,
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                      color:
                          active ? const Color(0xffd7e4cc) : Colors.transparent,
                      border: Border(
                          left: BorderSide(
                              width: 3,
                              color: active
                                  ? const Color(0xff456b4e)
                                  : Colors.transparent))),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(label,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600))),
                          if (active)
                            const Icon(Icons.check_circle,
                                color: Color(0xff456b4e), size: 16),
                        ]),
                        const SizedBox(height: 4),
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(timestamp(date),
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xff63755f))),
                      ]))));

  Widget versionList() {
    final prior = versions;
    return DecoratedBox(
        decoration: BoxDecoration(
            color: const Color(0xffedf1e6),
            borderRadius: BorderRadius.circular(8)),
        child: SingleChildScrollView(
            controller: versionScroll,
            child: Column(children: [
              versionRow(
                  key: const ValueKey('archive-history-current'),
                  name: snapshot.current.name,
                  date: snapshot.current.updatedAt,
                  label: AppLanguage.text('当前版本'),
                  active: selected == null,
                  choose: () => select(null)),
              for (var i = 0; i < prior.length; i++)
                versionRow(
                    key: ValueKey('archive-history-version-${prior[i].id}'),
                    name: prior[i].name,
                    date: prior[i].createdAt,
                    label: '${AppLanguage.text('历史版本')} ${prior.length - i}',
                    active: selectedId == prior[i].id,
                    choose: () => select(prior[i].id)),
              if (prior.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(AppLanguage.text('没有更早的历史版本。'),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xff63755f)))),
            ])));
  }

  Widget preview() {
    final version = selected;
    final document =
        Formation.fromJson(version?.document ?? snapshot.current.document);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(version?.name ?? snapshot.current.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(AppLanguage.text(document.map.name),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Color(0xff63755f))),
      const SizedBox(height: 8),
      ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: AspectRatio(
              aspectRatio: 4 / 3,
              child: CustomPaint(
                  key: const ValueKey('archive-history-preview'),
                  painter: BoardPainter(document: document, helpers: false)))),
    ]);
  }

  @override
  void dispose() {
    versionScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: Dialog(
          key: const ValueKey('archive-history-dialog'),
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: const Color(0xfff4f5ed),
          child: SizedBox(
              width: 800,
              height: math.min(660, MediaQuery.sizeOf(context).height - 32),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(AppLanguage.text('历史版本'),
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600))),
                          TextButton(
                              key: const ValueKey('archive-history-close'),
                              onPressed: busy
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: Text(AppLanguage.text('关闭'))),
                        ]),
                        Text(snapshot.current.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xff63755f))),
                        const SizedBox(height: 12),
                        Expanded(
                            child: LayoutBuilder(builder: (_, constraints) {
                          if (constraints.maxWidth < 560) {
                            return Column(children: [
                              SizedBox(
                                  height:
                                      math.min(200, constraints.maxHeight * .5),
                                  child: FittedBox(
                                      child: SizedBox(
                                          width: 360, child: preview()))),
                              const SizedBox(height: 12),
                              Expanded(child: versionList()),
                            ]);
                          }
                          return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 244, child: versionList()),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: LayoutBuilder(
                                        builder: (_, previewConstraints) =>
                                            FittedBox(
                                                alignment: Alignment.topCenter,
                                                child: SizedBox(
                                                    width: previewConstraints
                                                        .maxWidth,
                                                    child: preview())))),
                              ]);
                        })),
                        const SizedBox(height: 10),
                        if (error != null)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text('${AppLanguage.text('恢复失败')}：$error',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.red))),
                        Text(
                            AppLanguage.text(widget.onRestore == null
                                ? '只读预览'
                                : '恢复会新增一个最新版本，原有历史保留。'),
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xff63755f))),
                        const SizedBox(height: 8),
                        Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton(
                                key: const ValueKey('archive-history-restore'),
                                onPressed: busy ||
                                        selected == null ||
                                        widget.onRestore == null
                                    ? null
                                    : restore,
                                child: Text(AppLanguage.text(
                                    busy ? '恢复中…' : '恢复此版本')))),
                      ])))));
}
