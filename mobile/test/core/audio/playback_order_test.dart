import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/audio/playback_order.dart';

void main() {
  group('PlaybackOrder — ordre naturel (US-05-05)', () {
    test('avance et recule d\'un rang', () {
      final order = PlaybackOrder.natural(3);

      expect(order.relative(0, 1, wrap: false), 1);
      expect(order.relative(2, -1, wrap: false), 1);
    });

    test('sans répétition, les extrémités n\'ont pas de suite', () {
      final order = PlaybackOrder.natural(3);

      expect(order.relative(2, 1, wrap: false), isNull);
      expect(order.relative(0, -1, wrap: false), isNull);
    });

    test('la répétition de la file reboucle des deux côtés', () {
      final order = PlaybackOrder.natural(3);

      expect(order.relative(2, 1, wrap: true), 0);
      expect(order.relative(0, -1, wrap: true), 2);
    });
  });

  group('PlaybackOrder — ordre mélangé (US-05-05)', () {
    // La file d'origine est [0, 1, 2] ; le lecteur la jouera 2, 0, 1.
    const shuffled = PlaybackOrder([2, 0, 1]);

    test('le rang affiché suit l\'ordre de lecture, pas la playlist', () {
      expect(shuffled.positionOf(2), 0);
      expect(shuffled.positionOf(1), 2);
    });

    test('le saut suit l\'ordre mélangé et non l\'index de la playlist', () {
      // Depuis la piste 2 (1re jouée), la suivante est la piste 0.
      expect(shuffled.relative(2, 1, wrap: false), 0);
      expect(shuffled.relative(0, -1, wrap: false), 2);
    });

    test('la dernière piste jouée n\'a de suite qu\'avec la répétition', () {
      expect(shuffled.relative(1, 1, wrap: false), isNull);
      expect(shuffled.relative(1, 1, wrap: true), 2);
    });
  });

  group('PlaybackOrder — cas limites', () {
    test('file vide : aucun saut', () {
      expect(PlaybackOrder.empty.relative(0, 1, wrap: true), isNull);
      expect(PlaybackOrder.empty.isEmpty, isTrue);
    });

    test('piste absente de l\'ordre : aucun saut plutôt qu\'un saut faux', () {
      const order = PlaybackOrder([0, 1]);

      expect(order.positionOf(7), -1);
      expect(order.relative(7, 1, wrap: true), isNull);
    });

    test('file d\'une seule piste : la répétition la redonne', () {
      final order = PlaybackOrder.natural(1);

      expect(order.relative(0, 1, wrap: false), isNull);
      expect(order.relative(0, 1, wrap: true), 0);
    });
  });
}
