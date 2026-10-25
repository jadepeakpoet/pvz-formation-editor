import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _EncodeNative = Size Function(Pointer<Uint8>, Int32, Int32, Int32,
    Float, Pointer<Pointer<Uint8>>);
typedef _EncodeDart = int Function(Pointer<Uint8>, int, int, int,
    double, Pointer<Pointer<Uint8>>);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

/// A single background encoder keeps disk-cache compression off the UI isolate.
class ThumbnailEncoder {
  static Future<SendPort>? _worker;
  @visibleForTesting
  static String? libraryPathOverride;

  static Future<(String, Uint8List)> encode(ui.Image image) async {
    if (!Platform.isWindows) {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      return ('png', png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
    }
    final raw = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
    final bytes = raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes);
    final worker = await (_worker ??= _start());
    final reply = ReceivePort();
    try {
      worker.send([reply.sendPort, TransferableTypedData.fromList([bytes]),
        image.width, image.height]);
      final result = await reply.first.timeout(const Duration(seconds: 30));
      if (result is! TransferableTypedData) throw StateError('WebP encoding failed: $result');
      return ('webp', result.materialize().asUint8List());
    } finally {
      reply.close();
    }
  }

  static Future<SendPort> _start() async {
    final ready = ReceivePort();
    await Isolate.spawn(_encodeLoop, [ready.sendPort,
      libraryPathOverride ?? '${File(Platform.resolvedExecutable).parent.path}/pvz_webp.dll']);
    final result = await ready.first;
    ready.close();
    if (result is! SendPort) throw StateError('WebP encoder unavailable: $result');
    return result;
  }

  static void _encodeLoop(List<Object> init) {
    final ready = init[0] as SendPort;
    try {
      final library = DynamicLibrary.open(init[1] as String);
      final encode = library.lookupFunction<_EncodeNative, _EncodeDart>('PvzWebPEncodeRGBA');
      final release = library.lookupFunction<_FreeNative, _FreeDart>('PvzWebPFree');
      final requests = ReceivePort();
      ready.send(requests.sendPort);
      requests.listen((request) {
        final values = request as List;
        final reply = values[0] as SendPort;
        Pointer<Uint8>? input;
        Pointer<Pointer<Uint8>>? output;
        try {
          final bytes = (values[1] as TransferableTypedData).materialize().asUint8List();
          final width = values[2] as int, height = values[3] as int;
          if (bytes.length != width * height * 4 || width != 256 || height != 192) {
            throw const FormatException('Thumbnail dimensions');
          }
          input = calloc<Uint8>(bytes.length);
          input.asTypedList(bytes.length).setAll(0, bytes);
          output = calloc<Pointer<Uint8>>();
          final size = encode(input, width, height, width * 4, 88, output);
          if (size == 0 || output.value == nullptr) throw StateError('libwebp encoding failed');
          reply.send(TransferableTypedData.fromList([output.value.asTypedList(size)]));
        } catch (error) {
          reply.send('$error');
        } finally {
          if (output != null) {
            if (output.value != nullptr) release(output.value.cast());
            calloc.free(output);
          }
          if (input != null) calloc.free(input);
        }
      });
    } catch (error) {
      ready.send('$error');
    }
  }
}
