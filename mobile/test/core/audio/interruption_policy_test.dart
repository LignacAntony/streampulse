import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/audio/interruption_policy.dart';

void main() {
  group('InterruptionPolicy (STR-110)', () {
    test('appel entrant pendant la lecture → pause, puis reprise à la fin', () {
      final policy = InterruptionPolicy();

      expect(
        policy.onInterruption(
          begin: true,
          isDuck: false,
          canResume: false,
          isPlaying: true,
        ),
        InterruptionAction.pause,
      );
      // Fin de l'appel avec autorisation de reprise (iOS `shouldResume`).
      expect(
        policy.onInterruption(
          begin: false,
          isDuck: false,
          canResume: true,
          isPlaying: false,
        ),
        InterruptionAction.resume,
      );
    });

    test('fin d\'interruption non reprenable → aucune reprise', () {
      final policy = InterruptionPolicy();

      policy.onInterruption(
        begin: true,
        isDuck: false,
        canResume: false,
        isPlaying: true,
      ); // pause armée
      // L'OS ne permet pas la reprise (iOS sans `shouldResume`, perte de focus
      // permanente Android → `unknown`) : on ne relance pas.
      expect(
        policy.onInterruption(
          begin: false,
          isDuck: false,
          canResume: false,
          isPlaying: false,
        ),
        InterruptionAction.none,
      );
    });

    test('interruption alors qu\'on est déjà en pause → aucune reprise auto', () {
      final policy = InterruptionPolicy();

      expect(
        policy.onInterruption(
          begin: true,
          isDuck: false,
          canResume: false,
          isPlaying: false,
        ),
        InterruptionAction.none,
      );
      expect(
        policy.onInterruption(
          begin: false,
          isDuck: false,
          canResume: true,
          isPlaying: false,
        ),
        InterruptionAction.none,
      );
    });

    test('notification transitoire en lecture → duck puis unduck', () {
      final policy = InterruptionPolicy();

      expect(
        policy.onInterruption(
          begin: true,
          isDuck: true,
          canResume: false,
          isPlaying: true,
        ),
        InterruptionAction.duck,
      );
      expect(
        policy.onInterruption(
          begin: false,
          isDuck: true,
          canResume: false,
          isPlaying: true,
        ),
        InterruptionAction.unduck,
      );
    });

    test('notification alors que rien ne joue → aucune atténuation', () {
      final policy = InterruptionPolicy();

      expect(
        policy.onInterruption(
          begin: true,
          isDuck: true,
          canResume: false,
          isPlaying: false,
        ),
        InterruptionAction.none,
      );
    });

    test('un duck n\'arme pas la reprise', () {
      final policy = InterruptionPolicy();

      policy.onInterruption(
        begin: true,
        isDuck: true,
        canResume: false,
        isPlaying: true,
      ); // duck
      expect(
        policy.onInterruption(
          begin: false,
          isDuck: false,
          canResume: true,
          isPlaying: false,
        ),
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
        policy.onInterruption(
          begin: false,
          isDuck: false,
          canResume: true,
          isPlaying: false,
        ),
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
