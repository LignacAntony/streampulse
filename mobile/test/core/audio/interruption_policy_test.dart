import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/audio/interruption_policy.dart';

void main() {
  group('InterruptionPolicy (STR-110)', () {
    test('appel entrant pendant la lecture → pause, puis reprise à la fin', () {
      final policy = InterruptionPolicy();

      expect(
        policy.onInterruption(begin: true, isDuck: false, isPlaying: true),
        InterruptionAction.pause,
      );
      // Fin de l'appel : on reprend (c'est nous qui avions mis en pause).
      expect(
        policy.onInterruption(begin: false, isDuck: false, isPlaying: false),
        InterruptionAction.resume,
      );
    });

    test('interruption alors qu\'on est déjà en pause → aucune reprise auto', () {
      final policy = InterruptionPolicy();

      // Rien ne jouait quand l'appel arrive → on ne touche à rien.
      expect(
        policy.onInterruption(begin: true, isDuck: false, isPlaying: false),
        InterruptionAction.none,
      );
      // ...donc à la fin non plus (l'utilisateur avait mis en pause lui-même).
      expect(
        policy.onInterruption(begin: false, isDuck: false, isPlaying: false),
        InterruptionAction.none,
      );
    });

    test('notification transitoire → duck puis unduck (pas de pause)', () {
      final policy = InterruptionPolicy();

      expect(
        policy.onInterruption(begin: true, isDuck: true, isPlaying: true),
        InterruptionAction.duck,
      );
      expect(
        policy.onInterruption(begin: false, isDuck: true, isPlaying: true),
        InterruptionAction.unduck,
      );
    });

    test('un duck ne déclenche pas de reprise (n\'arme pas la pause)', () {
      final policy = InterruptionPolicy();

      policy.onInterruption(begin: true, isDuck: true, isPlaying: true); // duck
      // Fin d'une interruption « pause » qui n'a jamais eu lieu → rien.
      expect(
        policy.onInterruption(begin: false, isDuck: false, isPlaying: false),
        InterruptionAction.none,
      );
    });

    test('casque débranché en lecture → pause, sans reprise auto ensuite', () {
      final policy = InterruptionPolicy();

      expect(
        policy.onBecomingNoisy(isPlaying: true),
        InterruptionAction.pause,
      );
      // Une fin d'interruption ne doit pas relancer le son sur le haut-parleur.
      expect(
        policy.onInterruption(begin: false, isDuck: false, isPlaying: false),
        InterruptionAction.none,
      );
    });

    test('casque débranché à l\'arrêt → aucune action', () {
      final policy = InterruptionPolicy();

      expect(
        policy.onBecomingNoisy(isPlaying: false),
        InterruptionAction.none,
      );
    });
  });
}
