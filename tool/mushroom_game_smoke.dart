// Runs in a Flutter engine. Tests the same GameBridge payload used by all UIs.
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pvz_formation_editor/domain/formation.dart';
import 'package:pvz_formation_editor/domain/formation_exchange.dart';
import 'package:pvz_formation_editor/platform/game_bridge.dart';

late GameMessenger messenger;

class Binding extends WidgetsFlutterBinding {
  @override
  BinaryMessenger createBinaryMessenger() =>
      messenger = GameMessenger(super.createBinaryMessenger());
}

class GameMessenger extends BinaryMessenger {
  GameMessenger(this.delegate);
  final BinaryMessenger delegate;
  Map? target;
  @override
  Future<ByteData?> send(String channel, ByteData? data) async {
    if (channel != 'pvz_formation_editor/game') {
      return delegate.send(channel, data);
    }
    const codec = StandardMethodCodec();
    final call = codec.decodeMethodCall(data);
    final args = call.arguments as Map;
    target = args['target'] as Map;
    return codec.encodeSuccessEnvelope({
      'after': {'pid': 1051, 'version': 'test', ...target!}
    });
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      delegate.setMessageHandler(channel, handler);
  @override
  Future<void> handlePlatformMessage(String channel, ByteData? data,
      PlatformMessageResponseCallback? callback) async {
    ServicesBinding.instance.channelBuffers.push(channel, data, callback ?? (_) {});
  }
}

void check(bool condition, String reason) {
  if (!condition) throw StateError(reason);
}

Future<void> main() async {
  Binding();
  final before = GameFormationSnapshot.fromJson({
    'pid': 1051,
    'version': 'test',
    'map': 'pool',
    'sunValue': 5000,
    'pieces': []
  });
  try {
    for (final type in Piece.mushroomTypes) {
      final piece = Piece(id: type, type: type, row: 0, col: 0, layer: 10,
          frameRow: Piece.defaultPlantFrame(type).$1);
      final document = Formation(pieces: [piece]);
      final after = await GameBridge.applyFormation(1051, document, before);
      final shouldSleep = !{'gloom', 'fume', 'magnet'}.contains(type);
      check(
          (messenger.target!['pieces'] as List).single['asleep'] == shouldSleep,
          'Default $type write matches visible state');
      check(after.formation.pieces.single.frameRow == (shouldSleep ? 0 : 1),
          'Readback $type appearance');
      final awake = piece.copy(frameRow: 1);
      await GameBridge.applyFormation(
          1051, document.copy(pieces: [awake]), before);
      check((messenger.target!['pieces'] as List).single['asleep'] == false,
          'Explicit $type wake state');
      final sleeping = FormationExchange.decode(FormationExchange.encode(
          document.copy(pieces: [awake.copy(frameRow: 0)])));
      await GameBridge.applyFormation(1051, sleeping, before);
      check((messenger.target!['pieces'] as List).single['asleep'] == true,
          'Toolkit exchange keeps explicit $type sleep state');
    }
    stdout.writeln(
        'PASS: all ten mushrooms default / explicit awake / sleep, actual GameBridge payload and snapshot appearance');
    exit(0);
  } catch (e, st) {
    stderr.writeln('$e\n$st');
    exit(1);
  }
}
