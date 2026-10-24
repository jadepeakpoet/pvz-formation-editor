import 'formation.dart';

/// Stable game state represented by the original site's appearance frames.
/// Animation-only variants remain part of the editable document.
class PlantGameState {
  static int? of(Piece p) {
    switch (p.type) {
      case 'cob':
        return p.frameRow == 0 && p.frameCol < 2 ? 0 : 1;
      case 'potato':
        return p.frameCol == 0 ? 0 : 1;
      case 'sunshroom':
        return p.frameRow > 0 && p.frameCol >= 2 ? 1 : 0;
      case 'cactus':
        return p.frameRow >= 2 ? 1 : 0;
      case 'wallnut':
        return p.frameRow == 0 ? (p.frameCol - 1).clamp(0, 2) : 0;
      case 'tallnut':
      case 'spike':
      case 'garlic':
        return p.frameCol.clamp(0, 2);
      default:
        return null;
    }
  }
}
