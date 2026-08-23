import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/audio/listening_clock.dart';

/// Instants fixes : l'horloge ne lit jamais l'heure elle-même, c'est ce qui la
/// rend vérifiable sans attendre.
final _t0 = DateTime(2026, 8, 20, 10, 0, 0);
DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

void main() {
  group('ListeningClock', () {
    test('ne compte rien avant le premier démarrage', () {
      final clock = ListeningClock();
      expect(clock.elapsedAt(_at(60)), Duration.zero);
      expect(clock.running, isFalse);
    });

    test('compte le temps écoulé depuis le démarrage', () {
      final clock = ListeningClock()..start(_t0);
      expect(clock.elapsedAt(_at(30)), const Duration(seconds: 30));
      expect(clock.running, isTrue);
    });

    test('cumule les tranches de part et d\'autre d\'une pause', () {
      final clock = ListeningClock()..start(_t0);
      clock.pause(_at(10));
      // Rien ne s'écoule pendant la pause, même si le temps passe.
      expect(clock.elapsedAt(_at(100)), const Duration(seconds: 10));

      clock.start(_at(100));
      expect(clock.elapsedAt(_at(105)), const Duration(seconds: 15));
    });

    // Le lecteur émet plusieurs événements pour un même état : un `start`
    // répété qui déplacerait l'origine ferait reculer le temps affiché.
    test('un démarrage répété ne déplace pas l\'origine', () {
      final clock = ListeningClock()..start(_t0);
      clock.start(_at(20));
      clock.start(_at(40));

      expect(clock.elapsedAt(_at(60)), const Duration(seconds: 60));
    });

    test('une pause répétée ne cumule pas deux fois', () {
      final clock = ListeningClock()..start(_t0);
      clock.pause(_at(10));
      clock.pause(_at(50));

      expect(clock.elapsedAt(_at(90)), const Duration(seconds: 10));
    });

    test('reset repart de zéro, y compris pendant une lecture', () {
      final clock = ListeningClock()..start(_t0);
      clock.reset();

      expect(clock.elapsedAt(_at(30)), Duration.zero);
      expect(clock.running, isFalse);
    });

    // Une horloge murale peut reculer (NTP, fuseau, réglage manuel). Un temps
    // d'écoute qui décroît serait pire que figé.
    test('une horloge qui recule ne produit pas de durée négative', () {
      final clock = ListeningClock()..start(_at(100));

      expect(clock.elapsedAt(_at(40)), Duration.zero);

      clock.pause(_at(40));
      clock.start(_at(40));
      expect(clock.elapsedAt(_at(50)), const Duration(seconds: 10));
    });

    // C'est la raison d'être de cette horloge : le contrôleur recharge l'URL à
    // chaque reprise après erreur (STR-118), ce qui remettrait la position du
    // lecteur à zéro. Le temps d'écoute, lui, doit traverser la coupure.
    test('une reconnexion suspend le décompte sans le perdre', () {
      final clock = ListeningClock()..start(_t0);
      clock.pause(_at(120)); // perte réseau
      clock.start(_at(125)); // flux repris

      expect(clock.elapsedAt(_at(130)), const Duration(seconds: 125));
    });
  });
}
