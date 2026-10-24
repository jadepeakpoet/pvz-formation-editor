import 'package:flutter/services.dart';

import '../domain/formation.dart';
import '../domain/website_codec.dart';
import '../domain/plant_game_state.dart';
import '../domain/zombie_layout.dart';
import '../domain/zombie_game_state.dart';

/// An identified live process. Capabilities are reported by the native adapter,
/// never inferred from the window title by the UI.
class RunningGame {
  final int pid, timestamp;
  final String title, executable, version;
  final bool canRead, canWrite;
  const RunningGame({
    required this.pid,
    required this.timestamp,
    required this.title,
    required this.executable,
    required this.version,
    required this.canRead,
    required this.canWrite,
  });
  factory RunningGame.fromJson(Map<Object?, Object?> value) => RunningGame(
        pid: value['pid'] as int,
        timestamp: value['timestamp'] as int,
        title: value['title'] as String,
        executable: value['executable'] as String,
        version: value['version'] as String,
        canRead: value['canRead'] == true,
        canWrite: value['canWrite'] == true,
      );
}

class GameFormationSnapshot {
  final int pid;
  final String version;
  final Formation formation;
  final DateTime capturedAt;

  /// Runtime attributes retained in session formation backups.
  final List<Map<String, dynamic>> runtimePieces;
  final bool includesZombies;
  GameFormationSnapshot({
    required this.pid,
    required this.version,
    required this.formation,
    required this.capturedAt,
    required this.runtimePieces,
    this.includesZombies = false,
  });
  Map<String, dynamic> toJson() => {
        'pid': pid,
        'version': version,
        'map': formation.mapId,
        'sunValue': formation.sunValue,
        'pieces': runtimePieces,
        if (includesZombies) 'includeZombies': true,
      };
  factory GameFormationSnapshot.fromJson(Map<Object?, Object?> json) {
    final raw = (json['pieces'] as List)
        .map(
          (p) => Map<String, dynamic>.unmodifiable(
            Map<String, dynamic>.from(p as Map),
          ),
        )
        .toList();
    final pieces = <Piece>[];
    for (var i = 0; i < raw.length; i++) {
      final p = raw[i];
      final type = p['type'] as int?;
      final grid = p['gridType'] as int?;
      final zombie = p['zombieType'] as int?;
      final id = zombie != null
          ? WebsiteCodec.typeForIndex(zombie + 0x50)
          : type != null && type >= 0 && type < WebsiteCodec.plantIds.length
              ? WebsiteCodec.plantIds[type]
              : {1: 'grave', 3: 'ladder', 11: 'rake'}[grid];
      if (id == null) throw const FormatException('游戏对象类型尚未适配');
      if (zombie != null && ZombieLayout.gameType(id) != zombie) {
        throw const FormatException('游戏僵尸类型尚未适配');
      }
      final row = p['row'] as int;
      final zombieState = zombie != null && p.containsKey('animation')
          ? ZombieGameState.fromRuntime(zombie, p) : null;
      final editorX = zombie == null ? null : zombieState == null
          ? (p['x'] as num).toDouble()
          : ZombieLayout.editorX(id, zombieState.row, zombieState.col,
              (p['x'] as num).toDouble());
      final col = zombieState != null ? ZombieLayout.column(editorX!) : p['col'] as int;
      if (row < 0 || row > 5 || col < 0 || col > 8) {
        throw const FormatException('游戏对象坐标无效');
      }
      pieces.add(
        Piece(
          id: 'game-$i',
          type: id,
          row: row,
          col: col,
          layer: ObjectSpec.byId(id).layer,
          asleep: p['asleep'] == true,
          frameRow: zombieState?.row ?? p['frameRow'] as int?,
          frameCol: zombieState?.col ?? p['frameCol'] as int? ?? 0,
          websiteFields: zombie != null
              ? ZombieLayout.positionFields(
                  id,
                  row,
                  col,
                  editorX!,
                  frameRow: zombieState?.row ?? p['frameRow'] as int? ?? 0,
                  frameCol: zombieState?.col ?? p['frameCol'] as int? ?? 0,
                )
              : null,
          effects: {
            if (p['imitater'] == true) '模仿者',
            if (zombie == null && (p['eatenFlashCountdown'] as int? ?? 0) > 0) '高亮',
          },
        ),
      );
    }
    final map = json['map'] as String;
    if (!const [
      'day',
      'night',
      'pool',
      'fog',
      'roof',
      'moonRoof',
    ].contains(map)) throw const FormatException('游戏场景尚未适配');
    return GameFormationSnapshot(
      pid: json['pid'] as int,
      version: json['version'] as String,
      formation: Formation(
        mapId: map,
        sunValue: json['sunValue'] as int,
        pieces: pieces,
      ),
      capturedAt: DateTime.now(),
      runtimePieces: List.unmodifiable(raw),
      includesZombies: json['includeZombies'] == true,
    );
  }
}

class GameSaveFile {
  final String path, relativePath, directory;
  final int size;
  final DateTime modifiedAt;
  const GameSaveFile({
    required this.path,
    required this.relativePath,
    required this.directory,
    required this.size,
    required this.modifiedAt,
  });
  factory GameSaveFile.fromJson(Map<Object?, Object?> value) => GameSaveFile(
        path: value['path'] as String,
        relativePath: value['relativePath'] as String,
        directory: value['directory'] as String,
        size: value['size'] as int,
        modifiedAt:
            DateTime.fromMillisecondsSinceEpoch(value['modifiedAt'] as int),
      );
}

