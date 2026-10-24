// Real Flutter engine, fake native channel only. Compile like render_smoke.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/platform/window_bridge.dart';

late NativeChannelHarness native;
void check(bool condition, String why) {
  if (!condition) throw StateError(why);
}

Future<T> throws<T>(Future<dynamic> Function() action) async {
  try {
    await action();
  } catch (error) {
    if (error is T) return error as T;
    throw StateError('Expected $T, received ${error.runtimeType}: $error');
  }
  throw StateError('Expected $T, but operation succeeded');
}

Future<dynamic> ignoreEvent(String method, dynamic arguments) async => null;
Future<bool> initialize(
        {bool toolbox = false,
        Future<dynamic> Function(String, dynamic) onEvent = ignoreEvent}) =>
    WindowBridge.initialize(toolbox: toolbox, onEvent: onEvent);

Future<void> main() async {
  _BridgeBinding();
  final results = <Map<String, dynamic>>[];
  Future<void> run(String id, Future<void> Function() body) async {
    WindowBridge.dispose();
    native.reset();
    final row = <String, dynamic>{'id': id, 'status': 'pass'};
    try {
      await body().timeout(const Duration(seconds: 3));
    } catch (error, stack) {
      row.addAll({'status': 'fail', 'error': '$error', 'stack': '$stack'});
    } finally {
      WindowBridge.dispose();
    }
    results.add(row);
    stdout.writeln('${row['status']}: $id ${row['error'] ?? ''}');
  }

  await run('primary.initialize', () async {
    check(await initialize(), 'Primary handshake should be supported');
    check(WindowBridge.supported && !WindowBridge.isToolbox,
        'Primary role/state');
    check(
        native.calls.single.method == 'initialize' &&
            native.calls.single.arguments is Map &&
            (native.calls.single.arguments as Map).isEmpty,
        'Primary handshake payload');
    check(WindowBridge.latestState == null, 'No invented initial snapshot');
  });
  await run('primary.delayed-native-registration', () async {
    native.behavior = (call) async {
      if (native.calls.length == 1) throw MissingPluginException();
      return true;
    };
    check(await WindowBridge.initialize(toolbox: false, availabilityRetries: 3,
        onEvent: ignoreEvent), 'Late native registration must recover');
    check(native.calls.length == 2 && WindowBridge.supported,
        'Only unavailable registration is retried');
  });
  await run('primary.registration-retries-bounded', () async {
    native.behavior = (call) async => throw MissingPluginException();
    check(!await WindowBridge.initialize(toolbox: false, availabilityRetries: 3,
        onEvent: ignoreEvent), 'Permanently missing channel stays unavailable');
    check(native.calls.length == 4 && !native.hasHandler,
        'Retry budget and cleanup');
  });
  await run('primary.library-configuration', () async {
    check(
        await WindowBridge.initialize(
            toolbox: false,
            dataPath: '${Directory.systemTemp.path}/library.sqlite',
            activeDraftId: 'draft-7',
            onEvent: ignoreEvent),
        'Configured initialize');
    final args = native.calls.single.arguments as Map;
    check(
        args.length == 2 &&
            args['dataPath'] == '${Directory.systemTemp.path}/library.sqlite' &&
            args['activeDraftId'] == 'draft-7',
        'Library configuration forwarded');
  });
  await run('sidebar.mode-and-invalid-mode', () async {
    await initialize();
    await WindowBridge.selectMode('library',
        dataPath: '${Directory.systemTemp.path}/store.sqlite', activeDraftId: 'active');
    check(
        native.calls.last.method == 'selectSidebarMode' &&
            native.calls.last.arguments['mode'] == 'library' &&
            native.calls.last.arguments['dataPath'] == '${Directory.systemTemp.path}/store.sqlite' &&
            native.calls.last.arguments['activeDraftId'] == 'active',
        'Library mode payload');
    await WindowBridge.selectMode('toolbox');
    check(
        native.calls.last.arguments.length == 1 &&
            native.calls.last.arguments['mode'] == 'toolbox',
        'Toolbox mode payload');
    final count = native.calls.length;
    await throws<ArgumentError>(() => WindowBridge.selectMode('unknown'));
    check(native.calls.length == count,
        'Invalid mode must never reach native channel');
  });
  await run('library.refresh-does-not-switch-mode', () async {
    await WindowBridge.refreshLibrary();
    check(native.calls.isEmpty, 'Unavailable bridge does not send refresh');
    await initialize();
    native.calls.clear();
    await WindowBridge.refreshLibrary();
    check(native.calls.single.method == 'refreshLibrary',
        'Refresh uses a dedicated event without changing sidebar mode');
    await initialize(toolbox: true);
    native.calls.clear();
    await WindowBridge.refreshLibrary();
    check(native.calls.isEmpty, 'Only the editor initiates library refresh');
  });
  await run('sidebar.event-generation-and-visibility', () async {
    final pending = Completer<dynamic>();
    final events = <String>[];
    native.behavior =
        (call) => call.method == 'ready' ? pending.future : Future.value(true);
    final older = initialize(
        toolbox: true,
        onEvent: (m, a) async {
          throw StateError('stale callback');
        });
    await initialize(onEvent: (m, a) async {
      events.add('$m:${a['mode']}:${a['visible']}');
    });
    pending.complete({'revision': 1});
    check(!await older, 'Older generation remains detached');
    await native
        .emit('sidebarStateChanged', {'mode': 'library', 'visible': false});
    await native
        .emit('sidebarStateChanged', {'mode': 'toolbox', 'visible': true});
    check(
        events.join(',') ==
            'sidebarStateChanged:library:false,sidebarStateChanged:toolbox:true',
        'Current generation receives sidebar mode and visibility');
    check(WindowBridge.latestState == null,
        'Sidebar mode does not invent document state');
  });
  await run('secondary.ready-snapshot', () async {
    final events = <String>[];
    native.behavior = (call) async => call.method == 'ready'
        ? {
            'revision': 7,
            'nested': {'x': 1}
          }
        : null;
    check(
        await initialize(
            toolbox: true,
            onEvent: (method, args) async {
              events.add(method);
              (args['nested'] as Map)['x'] = 99;
              return 'accepted';
            }),
        'Secondary ready support');
    check(WindowBridge.isToolbox && events.single == 'receiveState',
        'Ready map must dispatch receiveState');
    check(
        WindowBridge.latestState!['revision'] == 7 &&
            WindowBridge.latestState!['nested']['x'] == 1,
        'Callback mutation must not alter latest snapshot');
  });
  await run('native.all-events', () async {
    final events = <String>[], payloads = <dynamic>[];
    await initialize(onEvent: (method, args) async {
      events.add(method);
      payloads.add(args);
      return 'ack:$method';
    });
    for (final name in [
      'receiveState',
      'applyToolboxState',
      'toolboxVisibilityChanged',
      'sidebarStateChanged',
      'mainAction'
    ]) {
      final data = name == 'sidebarStateChanged'
          ? {'visible': true, 'mode': 'library'}
          : name == 'toolboxVisibilityChanged'
              ? {'visible': true}
              : name == 'mainAction'
                  ? {'action': 'undo'}
                  : {'revision': events.length};
      check(await native.emit(name, data) == 'ack:$name',
          'Native callback result must be returned');
    }
    check(
        events.join(',') ==
            'receiveState,applyToolboxState,toolboxVisibilityChanged,sidebarStateChanged,mainAction',
        'Native event routing');
    check(
        payloads.last['action'] == 'undo' &&
            WindowBridge.latestState!['revision'] == 1,
        'Non-state events must preserve latest state');
  });
  await run('primary.publish-copy', () async {
    await initialize();
    final state = <String, dynamic>{
      'document': {
        'pieces': [
          {'type': 'pea'}
        ]
      },
      'revision': 1
    };
    await WindowBridge.publish(state);
    state['document']['pieces'][0]['type'] = 'corrupted';
    final read = WindowBridge.latestState!;
    read['document']['pieces'][0]['type'] = 'also-corrupted';
    check(WindowBridge.latestState!['document']['pieces'][0]['type'] == 'pea',
        'Snapshot must be independent of caller and getter mutation');
    check(
        native.calls.last.method == 'publishState' &&
            native.calls.last.arguments['document']['pieces'][0]['type'] ==
                'pea',
        'Primary wire snapshot');
  });
  await run('secondary.publish-editState', () async {
    native.behavior = (call) async => null;
    await initialize(toolbox: true);
    await WindowBridge.publish({'selectedType': 'sunflower'});
    check(
        native.calls.last.method == 'editState' &&
            native.calls.last.arguments['selectedType'] == 'sunflower',
        'Toolbox edits must use editState');
  });
  await run('publish.native-acceptance-result', () async {
    await initialize();
    native.behavior = (call) async => true;
    check(await WindowBridge.publish({'revision': 1}) == true,
        'Primary native publish result lost');
    native.behavior = (call) async =>
        call.method == 'ready' ? null : call.arguments['accepted'];
    await initialize(toolbox: true);
    check(await WindowBridge.publish({'accepted': false}) == false,
        'Rejected toolbox edit must return false to caller');
    check(WindowBridge.supported, 'Rejected edit is not unsupported platform');
    check(await WindowBridge.publish({'accepted': true}) == true,
        'Accepted toolbox edit must return true to caller');
  });
  await run('primary.visibility', () async {
    await initialize();
    await WindowBridge.setVisible(false);
    await WindowBridge.setVisible(true);
    check(
        native.calls[1].method == 'setSidebarVisible' &&
            native.calls[1].arguments['visible'] == false,
        'Hide wire payload');
    check(native.calls[2].arguments['visible'] == true, 'Show wire payload');
  });
  await run('primary.deactivate', () async {
    await initialize();
    await WindowBridge.publish({'revision': 1});
    await WindowBridge.deactivate();
    check(
        native.calls.last.method == 'deactivate' &&
            native.calls.last.arguments == null,
        'Deactivate native method');
    check(WindowBridge.latestState == null,
        'Deactivate must clear active local snapshot');
    native.behavior = (call) async => null;
    await initialize(toolbox: true);
    await throws<StateError>(() => WindowBridge.deactivate());
    check(native.calls.last.method == 'ready',
        'Secondary must not deactivate primary');
  });
  await run('secondary.actions', () async {
    native.behavior = (call) async => null;
    await initialize(toolbox: true);
    await WindowBridge.mainAction('redo');
    check(
        native.calls.last.method == 'mainAction' &&
            native.calls.last.arguments['action'] == 'redo',
        'Action must use native map contract');
  });
  await run('role.invalid-actions', () async {
    await initialize();
    await throws<StateError>(() => WindowBridge.mainAction('undo'));
    native.behavior = (call) async => null;
    await initialize(toolbox: true);
    await throws<StateError>(() => WindowBridge.setVisible(true));
    check(
        native.calls.length == 2, 'Wrong-role requests must not reach native');
  });
  await run('ready.older-response-race', () async {
    final ready = Completer<dynamic>(), revisions = <int>[];
    native.behavior =
        (call) => call.method == 'ready' ? ready.future : Future.value(true);
    final initializing = initialize(
        toolbox: true,
        onEvent: (method, args) async {
          revisions.add(args['revision'] as int);
        });
    await native.emit('receiveState', {'revision': 3});
    ready.complete({'revision': 1});
    check(await initializing, 'Ready should complete supported');
    check(
        revisions.join(',') == '3' &&
            WindowBridge.latestState!['revision'] == 3,
        'Older ready response must not overwrite a newer event');
  });
  await run('initialize.new-generation-wins', () async {
    final ready = Completer<dynamic>();
    var oldEvents = 0, newEvents = 0;
    native.behavior =
        (call) => call.method == 'ready' ? ready.future : Future.value(true);
    final old = initialize(
        toolbox: true,
        onEvent: (m, a) async {
          oldEvents++;
        });
    check(
        await initialize(onEvent: (m, a) async {
          newEvents++;
        }),
        'New primary initialization');
    ready.complete({'revision': 1});
    check(!await old, 'Stale handshake must not reinitialize secondary');
    await native.emit('mainAction', {'action': 'undo'});
    check(
        WindowBridge.supported &&
            !WindowBridge.isToolbox &&
            oldEvents == 0 &&
            newEvents == 1,
        'Only latest generation may receive events');
  });
  await run('dispose.pending-ready', () async {
    final ready = Completer<dynamic>();
    native.behavior = (call) => ready.future;
    final pending = initialize(toolbox: true);
    WindowBridge.dispose();
    ready.complete({'revision': 1});
    check(!await pending && !WindowBridge.supported && !native.hasHandler,
        'Disposed initialization must not reinstall handler');
    check(
        WindowBridge.latestState == null, 'Disposed snapshots must be cleared');
  });
  for (final toolbox in [false, true]) {
    await run('unsupported.${toolbox ? 'secondary' : 'primary'}', () async {
      native.behavior = (call) async => throw MissingPluginException();
      check(!await initialize(toolbox: toolbox) && !WindowBridge.supported,
          'Missing plugin must be unsupported');
      await WindowBridge.publish({'revision': 1});
      await WindowBridge.setVisible(true);
      await WindowBridge.mainAction('undo');
      check(native.calls.length == 1 && !native.hasHandler,
          'Unsupported requests must remain no-ops, not fake native calls');
    });
  }
  await run('native.explicit-false', () async {
    native.behavior = (call) async => false;
    check(!await initialize() && !WindowBridge.supported && !native.hasHandler,
        'Native false must remain unsupported');
  });
  await run('initialize.platform-error-recovery', () async {
    native.behavior = (call) async =>
        throw PlatformException(code: 'denied', message: 'native failure');
    final error = await throws<PlatformException>(() => initialize());
    check(
        error.code == 'denied' && !WindowBridge.supported && !native.hasHandler,
        'Platform failure must propagate and detach incomplete handler');
    native.behavior = (call) async => true;
    check(await initialize(), 'A new initialize must recover');
  });
  await run('initialize.invalid-primary-response', () async {
    native.behavior = (call) async => null;
    await throws<StateError>(() => initialize());
    check(!WindowBridge.supported && !native.hasHandler,
        'Invalid primary handshake cannot become supported');
  });
  await run('initialize.invalid-secondary-response', () async {
    native.behavior = (call) async => ['wrong'];
    await throws<StateError>(() => initialize(toolbox: true));
    check(!WindowBridge.supported && !native.hasHandler,
        'Invalid ready snapshot cannot become supported');
  });
  await run('publish.platform-error', () async {
    await initialize();
    native.behavior =
        (call) async => throw PlatformException(code: 'transport');
    final error = await throws<PlatformException>(
        () => WindowBridge.publish({'revision': 2}));
    check(error.code == 'transport' && WindowBridge.supported,
        'Available plugin error must not be mislabeled missing plugin');
  });
  await run('publish.disappearing-plugin', () async {
    await initialize();
    native.behavior = (call) async => throw MissingPluginException();
    await WindowBridge.publish({'revision': 2});
    check(!WindowBridge.supported && !native.hasHandler,
        'Lost plugin must deactivate bridge');
    final count = native.calls.length;
    await WindowBridge.publish({'revision': 3});
    check(native.calls.length == count, 'No requests after plugin loss');
  });
  await run('native.callback-errors', () async {
    await initialize(
        onEvent: (m, a) async => throw StateError('callback rejected'));
    final error = await throws<PlatformException>(
        () => native.emit('receiveState', {'revision': 1}));
    check(
        error.message!.contains('callback rejected') && WindowBridge.supported,
        'Application callback error must return to native');
  });
  await run('native.unknown-event', () async {
    var count = 0;
    await initialize(onEvent: (m, a) async {
      count++;
    });
    await throws<MissingPluginException>(() => native.emit('unknown', null));
    check(count == 0, 'Unknown events must not be silently forwarded');
  });
  await run('native.invalid-state', () async {
    await initialize();
    await native.emit('receiveState', {'revision': 1});
    await throws<PlatformException>(
        () => native.emit('applyToolboxState', 'not a map'));
    check(WindowBridge.latestState!['revision'] == 1,
        'Invalid native snapshot must not replace last valid state');
  });
  await run('snapshot.typed-bytes', () async {
    await initialize();
    final bytes = Uint8List.fromList([1, 2, 3]);
    await WindowBridge.publish({'bytes': bytes});
    bytes[0] = 9;
    check((WindowBridge.latestState!['bytes'] as Uint8List)[0] == 1,
        'Typed bytes snapshot alias');
  });
  await run('dispose.detaches-and-reinitializes', () async {
    var old = 0, newer = 0;
    await initialize(onEvent: (m, a) async {
      old++;
    });
    WindowBridge.dispose();
    check(!native.hasHandler && !WindowBridge.supported,
        'Dispose must remove native handler');
    await throws<MissingPluginException>(() => native.emit('receiveState', {}));
    await initialize(onEvent: (m, a) async {
      newer++;
    });
    await native.emit('receiveState', {});
    check(old == 0 && newer == 1 && WindowBridge.latestState!.isEmpty,
        'Only fresh callback after dispose');
  });
  await run('old-publish-error.cannot-detach-new-engine', () async {
    final publishing = Completer<dynamic>();
    await initialize();
    native.behavior = (call) =>
        call.method == 'publishState' ? publishing.future : Future.value(true);
    final old = WindowBridge.publish({'revision': 1});
    await initialize();
    publishing.completeError(MissingPluginException());
    await old;
    check(WindowBridge.supported && native.hasHandler,
        'A stale outgoing failure detached newer initialization');
  });
  await run('ready.callback-error-cleanup', () async {
    native.behavior = (call) async => {'revision': 1};
    await throws<StateError>(() => initialize(
        toolbox: true,
        onEvent: (m, a) async => throw StateError('ready rejected')));
    check(!WindowBridge.supported && !native.hasHandler,
        'Ready callback failure must not leave active incomplete initialization');
  });
  final report = {
    'schemaVersion': 1,
    'scope':
        'Dart/native method-channel contract only; no actual native windows or cross-engine transport exercised',
    'nativePlatform': 'inMemoryMock',
    'cases': results,
    'summary': {
      'pass': results.where((r) => r['status'] == 'pass').length,
      'fail': results.where((r) => r['status'] == 'fail').length
    }
  };
  await File('${Directory.systemTemp.path}/pvz-window-bridge-report.json')
      .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
  stdout.writeln('Report ${Directory.systemTemp.path}/pvz-window-bridge-report.json');
  exit(results.any((r) => r['status'] == 'fail') ? 1 : 0);
}

