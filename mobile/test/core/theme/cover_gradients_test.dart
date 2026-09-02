import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/theme/cover_gradients.dart';

void main() {
  group('stableColorIndex', () {
    test('déterministe : même id → même index à chaque appel', () {
      const id = 'abc-123-def';
      final a = stableColorIndex(id, 6);
      final b = stableColorIndex(id, 6);
      expect(a, b);
    });

    test('toujours dans les bornes de la palette', () {
      for (final id in ['', 'x', 'très-long-identifiant-de-playlist-🎵']) {
        final idx = stableColorIndex(id, 6);
        expect(idx, inInclusiveRange(0, 5));
      }
    });

    test('ne dépend pas de String.hashCode (dérive des codeUnits)', () {
      // Deux chaînes distinctes de mêmes unités de code dans un ordre différent
      // donnent le même index (somme commutative) — preuve qu'on somme les
      // codeUnits et qu'on n'utilise pas hashCode.
      expect(stableColorIndex('ab', 6), stableColorIndex('ba', 6));
    });
  });

  test('playlistCoverGradient : stable pour un id donné', () {
    final g1 = playlistCoverGradient('playlist-42');
    final g2 = playlistCoverGradient('playlist-42');
    expect(g1, same(g2));
    expect(playlistCoverGradients, contains(g1));
  });
}
