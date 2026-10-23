import 'dart:async';
import 'package:flutter/material.dart';
import '../storage/formation_repository.dart';
import 'editor_session.dart';

/// Owns every adopted session. A successful [open] adopts the supplied session
/// (or disposes it when its draft is already open). If [open] fails, ownership
/// stays with the caller. Call [flushAll] before [dispose]; dispose does not save.
class EditorTabsController extends ChangeNotifier {
  final FormationRepository repository;
  final List<EditorSession> _sessions = [];
  final List<List<EditorSession>> _history = [];
  final List<int> _historyIndex = [];
  final List<List<int>> _undoBase = [], _undoEnd = [];
  final Map<EditorSession, int> _commandSerials = {};
  final Set<EditorSession> _retiredSessions = {};
  int _activeIndex = 0;
  bool _busy = false, _disposed = false, _retiredCleanupQueued = false;
  String? error;
  Future<bool> Function()? beforeSwitch;
  Future<void> _tail = Future.value();
  String? _rememberedArchiveId;
  bool _resumeQueued = false;

  String _blankName() {
    // Temporary pages reserve names only within the open tabs. Archive names
    // are made unique on first save, so opening/closing a blank consumes none.
    final names = _allSessions.map((session) => session.name).toSet();
    if (!names.contains('新建阵型')) return '新建阵型';
    var index = 2;
    while (names.contains('新建阵型（$index）')) {
      index++;
    }
    return '新建阵型（$index）';
  }

  Future<void> _rememberActive() async {
    final session = active;
    final id = session.sourceArchiveId;
    if (session.readOnly ||
        session.deleted ||
        id == null ||
        id == _rememberedArchiveId) return;
    await repository.rememberOpenedArchive(id);
    _rememberedArchiveId = id;
  }

  EditorTabsController(this.repository, {EditorSession? initial}) {
    final first = initial ?? EditorSession(repository);
    if (!identical(first.repository, repository)) {
      throw ArgumentError('标签页必须使用同一个存档库');
    }
    _adopt(first);
    unawaited(_serial(() => _flush(first)).catchError((Object _) {}));
  }

  /// Completes initial adoption persistence; inspect [error] on failure.
  Future<void> get ready => _tail;
  List<EditorSession> get sessions => List.unmodifiable(_sessions);

  /// All owned sessions, including pages retained in back/forward history.
  List<EditorSession> get allSessions => List.unmodifiable(_allSessions);
  EditorSession get active => _sessions[_activeIndex];
  EditorSession get activeSession => active;
  int get activeIndex => _activeIndex;
  bool get busy => _busy;
  bool get canGoBack => _historyIndex[_activeIndex] > 0;
  bool get canGoForward =>
      _historyIndex[_activeIndex] + 1 < _history[_activeIndex].length;
  bool get canUndo =>
      (active.canUndo &&
          active.undoDepth >
              _undoBase[_activeIndex][_historyIndex[_activeIndex]]) ||
      canGoBack;
  bool get canRedo =>
      (active.canRedo &&
          active.undoDepth <
              _undoEnd[_activeIndex][_historyIndex[_activeIndex]]) ||
      canGoForward;
  Iterable<EditorSession> get _allSessions =>
      {..._history.expand((entries) => entries), ..._retiredSessions};

