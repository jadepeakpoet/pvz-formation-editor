import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'mobile_db_stub.dart' if (dart.library.ui) 'mobile_db_flutter.dart';
import 'native_sqlite.dart';

class DraftRecord {
  final String id, name, mapId;
  final Map<String, dynamic> document;
  final int revision;
  final DateTime createdAt, updatedAt;
  final String? sourceArchiveId, thumbnail, savedFingerprint;
  DraftRecord(
      {required this.id,
      required this.name,
      required this.mapId,
      required this.document,
      required this.revision,
      DateTime? createdAt,
      DateTime? updatedAt,
      this.sourceArchiveId,
      this.thumbnail,
      this.savedFingerprint})
      : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();
}

class ArchiveRecord {
  final String id, name, note;
  final List<String> tags;
  final bool favorite;
  final Map<String, dynamic> document;
  final DateTime createdAt, updatedAt;
  ArchiveRecord(
      {required this.id,
      required this.name,
      required this.document,
      required this.createdAt,
      required this.updatedAt,
      this.note = '',
      this.tags = const [],
      this.favorite = false});
}

class ArchiveVersion {
  final String id, archiveId, name, note;
  final List<String> tags;
  final DateTime createdAt;
  final Map<String, dynamic> document;
  ArchiveVersion(
      {required this.id,
      required this.archiveId,
      required this.name,
      required this.note,
      required this.tags,
      required this.createdAt,
      required this.document});
}

