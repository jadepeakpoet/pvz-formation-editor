import '../widgets/app_dropdown.dart';
import '../widgets/clear_game_zombies_option.dart';
import '../platform/app_language.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/formation.dart';
import '../domain/formation_exchange.dart';
import '../domain/placement_layout.dart';
import '../editor/board_painter.dart';
import '../platform/game_bridge.dart';
import '../platform/game_writes.dart';
import '../platform/project_files.dart';
import '../storage/file_backups.dart';

/// Shared Windows game integration for the editor and archive library.
class GamePanel extends StatefulWidget {
  final Formation? target;
  final Future<void> Function(Formation) onArchive, onEdit;
  const GamePanel({
    super.key,
    this.target,
    required this.onArchive,
    required this.onEdit,
  });
  @override
  State<GamePanel> createState() => _GamePanelState();
}

class _GamePanelState extends State<GamePanel> {
  List<RunningGame> games = [];
  List<GameSaveFile> files = [];
  RunningGame? selected;
  GameFormationSnapshot? snapshot;
  String? error, notice, lastFileBackup, restoredFile;
  bool busy = false;
  bool clearZombiesOnApply = false;
  GameWrites? backups;
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
        lastFileBackup = null;
        restoredFile = null;
        files = selected == null
            ? []
            : await GameBridge.listSaveFiles(selected!.pid);
        if (mounted) setState(() {});
      });

  Future<GameWrites> store() async {
    if (backups != null) return backups!;
    final directory = await getApplicationSupportDirectory();
    return backups = GameWrites(Directory('${directory.path}/game-backups'));
  }

  Future<void> read({bool includeZombies = false}) => run(() async {
        snapshot = await GameBridge.readFormation(
          selected!.pid,
          includeZombies: includeZombies,
        );
        if (mounted) setState(() {});
      });

  Future<void> apply() => run(() async {
        snapshot = await (await store()).apply(selected!.pid, widget.target!,
            clearZombies: clearZombiesOnApply);
        final detail = PlacementLayout.prepare(
          widget.target!,
          includeZombies: true,
        ).notice;
        notice = '阵型已应用到游戏。${detail.isEmpty ? '' : ' $detail'}';
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
          final path = await ProjectFiles.save(
            name,
            bytes,
            'application/octet-stream',
          );
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
              'crc32': GameWrites.checksum(bytes),
            }),
            flush: true,
          );
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppLanguage.text('Windows 游戏与存档'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: busy ? null : refresh,
                      tooltip: AppLanguage.text('刷新'),
                      icon: const Icon(Icons.refresh),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: AppLanguage.text('关闭'),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  AppLanguage.text('原版 PvZ 1.0.0.1051 · 读取 / 注入当前游戏阵型'),
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 80),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        AppLanguage.text(error!),
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ),
                if (notice != null)
                  SelectableText(
                    AppLanguage.text(notice!),
                    style:
                        const TextStyle(color: Color(0xff376b50), fontSize: 12),
                  ),
                Expanded(
                  child: games.isEmpty
                      ? Center(
                          child: Text(
                            AppLanguage.text(
                              '没有发现运行中的植物大战僵尸。\n请先启动原版 1.0.0.1051，再点击刷新。',
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView(
                          children: [
                            AppDropdown<int>(
                              value: selected?.pid,
                              isExpanded: true,
                              items: games
                                  .map(
                                    (g) => DropdownMenuItem(
                                      value: g.pid,
                                      child: Text(
                                        '${g.title} · ${g.version} · PID ${g.pid}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: busy
                                  ? null
                                  : (pid) async {
                                      selected = games.firstWhere(
                                        (g) => g.pid == pid,
                                      );
                                      snapshot = null;
                                      lastFileBackup = null;
                                      restoredFile = null;
                                      await run(() async {
                                        files = await GameBridge.listSaveFiles(
                                          selected!.pid,
                                        );
                                      });
                                    },
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                FilledButton(
                                  onPressed: busy || selected?.canRead != true
                                      ? null
                                      : read,
                                  child: Text(AppLanguage.text('获取阵型')),
                                ),
                                OutlinedButton(
                                  onPressed: busy || selected?.canRead != true
                                      ? null
                                      : () => read(includeZombies: true),
                                  child: const Text('获取含僵尸布局'),
                                ),
                                if (widget.target != null)
                                  OutlinedButton.icon(
                                    onPressed:
                                        busy || selected?.canWrite != true
                                            ? null
                                            : apply,
                                    icon: const Icon(Icons.play_arrow_rounded, size: 17),
                                    key: const ValueKey('game-panel-apply'),
                                    label: Text(AppLanguage.text('应用阵型')),
                                  ),
                                if (widget.target != null)
                                  ClearGameZombiesOption(key: const ValueKey('game-panel-clear-zombies'),
                                      value: clearZombiesOnApply,
                                      onChanged: busy ? null : (value) => setState(() => clearZombiesOnApply = value)),
                              ],
                            ),
                            if (snapshot != null) ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 180,
                                child: Center(
                                  child: AspectRatio(
                                    aspectRatio: 4 / 3,
                                    child: CustomPaint(
                                      painter: BoardPainter(
                                        document: snapshot!.formation,
                                        helpers: false,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                AppLanguage.text(
                                  '${snapshot!.formation.map.name} · ${snapshot!.formation.pieces.length} 个对象',
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => run(
                                              () => widget
                                                  .onEdit(snapshot!.formation),
                                            ),
                                    child: Text(AppLanguage.text('在编辑器打开')),
                                  ),
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => run(
                                              () => widget.onArchive(
                                                snapshot!.formation,
                                              ),
                                            ),
                                    child: Text(AppLanguage.text('加入我的存档')),
                                  ),
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => run(() async {
                                              final text =
                                                  FormationExchange.encode(
                                                snapshot!.formation,
                                              );
                                              await ProjectFiles.save(
                                                '游戏现场.txt',
                                                Uint8List.fromList(
                                                    utf8.encode(text)),
                                                'text/plain',
                                              );
                                            }),
                                    child: Text(
                                        AppLanguage.text('另存为 PvZ Toolkit 阵型码')),
                                  ),
                                ],
                              ),
                            ],
                            const Divider(),
                            Text(
                              AppLanguage.text('游戏存档文件'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            if (files.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(AppLanguage.text('未找到游戏存档文件。')),
                              ),
                            for (final file in files)
                              ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  file.relativePath,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                subtitle: Text(
                                  AppLanguage.text(
                                    '${file.size} 字节 · ${file.directory}',
                                  ),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: Wrap(
                                  children: [
                                    TextButton(
                                      onPressed:
                                          busy ? null : () => backupSave(file),
                                      child: Text(AppLanguage.text('备份')),
                                    ),
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () =>
                                              backupSave(file, saveAs: true),
                                      child: Text(AppLanguage.text('另存为')),
                                    ),
                                  ],
                                ),
                              ),
                            if (lastFileBackup != null)
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => run(() async {
                                          final redo =
                                              await FileBackups.restoreBackup(
                                            lastFileBackup!,
                                            restoredFile!,
                                          );
                                          lastFileBackup = redo;
                                          notice = '已恢复游戏存档，覆盖前的文件也已备份。';
                                        }),
                                child: Text(AppLanguage.text('恢复上次游戏存档备份')),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      );
}
