import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/formation.dart';
import '../domain/formation_exchange.dart';
import '../editor/board_painter.dart';
import '../platform/game_bridge.dart';
import '../platform/game_backups.dart';
import '../platform/project_files.dart';
import '../storage/file_backups.dart';

/// Windows game integration is kept in the library's own dialog/window.
class GamePanel extends StatefulWidget {
  final Formation? target;
  final Future<void> Function(Formation) onArchive, onEdit;
  const GamePanel(
      {super.key, this.target, required this.onArchive, required this.onEdit});
  @override
  State<GamePanel> createState() => _GamePanelState();
}

class _GamePanelState extends State<GamePanel> {
  List<RunningGame> games = [];
  List<GameSaveFile> files = [];
  List<String> memoryBackups = [];
  RunningGame? selected;
  GameFormationSnapshot? snapshot;
  String? error, notice, lastMemoryBackup, lastFileBackup, restoredFile;
  bool busy = false;
  GameBackups? backups;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refresh() => run(() async {
        final found = await GameBridge.listGames();
        final oldPid = selected?.pid;
        selected = found.where((g) => g.pid == oldPid).firstOrNull ??
            found.firstOrNull;
        games = found;
        snapshot = null;
        lastMemoryBackup = null;
        lastFileBackup = null;
        restoredFile = null;
        memoryBackups =
            selected == null ? [] : await (await store()).list(selected!.pid);
        if (memoryBackups.isNotEmpty) lastMemoryBackup = memoryBackups.first;
        files = selected == null
            ? []
            : await GameBridge.listSaveFiles(selected!.pid);
        if (mounted) setState(() {});
      });

  Future<GameBackups> store() async {
    if (backups != null) return backups!;
    final directory = await getApplicationSupportDirectory();
    return backups = GameBackups(Directory('${directory.path}/game-backups'));
  }

  Future<void> read() => run(() async {
        snapshot = await GameBridge.readFormation(selected!.pid);
        files = await GameBridge.listSaveFiles(selected!.pid);
        if (mounted) setState(() {});
      });

  Future<void> apply() => run(() async {
        try {
          final result =
              await (await store()).apply(selected!.pid, widget.target!);
          snapshot = result.after;
          lastMemoryBackup = result.backupPath;
          memoryBackups = await (await store()).list(selected!.pid);
          notice = '阵型已写入游戏，原阵型已备份。';
        } on GameWriteFailure catch (e) {
          lastMemoryBackup = e.backupPath;
          rethrow;
        }
      });

  Future<void> undo() => run(() async {
        final result =
            await (await store()).undo(selected!.pid, lastMemoryBackup!);
        snapshot = result.after;
        lastMemoryBackup = result.backupPath;
        memoryBackups = await (await store()).list(selected!.pid);
        notice = '已恢复原阵型，恢复前的内容也已备份。';
      });