class _BridgeBinding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() {
    native = NativeChannelHarness(super.createBinaryMessenger());
    return native;
  }
}

class NativeChannelHarness extends BinaryMessenger {
  final BinaryMessenger delegate;
  final calls = <MethodCall>[];
  final incoming = <String, Future<ByteData?>? Function(ByteData?)>{};
  Future<dynamic> Function(MethodCall) behavior =
      (call) async => call.method == 'initialize' ? true : null;
  NativeChannelHarness(this.delegate);
  bool get hasHandler => incoming.containsKey(WindowBridge.channel.name);
  void reset() {
    calls.clear();
    behavior = (call) async => call.method == 'initialize' ? true : null;
  }

  Future<dynamic> emit(String method, dynamic arguments) async {
    final handler = incoming[WindowBridge.channel.name];
    if (handler == null) throw MissingPluginException();
    final response = await handler(WindowBridge.channel.codec
        .encodeMethodCall(MethodCall(method, arguments)));
    if (response == null) throw MissingPluginException();
    return WindowBridge.channel.codec.decodeEnvelope(response);
  }

  @override
  Future<ByteData?> send(String channel, ByteData? message) async {
    if (channel != WindowBridge.channel.name) {
      return await delegate.send(channel, message);
    }
    final call = WindowBridge.channel.codec.decodeMethodCall(message);
    calls.add(call);
    try {
      return WindowBridge.channel.codec
          .encodeSuccessEnvelope(await behavior(call));
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      return WindowBridge.channel.codec.encodeErrorEnvelope(
          code: error.code, message: error.message, details: error.details);
    }
  }

  @override
  void setMessageHandler(
      String channel, Future<ByteData?>? Function(ByteData?)? handler) {
    if (channel != WindowBridge.channel.name) {
      delegate.setMessageHandler(channel, handler);
      return;
    }
    if (handler == null) {
      incoming.remove(channel);
    } else {
      incoming[channel] = handler;
    }
  }

  @override
  Future<void> handlePlatformMessage(
          String channel, ByteData? data, void Function(ByteData?)? callback) =>
      // ignore: deprecated_member_use
      delegate.handlePlatformMessage(channel, data, callback);
}
