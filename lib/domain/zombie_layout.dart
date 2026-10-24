import 'formation.dart';
import 'website_codec.dart';

/// The shared website/game zombie IDs are offset by 0x50.
class ZombieLayout {
  static int? gameType(String type) {
    final id = WebsiteCodec.indexForType(type);
    return id >= 0x50 && id <= 0x68 ? id - 0x50 : null;
  }

  static bool contains(Formation document) =>
      document.pieces.any((piece) => gameType(piece.type) != null);

  static double x(Piece piece) =>
      piece.websitePixelX ?? 40 + (piece.col + .5) * 80;

  // The source atlas keeps the dolphin's standing anchor for every frame.
  // Its swimming/eating frames are drawn 190 px left of that anchor; the game
  // stores the actor origin independently of this atlas placement.
  static double appearanceOffset(String type, int frameRow, int frameCol) =>
      type == 'dolphin' && frameRow == 1 && {2, 4}.contains(frameCol)
          ? 190.0 : 0.0;

  static double gameX(Piece piece) =>
      x(piece) - appearanceOffset(piece.type, piece.frameRow, piece.frameCol);

  static double editorX(String type, int frameRow, int frameCol, double gameX) =>
      gameX + appearanceOffset(type, frameRow, frameCol);

  static int column(double x) => ((x - 40) / 80).floor().clamp(0, 8);

  static List<String> positionFields(
    String type,
    int row,
    int col,
    double x, {
    int frameRow = 0,
    int frameCol = 0,
  }) =>
      [
        WebsiteCodec.indexForType(type).toRadixString(16),
        '${row + 1}',
        '${col + 1}',
        '$frameRow',
        '$frameCol',
        '0',
        '1',
        '0',
        '$x',
      ];
}