class GameBridge {
  static const channel = MethodChannel('pvz_formation_editor/game');
  static const supportedMaps = ['day', 'night', 'pool', 'fog', 'roof', 'moonRoof'];
  static void validateTarget(Formation target) {
    if (!supportedMaps.contains(target.mapId)) {
      throw UnsupportedError('“${target.map.name}”是扩展地图；原版游戏支持白天、黑夜、泳池、浓雾、屋顶和月夜屋顶。六行布局可选择泳池或浓雾场地。');
    }
    for (final piece in target.pieces) {
      if (piece.row < 0 || piece.row >= target.map.rows || piece.col < 0 ||
          piece.col + piece.spec.width > target.map.columns) {
        throw FormatException('“${piece.spec.name}”位于第 ${piece.row + 1} 行、第 ${piece.col + 1} 列，超出${target.map.name}的场地范围');
      }
    }
  }
  static Future<List<RunningGame>> listGames() async {
    final values = await channel.invokeListMethod<dynamic>('listGames') ?? [];
    return values
        .map((v) => RunningGame.fromJson(Map<Object?, Object?>.from(v as Map)))
        .toList();
  }

  static Future<GameFormationSnapshot> readFormation(
    int pid, {
    bool includeZombies = false,
  }) async {
    if (pid <= 0) throw ArgumentError.value(pid, 'pid');
    final value = await channel.invokeMapMethod<Object?, Object?>(
      'readFormation',
      {'pid': pid, if (includeZombies) 'includeZombies': true},
    );
    if (value == null) throw StateError('游戏未返回阵型');
    return GameFormationSnapshot.fromJson(value);
  }

  /// expectedBefore is a transient consistency check, not a history backup.
  static Future<GameFormationSnapshot> applyFormation(
    int pid,
    Formation target,
    GameFormationSnapshot expectedBefore,
  ) async {
    if (pid <= 0 || expectedBefore.pid != pid) {
      throw ArgumentError('读取的快照与游戏进程不一致');
    }
    validateTarget(target);
    final pieces = <Map<String, dynamic>>[];
    for (final p in target.pieces) {
      final zombie = ZombieLayout.gameType(p.type);
      if (zombie != null && expectedBefore.includesZombies) {
        final x = ZombieLayout.gameX(p);
        if (!x.isFinite || x < -200 || x > 1200) {
          throw const FormatException('僵尸横坐标超出支持范围');
        }
        pieces.add({
          'zombieType': zombie,
          'row': p.row,
          'col': ZombieLayout.column(x),
          'x': x,
          'frameRow': p.frameRow,
          'frameCol': p.frameCol,
          'state': ZombieGameState.of(p).toJson(),
        });
        continue;
      }
      final type = WebsiteCodec.plantIds.indexOf(p.type);
      final gridType = {'grave': 1, 'ladder': 3, 'rake': 11}[p.type];
      if (type < 0 && gridType == null) {
        throw UnsupportedError('当前游戏应用暂不支持对象：${p.spec.name}');
      }
      if (p.scale != 1 ||
          p.opacity != 1 ||
          p.flipped ||
          p.flippedVertical ||
          p.effects.any((effect) => effect != '模仿者' &&
              !(type >= 0 && effect == '高亮'))) {
        throw UnsupportedError('当前游戏应用暂不支持缩放、翻转或装饰图像特效');
      }
      if (p.type == 'cob' && p.frameRow != 0) {
        throw UnsupportedError('玉米炮发射动作不能作为初始布阵状态，请选择第一行的已装填或空炮外观');
      }
      pieces.add({
        if (gridType == null) 'type': type else 'gridType': gridType,
        'row': p.row,
        'col': p.col,
        'imitater': p.effects.contains('模仿者'),
        'asleep': p.asleep,
        if (p.effects.contains('高亮')) 'eatenFlash': true,
        if (PlantGameState.of(p) case final int state) 'visualState': state,
      });
    }
    final result = await channel.invokeMapMethod<Object?, Object?>(
      'applyFormation',
      {
        'pid': pid,
        'target': {
          'map': target.mapId,
          // Toolkit lineup codes contain no sun value. Inject the layout only.
          'sunValue': expectedBefore.formation.sunValue,
          'pieces': pieces,
          if (expectedBefore.includesZombies) 'includeZombies': true,
        },
        'expectedBefore': expectedBefore.toJson(),
      },
    );
    if (result == null || result['after'] is! Map) {
      throw StateError('游戏未返回应用后校验结果，请重新获取阵型');
    }
    return GameFormationSnapshot.fromJson(
      Map<Object?, Object?>.from(result['after'] as Map),
    );
  }

  static Future<int> clearZombies(int pid) async {
    if (pid <= 0) throw ArgumentError.value(pid, 'pid');
    final result = await channel.invokeMapMethod<String, dynamic>('clearZombies', {'pid': pid});
    final count = result?['cleared'];
    if (count is! int || count < 0) throw StateError('游戏未返回清除结果');
    return count;
  }

  static Future<List<GameSaveFile>> listSaveFiles(int pid) async {
    if (pid <= 0) throw ArgumentError.value(pid, 'pid');
    final result = await channel.invokeListMethod<dynamic>('listSaveFiles', {
          'pid': pid,
        }) ??
        [];
    return result
        .map((v) => GameSaveFile.fromJson(Map<Object?, Object?>.from(v as Map)))
        .toList();
  }

  static Future<List<String>> saveFolders(int pid) async {
    if (pid <= 0) throw ArgumentError.value(pid, 'pid');
    return (await channel.invokeListMethod<String>('saveFolders', {
          'pid': pid,
        })) ??
        [];
  }
}
