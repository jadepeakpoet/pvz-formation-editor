import 'package:flutter/services.dart';

/// Per-engine bridge between the fixed editor and its native toolbox window.
///
/// [supported] describes channel availability, not proof that a native window was
/// displayed. [latestState] is the latest local/received snapshot, not an
/// acknowledgement that another engine applied it.
class WindowBridge {
  static const channel = MethodChannel('pvz_formation_editor/windows');
  static bool _supported = false, _toolbox = false, _handlerInstalled = false;
  static int _generation = 0, _stateSequence = 0;
  static Map<String, dynamic>? _latestState;
  static Future<dynamic> Function(String, dynamic)? _onEvent;

  static bool get supported => _supported;
  static bool get isToolbox => _toolbox;

  /// Refresh retained library contents after persistence changes without
  /// changing the selected sidebar or stealing keyboard focus.
  static Future<void> refreshLibrary() async {
    if (_supported && !_toolbox) {
      await channel.invokeMethod<void>('refreshLibrary');
    }
  }

  static Map<String, dynamic>? get latestState =>
      _latestState == null ? null : _copyState(_latestState!);

  static Map<String, dynamic> _copyState(Map state) {
    // Copy the same values supported by the wire codec, including nested maps,
    // lists and typed bytes. Caller/callback mutation cannot change our snapshot.
    final value = channel.codec
        .decodeEnvelope(channel.codec.encodeSuccessEnvelope(state));
    return Map<String, dynamic>.from(value as Map);
  }

  static void _remember(Map state) {
    _latestState = _copyState(state);
    _stateSequence++;
  }

  static void _detach() {
    _supported = false;
    _onEvent = null;
    if (_handlerInstalled) {
      channel.setMethodCallHandler(null);
      _handlerInstalled = false;
    }
  }

  static Future<bool> initialize(
      {required bool toolbox,
      String? dataPath,
      String? activeDraftId,
      required Future<dynamic> Function(String, dynamic) onEvent}) async {
    _detach();
    final generation = ++_generation;
    _toolbox = toolbox;
    _latestState = null;
    _stateSequence = 0;
    _onEvent = onEvent;
    _handlerInstalled = true;
    channel.setMethodCallHandler((call) async {
      if (generation != _generation || !_handlerInstalled) {
        throw MissingPluginException('Window bridge is no longer active');
      }
      switch (call.method) {
        case 'receiveState':
        case 'applyToolboxState':
          if (call.arguments is! Map) {
            throw const FormatException('Window state must be a map');
          }
          _remember(call.arguments as Map);
          return _onEvent!(call.method, _copyState(_latestState!));
        case 'toolboxVisibilityChanged':
        case 'sidebarStateChanged':
        case 'editorPointerMoved':
        case 'mainAction':
        case 'libraryOpen':
        case 'showHistory':
          return _onEvent!(call.method, call.arguments);
        default:
          throw MissingPluginException('Unknown window event: ${call.method}');
      }
    });
    final sequenceBeforeReady = _stateSequence;
    try {
      final result = await channel.invokeMethod<dynamic>(
          toolbox ? 'ready' : 'initialize',
          toolbox
              ? null
              : {
                  if (dataPath != null) 'dataPath': dataPath,
                  if (activeDraftId != null) 'activeDraftId': activeDraftId,
                });
      if (generation != _generation) return false;
      if (result == false) {
        _detach();
        return false;
      }
      if (!toolbox && result != true) {
        throw StateError('Native window initialize must return a boolean');
      }
      if (toolbox && result != null && result != true && result is! Map) {
        throw StateError(
            'Native toolbox ready must return a state map or null');
      }
      _supported = true;
      // A newer native event may arrive before ready's older response. Never
      // replay that older response over the already delivered state.
      if (toolbox && result is Map && _stateSequence == sequenceBeforeReady) {
        _remember(result);
        await _onEvent!('receiveState', _copyState(_latestState!));
      }
      return generation == _generation && _supported;
    } on MissingPluginException {
      if (generation == _generation) _detach();
      return false;
    } catch (_) {
      if (generation == _generation) _detach();
      rethrow;
    }
  }

  static Future<dynamic> _send(String method, dynamic arguments) async {
    if (!_supported) return;
    final generation = _generation;
    try {
      return await channel.invokeMethod<dynamic>(method, arguments);
    } on MissingPluginException {
      if (generation == _generation) _detach();
    }
    // PlatformException and application errors propagate to the caller. An
    // existing plugin reporting an error is different from an absent plugin.
  }

  static Future<dynamic> publish(Map<String, dynamic> state) async {
    if (!_supported) return;
    final snapshot = _copyState(state);
    _remember(snapshot);
    return _send(_toolbox ? 'editState' : 'publishState', snapshot);
  }

  static Future<void> setVisible(bool visible) async {
    if (!_supported) return;
    if (_toolbox) {
      throw StateError('Only the main engine controls toolbox visibility');
    }
    await _send('setSidebarVisible', {'visible': visible});
  }

  static Future<void> selectMode(String mode,
      {String? dataPath, String? activeDraftId}) async {
    if (mode != 'toolbox' && mode != 'library') {
      throw ArgumentError.value(mode, 'mode');
    }
    await _send('selectSidebarMode', {
      'mode': mode,
      if (dataPath != null) 'dataPath': dataPath,
      if (activeDraftId != null) 'activeDraftId': activeDraftId,
    });
  }

  static Future<void> mainAction(String action,
      {Map<String, dynamic>? payload}) async {
    if (!_supported) return;
    if (!_toolbox) {
      throw StateError('Only the toolbox engine forwards actions to main');
    }
    await _send('mainAction', {
      'action': action,
      'documentToken': _latestState?['documentToken'],
      if (payload != null) 'payload': payload
    });
  }

  /// Release the active editor before returning to the archive library.
  static Future<void> deactivate() async {
    if (!_supported) return;
    if (_toolbox) {
      throw StateError('Only the main engine deactivates the editor');
    }
    final generation = _generation;
    await _send('deactivate', null);
    if (generation == _generation) _latestState = null;
  }

  static void dispose() {
    ++_generation;
    _detach();
    _latestState = null;
    _toolbox = false;
    _stateSequence = 0;
  }
}
