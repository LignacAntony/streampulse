import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/audio/volume_level.dart';

void main() {
  group('VolumeLevel', () {
    test('sans atténuation, le niveau appliqué est celui de l\'auditeur', () {
      expect(const VolumeLevel(user: 0.6).effective, 0.6);
    });

    test('l\'atténuation est un facteur, pas un niveau absolu', () {
      // Atténuer à 0,4 en dur remonterait le son de quelqu'un qui écoute à 0,2.
      const quiet = VolumeLevel(user: 0.2, ducked: true);
      expect(quiet.effective, closeTo(0.08, 1e-9));
      expect(quiet.effective, lessThan(quiet.user));
    });

    // Le bug que cet objet existe pour empêcher : la version précédente
    // capturait le volume du lecteur avant d'atténuer et le restaurait après.
    // Un réglage fait pendant l'interruption était donc écrasé — le son de
    // l'auditeur remontait tout seul à la fin de sa notification.
    test('un réglage fait pendant une atténuation survit à sa levée', () {
      const before = VolumeLevel(user: 0.8);

      final ducked = before.withDucked(true);
      final adjusted = ducked.withUser(0.3); // l'auditeur baisse pendant
      final restored = adjusted.withDucked(false);

      expect(restored.user, 0.3);
      expect(restored.effective, 0.3);
    });

    test('régler le volume ne lève pas l\'atténuation en cours', () {
      final level = const VolumeLevel(user: 1).withDucked(true).withUser(0.5);

      expect(level.ducked, isTrue);
      expect(level.effective, closeTo(0.2, 1e-9));
    });

    test('les valeurs hors bornes sont ramenées dans [0, 1]', () {
      // just_audio accepte au-delà de 1 (amplification) ; une valeur venue d'un
      // magasin de préférences trafiqué ne doit pas saturer le son.
      expect(const VolumeLevel().withUser(4).user, 1);
      expect(const VolumeLevel().withUser(-2).user, 0);
    });

    test('le silence reste silencieux, atténué ou non', () {
      const muted = VolumeLevel(user: 0);
      expect(muted.effective, 0);
      expect(muted.withDucked(true).effective, 0);
    });

    test('l\'égalité porte sur le réglage ET l\'atténuation', () {
      expect(const VolumeLevel(user: 0.5), const VolumeLevel(user: 0.5));
      expect(
        const VolumeLevel(user: 0.5),
        isNot(const VolumeLevel(user: 0.5, ducked: true)),
      );
    });
  });
}