  void _listen(EditorSession session) {
    _commandSerials[session] = session.newCommandSerial;
    session.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (_disposed) return;
    for (var tab = 0; tab < _history.length; tab++) {
      final cursor = _historyIndex[tab];
      final session = _history[tab][cursor];
      if (_commandSerials[session] == session.newCommandSerial) continue;
      _commandSerials[session] = session.newCommandSerial;
      _undoEnd[tab][cursor] = session.undoDepth;
      final entries = _history[tab];
      final next = cursor + 1;
      final discarded = entries.skip(next).toSet();
      entries.removeRange(next, entries.length);
      _undoBase[tab].removeRange(next, _undoBase[tab].length);
      _undoEnd[tab].removeRange(next, _undoEnd[tab].length);
      final retained = _history.expand((pages) => pages).toSet();
      _retiredSessions.addAll(discarded.difference(retained));
    }
    // The first actual edit creates the archive asynchronously. Remember it
    // only if it is still the active page when the queued operation executes.
    if (!_resumeQueued &&
        !active.readOnly &&
        active.sourceArchiveId != null &&
        active.sourceArchiveId != _rememberedArchiveId) {
      _resumeQueued = true;
      unawaited(_serial(() async {}).whenComplete(() {
        _resumeQueued = false;
      }).catchError((Object _) {}));
    }
    // Historical sessions may also be renamed by archive management.
    for (final session in _allSessions) {
      _commandSerials[session] = session.newCommandSerial;
    }
    if (_retiredSessions.isNotEmpty && !_retiredCleanupQueued) {
      _retiredCleanupQueued = true;
      unawaited(_serial(() async {
        try {
          await _flushRetired();
        } finally {
          _retiredCleanupQueued = false;
        }
      }).catchError((Object _) {}));
    }
    _changed();
  }