  Future<Uint8List> readSave(GameSaveFile file) async {
    final source = File(file.path);
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException('存档文件已变化，请刷新');
    }
    final before = await source.stat();
    if (before.size > FileBackups.maxBytes) {
      throw const FormatException('存档文件超过 8 MiB');
    }
    final bytes = await source.readAsBytes();
    final after = await source.stat();
    if (before.modified != after.modified ||
        before.size != after.size ||
        bytes.length != after.size) {
      throw const FileSystemException('游戏正在更新这个存档，请稍后重试');
    }
    return bytes;
  }

  Future<void> backupSave(GameSaveFile file, {bool saveAs = false}) =>
      run(() async {
        final bytes = await readSave(file);
        if (saveAs) {
          final name = file.path.replaceAll('\\', '/').split('/').last;
          final path =
              await ProjectFiles.save(name, bytes, 'application/octet-stream');
          if (path != null) notice = '存档已另存为：$path';
        } else {
          final directory = (await store()).directory;
          await directory.create(recursive: true);
          final path = '${directory.path}/save-${newId()}.bak';
          await FileBackups.replace(path, bytes);
          // Restore uses the same integrity manifest as all other file backups.
          await File('$path.json').writeAsString(
              jsonEncode({
                'schemaVersion': 1,
                'originalPath': file.path,
                'createdAt': DateTime.now().toUtc().toIso8601String(),
                'bytes': bytes.length,
                'crc32': GameBackups.checksum(bytes)
              }),
              flush: true);
          lastFileBackup = path;
          restoredFile = file.path;
          notice = '游戏存档已备份：$path';
        }
      });

  @override
  Widget build(BuildContext context) => Dialog(
      child: SizedBox(
          width: 780,
          height: 570,
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Expanded(
                          child: Text('Windows 游戏与存档',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w600))),
                      IconButton(
                          onPressed: busy ? null : refresh,
                          tooltip: '刷新',
                          icon: const Icon(Icons.refresh)),
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          tooltip: '关闭',
                          icon: const Icon(Icons.close))
                    ]),
                    const Text('原版 PvZ 1.0.0.1051 · 写入前自动备份原阵型',
                        style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 8),
                    if (busy) const LinearProgressIndicator(),
                    if (error != null)
                      ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 80),
                          child: SingleChildScrollView(
                              child: SelectableText(error!,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 12)))),
                    if (notice != null)
                      SelectableText(notice!,
                          style: const TextStyle(
                              color: Color(0xff376b50), fontSize: 12)),
                    Expanded(
                        child: games.isEmpty
                            ? const Center(
                                child: Text(
                                    '没有发现运行中的植物大战僵尸。\n请先启动原版 1.0.0.1051，再点击刷新。',
                                    textAlign: TextAlign.center))
                            : ListView(children: [
                                DropdownButton<int>(
                                    value: selected?.pid,
                                    isExpanded: true,
                                    items: games
                                        .map((g) => DropdownMenuItem(
                                            value: g.pid,
                                            child: Text(
                                                '${g.title} · ${g.version} · PID ${g.pid}')))
                                        .toList(),
                                    onChanged: busy
                                        ? null
                                        : (pid) async {
                                            selected = games.firstWhere(
                                                (g) => g.pid == pid);
                                            snapshot = null;
                                            lastMemoryBackup = null;
                                            lastFileBackup = null;
                                            restoredFile = null;
                                            memoryBackups = [];
                                            await run(() async {
                                              memoryBackups =
                                                  await (await store())
                                                      .list(selected!.pid);
                                              if (memoryBackups.isNotEmpty) {
                                                lastMemoryBackup =
                                                    memoryBackups.first;
                                              }
                                              files = await GameBridge
                                                  .listSaveFiles(selected!.pid);
                                            });
                                          }),
                                Wrap(spacing: 8, runSpacing: 4, children: [
                                  FilledButton(
                                      onPressed:
                                          busy || selected?.canRead != true
                                              ? null
                                              : read,
                                      child: const Text('读取游戏现场')),
                                  OutlinedButton(
                                      onPressed: busy ||
                                              widget.target == null ||
                                              selected?.canWrite != true
                                          ? null
                                          : apply,
                                      child: const Text('应用所选阵型到游戏')),
                                  OutlinedButton(
                                      onPressed:
                                          busy || lastMemoryBackup == null
                                              ? null
                                              : undo,
                                      child: const Text('撤销上次覆盖')),
                                ]),
                                if (memoryBackups.isNotEmpty)
                                  DropdownButton<String>(
                                      value: lastMemoryBackup,
                                      isExpanded: true,
                                      hint: const Text('选择要恢复的阵型备份'),
                                      items: memoryBackups
                                          .map((p) => DropdownMenuItem(
                                              value: p,
                                              child: Text(
                                                  p
                                                      .replaceAll('\\', '/')
                                                      .split('/')
                                                      .last,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 11))))
                                          .toList(),
                                      onChanged: busy
                                          ? null
                                          : (value) => setState(
                                              () => lastMemoryBackup = value)),
                                if (snapshot != null) ...[
                                  const SizedBox(height: 10),
                                  SizedBox(
                                      height: 180,
                                      child: Center(
                                          child: AspectRatio(
                                              aspectRatio: 4 / 3,
                                              child: CustomPaint(
                                                  painter: BoardPainter(
                                                      document:
                                                          snapshot!.formation,
                                                      helpers: false))))),
                                  Text(
                                      '${snapshot!.formation.map.name} · ${snapshot!.formation.pieces.length} 个对象'),
                                  Wrap(spacing: 8, children: [
                                    TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => run(() => widget
                                                .onEdit(snapshot!.formation)),
                                        child: const Text('在编辑器打开')),
                                    TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => run(() => widget.onArchive(
                                                snapshot!.formation)),
                                        child: const Text('加入我的存档')),
                                    TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => run(() async {
                                                  final text =
                                                      FormationExchange.encode(
                                                          snapshot!.formation);
                                                  await ProjectFiles.save(
                                                      '游戏现场.txt',
                                                      Uint8List.fromList(
                                                          utf8.encode(text)),
                                                      'text/plain');
                                                }),
                                        child: const Text('另存为 Toolkit 阵图')),
                                  ])
                                ],
                                const Divider(),
                                const Text('游戏存档文件',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600)),
                                if (files.isEmpty)
                                  const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Text('未找到游戏存档文件。')),
                                for (final file in files)
                                  ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(file.relativePath,
                                          style: const TextStyle(fontSize: 12)),
                                      subtitle: Text(
                                          '${file.size} 字节 · ${file.directory}',
                                          style: const TextStyle(fontSize: 11)),
                                      trailing: Wrap(children: [
                                        TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => backupSave(file),
                                            child: const Text('备份')),
                                        TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => backupSave(file,
                                                    saveAs: true),
                                            child: const Text('另存为'))
                                      ])),
                                if (lastFileBackup != null)
                                  OutlinedButton(
                                      onPressed: busy
                                          ? null
                                          : () => run(() async {
                                                final redo = await FileBackups
                                                    .restoreBackup(
                                                        lastFileBackup!,
                                                        restoredFile!);
                                                lastFileBackup = redo;
                                                notice = '已恢复游戏存档，覆盖前的文件也已备份。';
                                              }),
                                      child: const Text('恢复上次游戏存档备份')),
                              ])),
                  ]))));
}
