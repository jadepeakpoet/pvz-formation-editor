import 'formation.dart';
import 'website_codec.dart';
import 'zombie_layout.dart';

/// Extracts the executable layout without modifying the editor document.
/// Toolkit's website importer skips IDs above 0x32 and ignores visual styling.
class PlacementLayout {
  final Formation document;
  final int skippedObjects, simplifiedAppearances;
  const PlacementLayout._(
    this.document,
    this.skippedObjects,
    this.simplifiedAppearances,
  );

  String get notice {
    final parts = <String>[
      if (skippedObjects > 0) '已忽略 $skippedObjects 个僵尸或装饰对象',
      if (simplifiedAppearances > 0) '已忽略 $simplifiedAppearances 个对象的图像特效或外观变换',
    ];
    return parts.join('；');
  }

  static String completion(
    String action,
    Formation source, {
    bool game = false,
  }) {
    final detail = prepare(source, includeZombies: game).notice;
    return detail.isEmpty ? action : '$action（$detail）';
  }

  static PlacementLayout prepare(
    Formation source, {
    bool includeZombies = false,
  }) {
    var skipped = 0, simplified = 0;
    final pieces = <Piece>[];
    for (final piece in source.pieces) {
      final websiteId = WebsiteCodec.indexForType(piece.type);
      final zombie =
          includeZombies && ZombieLayout.gameType(piece.type) != null;
      final keepChewFlash = includeZombies && !zombie &&
          websiteId >= 0 && websiteId < WebsiteCodec.plantIds.length &&
          piece.effects.contains('高亮');
      if (websiteId > 0x32 && !zombie) {
        skipped++;
        continue;
      }
      if (websiteId < 0) {
        pieces.add(piece);
        continue;
      }
      final styled = piece.scale != 1 ||
          piece.opacity != 1 ||
          piece.flipped ||
          piece.flippedVertical ||
          piece.layer != piece.spec.layer ||
          !zombie &&
              (piece.websitePixelX != null || piece.websitePixelY != null) ||
          piece.effects.any((effect) => effect != '模仿者' &&
              !(keepChewFlash && effect == '高亮'));
      if (!styled) {
        pieces.add(piece);
        continue;
      }
      simplified++;
      final data = piece.toJson()
        ..remove('websiteEffects')
        ..remove('websitePixelX')
        ..remove('websitePixelY')
        ..['layer'] = piece.spec.layer
        ..['scale'] = 1.0
        ..['opacity'] = 1.0
        ..['flipped'] = false
        ..['flippedVertical'] = false
        ..['effects'] = [if (piece.effects.contains('模仿者')) '模仿者',
          if (keepChewFlash) '高亮'];
      if (!zombie) data.remove('websiteFields');
      // Keep the final frame: mushroom sleep and stable plant states are
      // interpreted by the game writer, independently of decorative styling.
      pieces.add(Piece.fromJson(data));
    }
    return PlacementLayout._(
      skipped == 0 && simplified == 0 ? source : source.copy(pieces: pieces),
      skipped,
      simplified,
    );
  }
}
