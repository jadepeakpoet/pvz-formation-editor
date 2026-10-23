import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Small synchronous SQLite adapter; callers serialize access through the repository.
class NativeSqlite {
  late final DynamicLibrary _library;
  late final Pointer<Void> _db;
  late final int Function(Pointer<Void>) _close;
  late final Pointer<Utf8> Function(Pointer<Void>) _error;
  late final int Function(Pointer<Void>, Pointer<Utf8>, int,
      Pointer<Pointer<Void>>, Pointer<Pointer<Utf8>>) _prepare;
  late final int Function(Pointer<Void>) _step;
  late final int Function(Pointer<Void>) _finalize;
  late final int Function(Pointer<Void>) _count;
  late final Pointer<Utf8> Function(Pointer<Void>, int) _name;
  late final Pointer<Utf8> Function(Pointer<Void>, int) _text;
  late final int Function(Pointer<Void>, int) _type;

  NativeSqlite(String path) {
    _library = DynamicLibrary.open(Platform.isMacOS
        ? '/usr/lib/libsqlite3.dylib'
        : Platform.isWindows
            ? 'winsqlite3.dll'
            : 'libsqlite3.so.0');
    final open = _library.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Pointer<Void>>),
        int Function(Pointer<Utf8>, Pointer<Pointer<Void>>)>('sqlite3_open');
    _close = _library.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('sqlite3_close');
    _error = _library.lookupFunction<Pointer<Utf8> Function(Pointer<Void>),
        Pointer<Utf8> Function(Pointer<Void>)>('sqlite3_errmsg');
    _prepare = _library.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32,
            Pointer<Pointer<Void>>, Pointer<Pointer<Utf8>>),
        int Function(Pointer<Void>, Pointer<Utf8>, int, Pointer<Pointer<Void>>,
            Pointer<Pointer<Utf8>>)>('sqlite3_prepare_v2');
    _step = _library.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('sqlite3_step');
    _finalize = _library.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('sqlite3_finalize');
    _count = _library.lookupFunction<Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>('sqlite3_column_count');
    _name = _library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Int32),
        Pointer<Utf8> Function(Pointer<Void>, int)>('sqlite3_column_name');
    _text = _library.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Int32),
        Pointer<Utf8> Function(Pointer<Void>, int)>('sqlite3_column_text');
    _type = _library.lookupFunction<Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)>('sqlite3_column_type');
    final file = path.toNativeUtf8();
    final out = calloc<Pointer<Void>>();
    try {
      final code = open(file, out);
      _db = out.value;
      if (code != 0) {
        final message = _error(_db).toDartString();
        _close(_db);
        throw StateError('SQLite open ($code): $message');
      }
    } finally {
      calloc.free(file);
      calloc.free(out);
    }
  }

  List<Map<String, Object?>> query(String sql) {
    final source = sql.toNativeUtf8();
    final out = calloc<Pointer<Void>>();
    Pointer<Void> statement = nullptr;
    try {
      var code = _prepare(_db, source, -1, out, nullptr);
      statement = out.value;
      if (code != 0) {
        throw StateError(
            'SQLite prepare ($code): ${_error(_db).toDartString()}');
      }
      final rows = <Map<String, Object?>>[];
      while ((code = _step(statement)) == 100) {
        final row = <String, Object?>{};
        for (var i = 0; i < _count(statement); i++) {
          final type = _type(statement, i);
          final value = type == 5 ? null : _text(statement, i).toDartString();
          row[_name(statement, i).toDartString()] =
              type == 1 ? int.parse(value!) : value;
        }
        rows.add(row);
      }
      if (code != 101) {
        throw StateError('SQLite step ($code): ${_error(_db).toDartString()}');
      }
      return rows;
    } finally {
      if (statement != nullptr) {
        _finalize(statement);
      }
      calloc.free(source);
      calloc.free(out);
    }
  }

  void close() {
    final code = _close(_db);
    if (code != 0) {
      throw StateError('SQLite close: $code');
    }
  }
}