  Future<void> _flushRetired() async {
    for (final session in _retiredSessions.toList()) {
      await _flush(session);
      _retiredSessions.remove(session);
      _release(session);
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _adopt(EditorSession session) {
    _sessions.add(session);
    _history.add([session]);
    _historyIndex.add(0);
    _undoBase.add([0]);
    _undoEnd.add([session.undoDepth]);
    _listen(session);
  }

  void _release(EditorSession session) {
    session.removeListener(_sessionChanged);
    _commandSerials.remove(session);
    _retiredSessions.remove(session);
    session.dispose();
  }

  Future<void> _serial(Future<void> Function() action) {
    final operation = _tail.then((_) async {
      if (_disposed) throw StateError('标签页已关闭');
      _busy = true;
      error = null;
      _changed();
      try {
        await action();
        await _rememberActive();
      } catch (e) {
        error = '$e';
        rethrow;
      } finally {
        _busy = false;
        _changed();
      }
    });
    // A rejected operation must not poison subsequent queued operations.
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  Future<void> _prepareSwitch() async {
    if (beforeSwitch != null && !await beforeSwitch!()) {
      throw StateError('请先完成当前操作');
    }
    if (_disposed) throw StateError('标签页已关闭');
  }

  Future<void> _flush(EditorSession session) async {
    await session.flush();
    if (session.error != null) {
      throw StateError('“${session.name}”保存失败：${session.error}');
    }
    if (_disposed) throw StateError('标签页已关闭');
  }

  Future<void> open(EditorSession session,
          {bool newTab = false, bool forceNavigation = false}) =>
      _serial(() async {
        if (!identical(session.repository, repository)) {
          throw ArgumentError('标签页必须使用同一个存档库');
        }
        int existingTab = -1, existingEntry = -1;
        for (var tab = 0; tab < _history.length; tab++) {
          final entry = _history[tab].indexWhere((s) =>
              identical(s, session) ||
              ((s.id == session.id ||
                      (!forceNavigation &&
                          s.sourceArchiveId != null &&
                          s.sourceArchiveId == session.sourceArchiveId)) &&
                  s.readOnly == session.readOnly));
          if (entry >= 0) {
            existingTab = tab;
            existingEntry = entry;
            break;
          }
        }
        if (existingTab >= 0) {
          final existing = _history[existingTab][existingEntry];
          if (!identical(active, existing)) {
            await _prepareSwitch();
            await _flush(active);
          }
          if (existingTab == _activeIndex) {
            if (!identical(active, existing)) {
              await _appendHistory(existing);
            }
          } else {
            _activeIndex = existingTab;
            _historyIndex[existingTab] = existingEntry;
            _sessions[existingTab] = existing;
          }
          if (!identical(existing, session)) session.dispose();
          return;
        }
        await _prepareSwitch();
        await _flush(active);
        await _flush(session);
        if (newTab) {
          _adopt(session);
          _activeIndex = _sessions.length - 1;
        } else {
          await _appendHistory(session);
          _listen(session);
        }
      });
  Future<void> _appendHistory(EditorSession session) async {
    final entries = _history[_activeIndex];
    final next = _historyIndex[_activeIndex] + 1;
    final discarded = entries.skip(next).toSet();
    for (final entry in discarded) {
      await _flush(entry);
    }
    // A new navigation starts from the state actually visible now. Redo
    // commands already undone before departing belong to the abandoned branch.
    _undoEnd[_activeIndex][_historyIndex[_activeIndex]] = active.undoDepth;
    entries.removeRange(next, entries.length);
    _undoBase[_activeIndex].removeRange(next, _undoBase[_activeIndex].length);
    _undoEnd[_activeIndex].removeRange(next, _undoEnd[_activeIndex].length);
    entries.add(session);
    _retiredSessions.remove(session);
    _undoBase[_activeIndex].add(session.undoDepth);
    _undoEnd[_activeIndex].add(session.undoDepth);
    _historyIndex[_activeIndex] = next;
    _sessions[_activeIndex] = session;
    final retained = _allSessions.toSet();
    for (final entry in discarded.difference(retained)) {
      _release(entry);
    }
  }

  Future<void> goBack() => _navigate(-1);
  Future<void> goForward() => _navigate(1);

  Future<void> _navigate(int delta) => _serial(() async {
        final target = _historyIndex[_activeIndex] + delta;
        final entries = _history[_activeIndex];
        if (target < 0 || target >= entries.length) return;
        await _prepareSwitch();
        await _flush(active);
        // Completing an in-flight edit may invalidate forward navigation.
        if (target >= entries.length) return;
        _historyIndex[_activeIndex] = target;
        _sessions[_activeIndex] = entries[target];
      });

  /// Undo document/title commands until the current visit's arrival point,
  /// then undo the navigation itself. Revisiting a page preserves chronology.
  Future<void> undo() => _serial(() async {
        await _prepareSwitch();
        final cursor = _historyIndex[_activeIndex];
        if (active.canUndo &&
            active.undoDepth > _undoBase[_activeIndex][cursor]) {
          active.undo();
          return;
        }
        if (cursor == 0) return;
        await _flush(active);
        _historyIndex[_activeIndex] = cursor - 1;
        _sessions[_activeIndex] = _history[_activeIndex][cursor - 1];
      });

  Future<void> redo() => _serial(() async {
        await _prepareSwitch();
        final cursor = _historyIndex[_activeIndex];
        if (active.canRedo &&
            active.undoDepth < _undoEnd[_activeIndex][cursor]) {
          active.redo();
          return;
        }
        if (!canGoForward) return;
        await _flush(active);
        _historyIndex[_activeIndex] = cursor + 1;
        _sessions[_activeIndex] = _history[_activeIndex][cursor + 1];
      });

  Future<void> activate(int index) {
    if (index < 0 || index >= _sessions.length) {
      return Future.error(RangeError.index(index, _sessions));
    }
    final requested = _sessions[index];
    return _serial(() async {
      final currentIndex = _sessions.indexOf(requested);
      if (currentIndex < 0 || currentIndex == _activeIndex) return;
      await _prepareSwitch();
      await _flush(active);
      _activeIndex = currentIndex;
    });
  }

  Future<void> close(int index) {
    if (index < 0 || index >= _sessions.length) {
      return Future.error(RangeError.index(index, _sessions));
    }
    final requested = _sessions[index];
    return _serial(() async {
      final currentIndex = _sessions.indexOf(requested);
      if (currentIndex < 0) return;
      final wasActive = identical(requested, active);
      if (wasActive) await _prepareSwitch();
      final entries = _history[currentIndex].toSet();
      for (final entry in entries) {
        await _flush(entry);
      }
      _sessions.removeAt(currentIndex);
      _history.removeAt(currentIndex);
      _historyIndex.removeAt(currentIndex);
      _undoBase.removeAt(currentIndex);
      _undoEnd.removeAt(currentIndex);
      for (final entry in entries) {
        _release(entry);
      }
      if (_sessions.isEmpty) {
        final name = _blankName();
        final replacement =
            EditorSession(repository, name: name, deferInitialSave: true);
        await _flush(replacement);
        _adopt(replacement);
        _activeIndex = 0;
      } else if (wasActive) {
        _activeIndex = currentIndex.clamp(0, _sessions.length - 1);
      } else if (currentIndex < _activeIndex) {
        _activeIndex--;
      }
    });
  }

  /// Removes an archive from every tab and navigation history before deletion.
  /// Saving or preparing the active page may reject without changing history.
  Future<void> removeArchive(String archiveId) => _serial(() async {
        bool matches(EditorSession session) =>
            session.id == archiveId || session.sourceArchiveId == archiveId;
        final removed = _allSessions.where(matches).toList();
        if (removed.isEmpty) return;
        final previousActive = active;
        final previousTab = _activeIndex;
        if (matches(previousActive)) await _prepareSwitch();
        for (final session in removed) {
          await _flush(session);
        }
        EditorSession? replacement;
        if (_history.expand((entries) => entries).every(matches)) {
          final name = _blankName();
          replacement =
              EditorSession(repository, name: name, deferInitialSave: true);
          try {
            await _flush(replacement);
          } catch (_) {
            replacement.dispose();
            rethrow;
          }
        }
        final nextHistory = <List<EditorSession>>[];
        final nextIndices = <int>[];
        final nextBases = <List<int>>[], nextEnds = <List<int>>[];
        int? nextActive;
        for (var tab = 0; tab < _history.length; tab++) {
          final entries = _history[tab];
          final cursor = _historyIndex[tab];
          final kept = entries.where((entry) => !matches(entry)).toList();
          if (kept.isEmpty) continue;
          var nextCursor =
              entries.take(cursor).where((e) => !matches(e)).length;
          if (matches(entries[cursor])) {
            // Prefer the nearest surviving previous page, then the next page.
            nextCursor =
                entries.take(cursor).where((e) => !matches(e)).length - 1;
            if (nextCursor < 0) nextCursor = 0;
          }
          if (tab == previousTab) nextActive = nextHistory.length;
          nextHistory.add(kept);
          nextIndices.add(nextCursor);
          nextBases.add([
            for (var i = 0; i < entries.length; i++)
              if (!matches(entries[i])) _undoBase[tab][i]
          ]);
          nextEnds.add([
            for (var i = 0; i < entries.length; i++)
              if (!matches(entries[i])) _undoEnd[tab][i]
          ]);
        }
        _history
          ..clear()
          ..addAll(nextHistory);
        _historyIndex
          ..clear()
          ..addAll(nextIndices);
        _undoBase
          ..clear()
          ..addAll(nextBases);
        _undoEnd
          ..clear()
          ..addAll(nextEnds);
        _sessions
          ..clear()
          ..addAll(List.generate(nextHistory.length,
              (index) => nextHistory[index][nextIndices[index]]));
        for (final session in removed) {
          _release(session);
        }
        if (replacement != null) {
          _adopt(replacement);
          _activeIndex = 0;
        } else {
          _activeIndex =
              nextActive ?? previousTab.clamp(0, _sessions.length - 1);
        }
      });

  Future<void> newBlank() => _serial(() async {
        await _prepareSwitch();
        await _flush(active);
        final name = _blankName();
        final session =
            EditorSession(repository, name: name, deferInitialSave: true);
        try {
          await _flush(session);
          _adopt(session);
          _activeIndex = _sessions.length - 1;
        } catch (_) {
          session.dispose();
          rethrow;
        }
      });

  Future<bool> flushAll() async {
    try {
      await _serial(() async {
        final failures = <String>[];
        for (final session in _allSessions) {
          try {
            await _flush(session);
          } catch (e) {
            failures.add('$e');
          }
        }
        if (failures.isNotEmpty) throw StateError(failures.join('\n'));
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final session in _allSessions) {
      _release(session);
    }
    super.dispose();
  }
}

class EditorTabStrip extends StatelessWidget {
  final EditorTabsController controller;
  const EditorTabStrip({super.key, required this.controller});
  Future<void> _run(
      BuildContext context, Future<void> Function() operation) async {
    try {
      await operation();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) => SizedBox(
          key: const ValueKey('editor-tabs-strip'),
          height: 28,
          child: Material(
              color: const Color(0xffe5e9e0),
              child: Row(children: [
                for (final back in [true, false])
                  SizedBox(
                      width: 28,
                      child: IconButton(
                          key: ValueKey(
                              back ? 'editor-go-back' : 'editor-go-forward'),
                          tooltip: back ? '后退' : '前进',
                          padding: EdgeInsets.zero,
                          iconSize: 17,
                          onPressed: controller.busy ||
                                  !(back
                                      ? controller.canGoBack
                                      : controller.canGoForward)
                              ? null
                              : () => _run(
                                  context,
                                  back
                                      ? controller.goBack
                                      : controller.goForward),
                          icon: Icon(
                              back ? Icons.arrow_back : Icons.arrow_forward))),
                Expanded(
                    child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: controller.sessions.length,
                        itemBuilder: (context, index) {
                          final session = controller.sessions[index];
                          final selected = controller.activeIndex == index;
                          final pending = session.saveState == '保存中' ||
                              session.saveState == '保存失败';
                          return Container(
                              width: 166,
                              margin: const EdgeInsets.only(top: 2, left: 3),
                              decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xfffafbf7)
                                      : const Color(0xffe0e5da),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6))),
                              child: Row(children: [
                                Expanded(
                                    child: InkWell(
                                        key: ValueKey(
                                            'editor-tab-${session.id}'),
                                        onTap: controller.busy
                                            ? null
                                            : () => _run(
                                                context,
                                                () =>
                                                    controller.activate(index)),
                                        child: Padding(
                                            padding:
                                                const EdgeInsets.only(left: 9),
                                            child: Tooltip(
                                                message:
                                                    '${session.name} · ${session.readOnly ? '只读预览' : session.saveState}',
                                                child: Row(children: [
                                                  if (session.readOnly) ...[
                                                    const Icon(
                                                        Icons.lock_outline,
                                                        size: 12,
                                                        color:
                                                            Color(0xff64765c)),
                                                    const SizedBox(width: 4)
                                                  ],
                                                  if (pending) ...[
                                                    Icon(Icons.circle,
                                                        size: 5,
                                                        color: session.error ==
                                                                null
                                                            ? const Color(
                                                                0xff688258)
                                                            : Colors.red),
                                                    const SizedBox(width: 5)
                                                  ],
                                                  Expanded(
                                                      child: Text(session.name,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                              fontSize: 11,
                                                              color: const Color(
                                                                  0xff344a2c),
                                                              fontWeight: selected
                                                                  ? FontWeight
                                                                      .w600
                                                                  : FontWeight
                                                                      .w400)))
                                                ]))))),
                                SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: IconButton(
                                        key: ValueKey(
                                            'editor-close-tab-${session.id}'),
                                        padding: EdgeInsets.zero,
                                        tooltip: '关闭“${session.name}”',
                                        iconSize: 13,
                                        onPressed: controller.busy
                                            ? null
                                            : () => _run(context,
                                                () => controller.close(index)),
                                        icon: const Icon(Icons.close)))
                              ]));
                        })),
                SizedBox(
                    width: 32,
                    child: IconButton(
                        key: const ValueKey('editor-new-tab'),
                        tooltip: '新建标签页',
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        onPressed: controller.busy
                            ? null
                            : () => _run(context, controller.newBlank),
                        icon: const Icon(Icons.add))),
                if (controller.busy)
                  const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5)))
              ]))));
}
