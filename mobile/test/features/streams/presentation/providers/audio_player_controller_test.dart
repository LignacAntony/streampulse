import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:streampulse/features/streams/presentation/providers/audio_player_controller.dart';

import '../../../../support/fake_audio_playback_service.dart';

const _now = NowPlaying(streamId: 's1', title: 'Flux test', broadcaster: 'DJ');

/// Amène le contrôleur à l'état `playing` (le manifeste a été servi au moins une
/// fois → `_hasPlayed`).
void _reachPlaying(FakeAudioPlaybackService service) {
  service.emitState(PlayerState(true, ProcessingState.ready));
}

void main() {
  group('AudioPlayerController._recover (STR-118 / STR-109)', () {
    test('lecture démarrée puis manifeste disparu → ended immédiat, notif retirée',
        () async {
      final service = FakeAudioPlaybackService();
      final controller = AudioPlayerController(
        service: service,
        isManifestUnavailable: (_) async => true,
      );
      addTearDown(controller.dispose);

      await controller.load(_now);
      _reachPlaying(service);
      await pumpEventQueue();
      expect(controller.status, PlaybackStatus.playing);

      // Le diffuseur arrête : le player émet une erreur, le manifeste ne répond
      // plus. Comme la lecture avait démarré → fin de direct, sans reconnexion.
      service.emitError(Exception('source error'));
      await pumpEventQueue();

      expect(controller.status, PlaybackStatus.ended);
      expect(service.stopped, isTrue);
      expect(service.loadCalls, 1);
    });

    test(
        'démarrage jamais joué : manifeste 409 (pas prêt) → reconnexion, pas de faux « terminé »',
        () async {
      // Le manifeste répond 409 comme s'il était terminé, mais c'est la fenêtre
      // de démarrage : `_hasPlayed` étant faux, on ne doit PAS conclure « ended ».
      final service = FakeAudioPlaybackService()..loadError = Exception('409');
      final controller = AudioPlayerController(
        service: service,
        isManifestUnavailable: (_) async => true,
      );
      addTearDown(controller.dispose);

      await controller.load(_now);
      await pumpEventQueue();

      expect(controller.status, PlaybackStatus.reconnecting);
      expect(controller.isEnded, isFalse);
    });

    test('jamais prêt : ended après épuisement des reconnexions', () {
      fakeAsync((async) {
        final service = FakeAudioPlaybackService()..loadError = Exception('409');
        final controller = AudioPlayerController(
          service: service,
          isManifestUnavailable: (_) async => true,
        );

        controller.load(_now);
        async.flushMicrotasks();
        expect(controller.status, PlaybackStatus.reconnecting);
        expect(service.loadCalls, 1);

        // Backoff 1+2+4+8 = 15 s ; à l'épuisement le manifeste répond toujours
        // 409 → verdict « terminé » (flux jamais réellement servi).
        async.elapse(const Duration(seconds: 15));
        async.flushMicrotasks();

        expect(service.loadCalls, 5); // 1 initial + 4 reconnexions
        expect(controller.status, PlaybackStatus.ended);
        expect(service.stopped, isTrue);

        controller.dispose();
      });
    });

    test('coupure réseau (sonde false) → error après épuisement', () {
      fakeAsync((async) {
        final service = FakeAudioPlaybackService()
          ..loadError = Exception('network');
        final controller = AudioPlayerController(
          service: service,
          isManifestUnavailable: (_) async => false,
        );

        controller.load(_now);
        async.flushMicrotasks();
        expect(controller.status, PlaybackStatus.reconnecting);

        async.elapse(const Duration(seconds: 15));
        async.flushMicrotasks();

        expect(service.loadCalls, 5);
        expect(controller.status, PlaybackStatus.error);
        expect(service.stopped, isTrue);

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(service.loadCalls, 5); // aucun timer résiduel

        controller.dispose();
      });
    });

    test('état résiduel idle après ended → non écrasé', () async {
      final service = FakeAudioPlaybackService();
      final controller = AudioPlayerController(
        service: service,
        isManifestUnavailable: (_) async => true,
      );
      addTearDown(controller.dispose);

      await controller.load(_now);
      _reachPlaying(service);
      await pumpEventQueue();
      service.emitError(Exception('stop'));
      await pumpEventQueue();
      expect(controller.status, PlaybackStatus.ended);

      // `idle` résiduel du player après la source error : ne doit pas faire
      // régresser « terminé » (garde dans _onPlayerState).
      service.emitState(PlayerState(false, ProcessingState.idle));
      await pumpEventQueue();
      expect(controller.status, PlaybackStatus.ended);
    });

    test('dispose() pendant l\'attente de la sonde → aucune notification',
        () async {
      final service = FakeAudioPlaybackService();
      final probe = Completer<bool>();
      final controller = AudioPlayerController(
        service: service,
        isManifestUnavailable: (_) => probe.future,
      );

      await controller.load(_now);
      _reachPlaying(service);
      await pumpEventQueue();

      var notificationsAfterDispose = 0;
      var disposed = false;
      controller.addListener(() {
        if (disposed) notificationsAfterDispose++;
      });

      service.emitError(Exception('x')); // → _recover attend la sonde (hasPlayed)
      await pumpEventQueue();

      disposed = true;
      controller.dispose();

      probe.complete(true);
      await pumpEventQueue();

      expect(notificationsAfterDispose, 0);
    });

    test('stop() arrête le service et repasse à idle', () async {
      final service = FakeAudioPlaybackService();
      final controller = AudioPlayerController(service: service);
      addTearDown(controller.dispose);

      await controller.load(_now);
      await pumpEventQueue();
      expect(controller.nowPlaying, isNotNull);

      await controller.stop();
      expect(service.stopped, isTrue);
      expect(controller.status, PlaybackStatus.idle);
      expect(controller.nowPlaying, isNull);
    });
  });
}
