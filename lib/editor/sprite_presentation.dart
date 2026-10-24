import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/formation.dart';
import 'original_assets.dart';

/// Keeps the outgoing appearance visible until the requested layers are ready.
/// Stores piece metadata; decoded images remain in the shared bounded caches.
class SpritePresentation {
  SpritePresentation({
    bool Function(Piece)? isReady,
    Future<void> Function(Piece)? load,
    VoidCallback Function(Piece)? retain,
  }) : _isReady = isReady ?? OriginalAssets.pieceImagesReady,
       _load = load ?? _loadPiece,
       _retain = retain ?? OriginalAssets.retainPieceImages;

  final bool Function(Piece) _isReady;
  final Future<void> Function(Piece) _load;
  final VoidCallback Function(Piece) _retain;
  final _shown = <String, Piece>{};
  final _pending = <String, _AppearanceRequest>{};
  Iterable<Piece>? _retainedPieces;

  static Future<void> _loadPiece(Piece piece) =>
      OriginalAssets.ensurePieceImages([piece]);

  void retainOnly(Iterable<Piece> pieces) {
    if (identical(pieces, _retainedPieces)) return;
    _retainedPieces = pieces;
    final ids = pieces.map((p) => p.id).toSet();
    _shown.removeWhere((id, _) => !ids.contains(id));
    _pending.removeWhere((id, request) {
      if (ids.contains(id)) return false;
      request.release();
      return true;
    });
  }

  Piece? resolve(Piece target) {
    if (_isReady(target)) {
      _shown[target.id] = target;
      _pending.remove(target.id)?.release();
      return target;
    }
    final previous = _shown[target.id];
    final old = previous?.type == target.type ? previous : null;
    final signature =
        '${target.type}:${target.frameRow}:${target.frameCol}:'
        '${target.effects.contains('模仿者')}';
    if (_pending[target.id]?.signature != signature) {
      final request = _AppearanceRequest(
        signature,
        old == null ? () {} : _retain(old),
      );
      _pending.remove(target.id)?.release();
      _pending[target.id] = request;
      void finish() {
        request.release();
        if (identical(_pending[target.id], request)) {
          _pending.remove(target.id);
        }
      }

      unawaited(
        _load(target).then(
          (_) => finish(),
          onError: (Object error, StackTrace stack) {
            finish();
            debugPrint('Appearance loading: $error');
          },
        ),
      );
    }
    if (old == null) return null;
    return target.copy(
      frameRow: old.frameRow,
      frameCol: old.frameCol,
      effects: {
        ...target.effects.difference({'模仿者'}),
        if (old.effects.contains('模仿者')) '模仿者',
      },
    );
  }

  void clear() {
    _retainedPieces = null;
    for (final request in _pending.values) {
      request.release();
    }
    _pending.clear();
    _shown.clear();
  }
}

class _AppearanceRequest {
  _AppearanceRequest(this.signature, this._release);
  final String signature;
  final VoidCallback _release;
  bool _released = false;
  void release() {
    if (_released) return;
    _released = true;
    _release();
  }
}