/// Each operation, including reads, occupies one queue slot. Transactions cannot interleave.
class FormationRepository {
  NativeSqlite? _native;
  dynamic _mobile;
  Future<void> _tail = Future.value();
  bool _closed = false;
  FormationRepository._();
  static Future<FormationRepository> open(String path) async {
    final repo = FormationRepository._();
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        repo._mobile = await openMobileDatabase(path);
      } else {
        repo._native = NativeSqlite(path);
      }
      await repo._query('PRAGMA busy_timeout=5000');
      await repo._query('PRAGMA foreign_keys=ON');
      final version = (await repo._query('PRAGMA user_version'))
          .single['user_version'] as int;
      if (version > 4) {
        throw StateError('数据库版本 $version 高于此应用支持的版本 4');
      }
      await repo._transaction(() async {
        await repo._query(
            'CREATE TABLE IF NOT EXISTS drafts(id TEXT PRIMARY KEY,name TEXT NOT NULL,map_id TEXT NOT NULL,document TEXT NOT NULL,revision INTEGER NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL,source_archive_id TEXT,thumbnail TEXT,saved_fingerprint TEXT)');
        await repo._query(
            'CREATE TABLE IF NOT EXISTS deleted_drafts(id TEXT PRIMARY KEY,deleted_at INTEGER NOT NULL)');
        await repo._query(
            'CREATE TABLE IF NOT EXISTS archives(id TEXT PRIMARY KEY,name TEXT NOT NULL,note TEXT NOT NULL,tags TEXT NOT NULL,favorite INTEGER NOT NULL,document TEXT NOT NULL,created_at INTEGER NOT NULL,updated_at INTEGER NOT NULL)');
        await repo._query(
            'CREATE TABLE IF NOT EXISTS archive_versions(id TEXT PRIMARY KEY,archive_id TEXT NOT NULL,name TEXT NOT NULL,note TEXT NOT NULL,tags TEXT NOT NULL,document TEXT NOT NULL,created_at INTEGER NOT NULL,FOREIGN KEY(archive_id) REFERENCES archives(id) ON DELETE CASCADE)');
        if (version == 1) {
          await repo
              ._query('ALTER TABLE drafts ADD COLUMN saved_fingerprint TEXT');
        }
        // A version-zero database may already contain the original tables.
        final columns = await repo._query('PRAGMA table_info(drafts)');
        if (!columns.any((column) => column['name'] == 'saved_fingerprint')) {
          await repo
              ._query('ALTER TABLE drafts ADD COLUMN saved_fingerprint TEXT');
        }
        // Additive v3 migration: preferences do not create or reference user
        // archives, and do not depend on the shipped preset catalog contents.
        await repo._query(
            'CREATE TABLE IF NOT EXISTS preset_preferences(preset_id TEXT PRIMARY KEY,favorite INTEGER NOT NULL CHECK(favorite IN (0,1)))');
        await repo._query(
            'CREATE TABLE IF NOT EXISTS editor_preferences(key TEXT PRIMARY KEY,value TEXT NOT NULL)');
        await repo._query(
            'CREATE TABLE IF NOT EXISTS legacy_draft_archives(draft_id TEXT PRIMARY KEY,archive_id TEXT NOT NULL)');
        // A still-running older engine can write a legacy draft after another
        // engine completed v4 migration. Drain those rows on every open too.
        if ((await repo._query('SELECT id FROM drafts LIMIT 1')).isNotEmpty) {
          await repo._migrateLegacyDrafts();
        }
        await repo._query('PRAGMA user_version=4');
      });
      // Fail early on database corruption rather than pretending the library is empty.
      final check = await repo._query('PRAGMA quick_check');
      if (check.length != 1 || check.single.values.single != 'ok') {
        throw StateError('数据库完整性检查失败');
      }
      return repo;
    } catch (_) {
      await repo._mobile?.close();
      repo._native?.close();
      rethrow;
    }
  }

  static String _availableName(String base, Set<String> taken) {
    final name = base.trim().isEmpty ? '新建阵型' : base.trim();
    if (!taken.contains(name)) return name;
    final suffix = RegExp(r'^(.*?)(?:（(\d+)）| \((\d+)\))$').firstMatch(name);
    final stem = suffix == null ? name : suffix.group(1)!;
    var index =
        suffix == null ? 2 : int.parse(suffix.group(2) ?? suffix.group(3)!) + 1;
    while (taken.contains('$stem（$index）')) {
      index++;
    }
    return '$stem（$index）';
  }

  Future<void> _migrateLegacyDrafts() async {
    final archives = await _query('SELECT id,name FROM archives');
    final ids = archives.map((r) => r['id'] as String).toSet();
    final names = archives.map((r) => r['name'] as String).toSet();
    for (final draft
        in await _query('SELECT * FROM drafts ORDER BY created_at,rowid')) {
      final oldId = draft['id'] as String;
      final mapped = await _query(
          'SELECT a.id,a.name,a.document FROM archives a JOIN legacy_draft_archives m ON a.id=m.archive_id WHERE m.draft_id=${_q(oldId)}');
      if (mapped.isNotEmpty &&
          mapped.single['document'] == draft['document'] &&
          mapped.single['name'] == draft['name']) {
        // An identical late flush is already preserved; never rewrite its
        // favorite/metadata or add a duplicate history entry.
        continue;
      }
      var id = oldId;
      var suffix = 2;
      while (ids.contains(id)) {
        id = 'legacy-$oldId-${suffix++}';
      }
      final name = _availableName(draft['name'] as String, names);
      // Every old unsaved snapshot is preserved independently. Existing saved
      // archives and their histories are never overwritten during migration.
      await _query(
          'INSERT INTO archives VALUES(${_q(id)},${_q(name)},${_q('由旧草稿迁入')},${_q('[]')},0,${_q(draft['document'])},${_q(draft['created_at'])},${_q(draft['updated_at'])})');
      await _query(
          'INSERT OR REPLACE INTO legacy_draft_archives VALUES(${_q(oldId)},${_q(id)})');
      ids.add(id);
      names.add(name);
    }
    await _query('DELETE FROM drafts');
  }

  Future<String> uniqueDocumentName(String base,
          {Iterable<String> reservedNames = const []}) =>
      _serial(() async {
        final names = <String>{
          ...reservedNames,
          ...(await _query(
                  'SELECT name FROM archives UNION SELECT name FROM drafts'))
              .map((row) => row['name'] as String)
        };
        return _availableName(base, names);
      });

  Future<String?> archiveForLegacyDraft(String id) => _serial(() async {
        final rows = await _query(
            'SELECT archive_id FROM legacy_draft_archives WHERE draft_id=${_q(id)}');
        return rows.isEmpty ? null : rows.single['archive_id'] as String;
      });

  /// Cleanup after legacy adoption/save; unlike user deletion, no tombstone.
  Future<void> discardSavedDraft(String id) => _serial(() async {
        await _query('DELETE FROM drafts WHERE id=${_q(id)}');
      });

  Future<T> _serial<T>(Future<T> Function() action) {
    final future = _tail.then((_) {
      if (_closed) {
        throw StateError('数据库已关闭');
      }
      return action();
    });
    _tail = future.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return future;
  }

  Future<List<Map<String, Object?>>> _query(String sql) async {
    if (_native != null) {
      return _native!.query(sql);
    }
    // Read statements use a cursor. DDL/DML and transaction boundaries use
    // execute, which also lets sqflite track BEGIN/COMMIT/ROLLBACK correctly.
    // busy_timeout is the one assignment used here that returns a result row.
    final cursor = sql.startsWith('SELECT ') ||
        (sql.startsWith('PRAGMA ') &&
            (!sql.contains('=') || sql.startsWith('PRAGMA busy_timeout=')));
    if (cursor) return _mobile!.rawQuery(sql);
    await _mobile!.execute(sql);
    return [];
  }

  Future<T> _transaction<T>(Future<T> Function() action) async {
    await _query('BEGIN IMMEDIATE');
    try {
      final value = await action();
      await _query('COMMIT');
      return value;
    } catch (_) {
      await _query('ROLLBACK');
      rethrow;
    }
  }

  static String _q(Object? value) => value == null
      ? 'NULL'
      : value is num
          ? '$value'
          : "'${value.toString().replaceAll("'", "''")}'";
  static String _json(Map<String, dynamic> document) {
    if (document['schemaVersion'] is! int) {
      throw const FormatException('文档缺少 schemaVersion');
    }
    return jsonEncode(document);
  }

  static Map<String, dynamic> _doc(Object? value) {
    final data = jsonDecode(value as String);
    if (data is! Map<String, dynamic> || data['schemaVersion'] is! int) {
      throw const FormatException('存储的文档已损坏');
    }
    return data;
  }

  static DateTime _date(Object? value) =>
      DateTime.fromMillisecondsSinceEpoch(value as int);
  DraftRecord _draft(Map<String, Object?> r) => DraftRecord(
      id: r['id'] as String,
      name: r['name'] as String,
      mapId: r['map_id'] as String,
      document: _doc(r['document']),
      revision: r['revision'] as int,
      createdAt: _date(r['created_at']),
      updatedAt: _date(r['updated_at']),
      sourceArchiveId: r['source_archive_id'] as String?,
      thumbnail: r['thumbnail'] as String?,
      savedFingerprint: r['saved_fingerprint'] as String?);
  ArchiveRecord _archive(Map<String, Object?> r) => ArchiveRecord(
      id: r['id'] as String,
      name: r['name'] as String,
      note: r['note'] as String,
      tags: List<String>.from(jsonDecode(r['tags'] as String) as List),
      favorite: r['favorite'] == 1,
      document: _doc(r['document']),
      createdAt: _date(r['created_at']),
      updatedAt: _date(r['updated_at']));
  Future<List<DraftRecord>> listDrafts() => _serial(() async =>
      (await _query('SELECT * FROM drafts ORDER BY updated_at DESC'))
          .map(_draft)
          .toList());
  Future<List<ArchiveRecord>> listArchives() => _serial(() async =>
      (await _query('SELECT * FROM archives ORDER BY updated_at DESC'))
          .map(_archive)
          .toList());

  /// Resume follows actual editor activation, independent of archive sort order.
  Future<ArchiveRecord?> lastOpenedArchive() => _serial(() async {
        final rows = await _query(
            "SELECT a.* FROM archives a JOIN editor_preferences p ON p.value=a.id WHERE p.key='last_opened_archive'");
        return rows.isEmpty ? null : _archive(rows.single);
      });

  Future<void> rememberOpenedArchive(String id) => _serial(() async {
        // Ignore stale/deleted IDs rather than replacing a valid resume target.
        await _query(
            "INSERT OR REPLACE INTO editor_preferences(key,value) SELECT 'last_opened_archive',id FROM archives WHERE id=${_q(id)}");
      });

  /// Built-in preset favorites are separate from editable user formations.
  Future<
      Set<String>> listFavoritePresets() => _serial(() async => (await _query(
          'SELECT preset_id FROM preset_preferences WHERE favorite=1 ORDER BY preset_id'))
      .map((row) => row['preset_id'] as String)
      .toSet());

  Future<void> setPresetFavorite(String presetId, bool favorite) =>
      _serial(() async {
        if (presetId.trim().isEmpty ||
            presetId.length > 256 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(presetId)) {
          throw const FormatException('预制阵型 ID 为空、过长或包含控制字符');
        }
        // _q preserves opaque IDs, including Unicode, quotes and punctuation;
        // no catalog index or embedded formation code is used as a foreign key.
        final id = _q(presetId);
        if (favorite) {
          await _query(
              'INSERT OR REPLACE INTO preset_preferences(preset_id,favorite) VALUES($id,1)');
        } else {
          await _query('DELETE FROM preset_preferences WHERE preset_id=$id');
        }
      });

  Future<List<ArchiveVersion>> listVersions(String id) =>
      _serial(() async => (await _query(
              'SELECT * FROM archive_versions WHERE archive_id=${_q(id)} ORDER BY created_at DESC,rowid DESC'))
          .map((r) => ArchiveVersion(
              id: r['id'] as String,
              archiveId: r['archive_id'] as String,
              name: r['name'] as String,
              note: r['note'] as String,
              tags: List<String>.from(jsonDecode(r['tags'] as String) as List),
              createdAt: _date(r['created_at']),
              document: _doc(r['document'])))
          .toList());
  Future<bool> saveDraft(DraftRecord draft) => _serial(() async {
        final data = _json(draft.document);
        return _transaction(() async {
          if ((await _query(
                  'SELECT id FROM deleted_drafts WHERE id=${_q(draft.id)}'))
              .isNotEmpty) {
            return false;
          }
          final previous = await _query(
              'SELECT revision,created_at FROM drafts WHERE id=${_q(draft.id)}');
          if (previous.isNotEmpty &&
              (previous.single['revision'] as int) >= draft.revision) {
            return false;
          }
          String? source = draft.sourceArchiveId;
          String? fingerprint = draft.savedFingerprint;
          if (source != null &&
              (await _query('SELECT id FROM archives WHERE id=${_q(source)}'))
                  .isEmpty) {
            source = null;
            fingerprint = null;
          }
          final created = previous.isEmpty
              ? draft.createdAt.millisecondsSinceEpoch
              : previous.single['created_at'];
          await _query(
              'INSERT OR REPLACE INTO drafts VALUES(${_q(draft.id)},${_q(draft.name)},${_q(draft.mapId)},${_q(data)},${draft.revision},$created,${draft.updatedAt.millisecondsSinceEpoch},${_q(source)},${_q(draft.thumbnail)},${_q(fingerprint)})');
          return true;
        });
      });

  /// Thumbnail generation can finish later; it may update only its exact revision.
  Future<bool> saveDraftThumbnail(String id, int revision, String thumbnail) =>
      _serial(() => _transaction(() async {
            final rows =
                await _query('SELECT revision FROM drafts WHERE id=${_q(id)}');
            if (rows.isEmpty || rows.single['revision'] != revision) {
              return false;
            }
            await _query(
                'UPDATE drafts SET thumbnail=${_q(thumbnail)} WHERE id=${_q(id)} AND revision=$revision');
            return true;
          }));
  Future<void> deleteDraft(String id) => _serial(() => _transaction(() async {
        await _query(
            'INSERT OR IGNORE INTO deleted_drafts VALUES(${_q(id)},${DateTime.now().millisecondsSinceEpoch})');
        await _query('DELETE FROM drafts WHERE id=${_q(id)}');
      }));
  Future<ArchiveRecord> saveArchive(
          {required String id,
          required String name,
          required Map<String, dynamic> document,
          String note = '',
          List<String> tags = const [],
          String? updateId,
          String? expectedFingerprint,
          String? expectedName,
          bool preserveMetadata = false,
          bool uniqueName = false}) =>
      _serial(() => _transaction(() async {
            final data = _json(document);
            final now = DateTime.now().millisecondsSinceEpoch;
            final target = updateId ?? id;
            final previous =
                await _query('SELECT * FROM archives WHERE id=${_q(target)}');
            if (updateId != null && previous.isEmpty) {
              throw StateError('来源存档已不存在');
            }
            if (updateId == null && previous.isNotEmpty) {
              throw StateError('存档 ID 已存在');
            }
            if (previous.isNotEmpty &&
                ((expectedFingerprint != null &&
                        previous.single['document'] != expectedFingerprint) ||
                    (expectedName != null &&
                        previous.single['name'] != expectedName))) {
              throw StateError('存档已在其他窗口更新，请重新打开后再编辑');
            }
            if (previous.isEmpty && uniqueName) {
              final names = (await _query(
                      'SELECT name FROM archives UNION SELECT name FROM drafts'))
                  .map((row) => row['name'] as String)
                  .toSet();
              name = _availableName(name, names);
            }
            if (preserveMetadata && previous.isNotEmpty) {
              note = previous.single['note'] as String;
              tags = List<String>.from(
                  jsonDecode(previous.single['tags'] as String) as List);
            }
            if (previous.isNotEmpty) {
              final old = previous.single;
              if (old['document'] == data &&
                  old['name'] == name &&
                  old['note'] == note &&
                  old['tags'] == jsonEncode(tags)) {
                return _archive(old);
              }
              await _query(
                  'INSERT INTO archive_versions VALUES(${_q('$target-$now-${DateTime.now().microsecondsSinceEpoch}')},${_q(target)},${_q(old['name'])},${_q(old['note'])},${_q(old['tags'])},${_q(old['document'])},$now)');
            }
            final created =
                previous.isEmpty ? now : previous.single['created_at'];
            final favorite = previous.isEmpty ? 0 : previous.single['favorite'];
            // UPDATE instead of REPLACE preserves foreign-key references and old versions.
            if (previous.isEmpty) {
              await _query(
                  'INSERT INTO archives VALUES(${_q(target)},${_q(name)},${_q(note)},${_q(jsonEncode(tags))},$favorite,${_q(data)},$created,$now)');
            } else {
              await _query(
                  'UPDATE archives SET name=${_q(name)},note=${_q(note)},tags=${_q(jsonEncode(tags))},document=${_q(data)},updated_at=$now WHERE id=${_q(target)}');
            }
            return _archive(
                (await _query('SELECT * FROM archives WHERE id=${_q(target)}'))
                    .single);
          }));
  Future<void> deleteArchive(String id) => _serial(() => _transaction(() async {
        await _query(
            'UPDATE drafts SET source_archive_id=NULL,saved_fingerprint=NULL WHERE source_archive_id=${_q(id)}');
        await _query('DELETE FROM archives WHERE id=${_q(id)}');
      }));
  Future<void> updateArchiveMetadata(String id,
          {String? name, String? note, List<String>? tags, bool? favorite}) =>
      _serial(() => _transaction(() async {
            final rows =
                await _query('SELECT * FROM archives WHERE id=${_q(id)}');
            if (rows.isEmpty) return;
            final previous = rows.single;
            final contentChanged = (name != null && name != previous['name']) ||
                (note != null && note != previous['note']) ||
                (tags != null && jsonEncode(tags) != previous['tags']);
            if (contentChanged) {
              final now = DateTime.now().millisecondsSinceEpoch;
              await _query(
                  'INSERT INTO archive_versions VALUES(${_q('$id-$now-${DateTime.now().microsecondsSinceEpoch}')},${_q(id)},${_q(previous['name'])},${_q(previous['note'])},${_q(previous['tags'])},${_q(previous['document'])},$now)');
            }
            final fields = <String>[];
            if (name != null) {
              fields.add('name=${_q(name)}');
            }
            if (note != null) {
              fields.add('note=${_q(note)}');
            }
            if (tags != null) {
              fields.add('tags=${_q(jsonEncode(tags))}');
            }
            if (favorite != null) {
              fields.add('favorite=${favorite ? 1 : 0}');
            }
            if (fields.isEmpty) {
              return;
            }
            fields.add('updated_at=${DateTime.now().millisecondsSinceEpoch}');
            await _query(
                'UPDATE archives SET ${fields.join(',')} WHERE id=${_q(id)}');
          }));
  Future<void> close() => _serial(() async {
        await _mobile?.close();
        _native?.close();
        _closed = true;
      });
}
