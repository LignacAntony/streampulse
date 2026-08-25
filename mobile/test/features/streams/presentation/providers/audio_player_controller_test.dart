import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:streampulse/features/streams/domain/entities/manifest_status.dart';
import 'package:streampulse/features/streams/presentation/providers/audio_player_controller.dart';

import '../../../../support/fake_audio_playback_service.dart';

const _now = NowPlaying(streamId: 's1', title: 'Flux test', broadcaster: 'DJ');

/// Amène le contrôleur à l'état `playing`.
void _reachPlaying(FakeAudioPlaybackService service) {
  service.emitState(PlayerState(true, ProcessingState.ready));
}

void main() {
  group('AudioPlayerController._recover (STR-118 / STR-109 / STR-229)', () {
    test(
        'flux déjà terminé, jamais joué → ended immédiat, sans consommer le backoff',
        () {
      // Le cas que STR-229 corrige : ouvrir un direct fini depuis une liste
      // Découvrir périmée. Le serveur le sait (`stream_not_live`), le contrôleur
      // n'a plus à le deviner à partir de « la lecture avait-elle démarré ? ».
      //
      // fakeAsync ici plutôt que async/await : l'assertion qui compte n'est pas
      // seulement le verdict, c'est qu'il tombe **sans écouler de temps**. Avant,
      // ce scénario coûtait 15 s de « Reconnexion… » (backoff 1+2+4+8).
      fakeAsync((async) {
        final service = FakeAudioPlaybackService()..loadError = Exception('409');
        final controller = AudioPlayerController(
          service: service,
          manifestStatus: (_) async => ManifestStatus.ended,
        );

        controller.load(_now);
        async.flushMicrotasks();

        expect(controller.status, PlaybackStatus.ended);
        expect(service.stopped, isTrue);
        expect(service.loadCalls, 1); // aucune reconnexion tentée

        // Et aucun timer résiduel : rien ne doit repartir après coup.
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        expect(service.loadCalls, 1);
        expect(controller.status, PlaybackStatus.ended);

        controller.dispose();
      });
    });

    test('lecture démarrée puis flux terminé → ended immédiat, notif retirée',
        () async {
      final service = FakeAudioPlaybackService();
      final controller = AudioPlayerController(
        service: service,
        manifestStatus: (_) async => ManifestStatus.ended,
      );
      addTearDown(controller.dispose);

      await controller.load(_now);
      _reachPlaying(service);
      await pumpEventQueue();
      expect(controller.status, PlaybackStatus.playing);

      // Le diffuseur arrête : le player émet une erreur et le serveur confirme
      // qu'il n'y a plus de session → fin de direct, sans reconnexion.
      service.emitError(Exception('source error'));
      await pumpEventQueue();

      expect(controller.status, PlaybackStatus.ended);
      expect(service.stopped, isTrue);
      expect(service.loadCalls, 1);
    });

    test('manifeste pas encore prêt → reconnexion, pas de faux « terminé »',
        () async {
      // Fenêtre de démarrage (~10 s) : le serveur répond 409 lui aussi, mais avec
      // `manifest_not_ready`. Conclure « terminé » ici couperait un direct qui
      // démarre — c'est l'erreur que l'ambiguïté rendait possible.
      final service = FakeAudioPlaybackService()..loadError = Exception('409');
      final controller = AudioPlayerController(
        service: service,
        manifestStatus: (_) async => ManifestStatus.notReady,
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
          manifestStatus: (_) async => ManifestStatus.notReady,
        );

        controller.load(_now);
        async.flushMicrotasks();
        expect(controller.status, PlaybackStatus.reconnecting);
        expect(service.loadCalls, 1);

        // Backoff 1+2+4+8 = 15 s ; à l'épuisement le manifeste n'est toujours pas
        // servi (diffuseur qui a démarré sans jamais pousser d'audio) → verdict
        // « terminé », comme avant STR-229.
        async.elapse(const Duration(seconds: 15));
        async.flushMicrotasks();

        expect(service.loadCalls, 5); // 1 initial + 4 reconnexions
        expect(controller.status, PlaybackStatus.ended);
        expect(service.stopped, isTrue);

        controller.dispose();
      });
    });

    test('coupure réseau (verdict indéterminé) → error après épuisement', () {
      fakeAsync((async) {
        final service = FakeAudioPlaybackService()
          ..loadError = Exception('network');
        final controller = AudioPlayerController(
          service: service,
          manifestStatus: (_) async => ManifestStatus.unknown,
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

    test('manifeste servi mais lecture en échec → error, pas ended', () {
      // Le serveur sert le manifeste : le problème est côté réseau ou lecteur,
      // pas côté direct. Annoncer « terminé » induirait l'auditeur en erreur.
      fakeAsync((async) {
        final service = FakeAudioPlaybackService()
          ..loadError = Exception('decoder');
        final controller = AudioPlayerController(
          service: service,
          manifestStatus: (_) async => ManifestStatus.available,
        );

        controller.load(_now);
        async.elapse(const Duration(seconds: 15));
        async.flushMicrotasks();

        expect(controller.status, PlaybackStatus.error);
        expect(controller.isEnded, isFalse);

        controller.dispose();
      });
    });

    test('état résiduel idle après ended → non écrasé', () async {
      final service = FakeAudioPlaybackService();
      final controller = AudioPlayerController(
        service: service,
        manifestStatus: (_) async => ManifestStatus.ended,
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
      final probe = Completer<ManifestStatus>();
      final controller = AudioPlayerController(
        service: service,
        manifestStatus: (_) => probe.future,
      );

      await controller.load(_now);
      _reachPlaying(service);
      await pumpEventQueue();

      var notificationsAfterDispose = 0;
      var disposed = false;
      controller.addListener(() {
        if (disposed) notificationsAfterDispose++;
      });

      service.emitError(Exception('x')); // → _recover attend la sonde
      await pumpEventQueue();

      disposed = true;
      controller.dispose();

      probe.complete(ManifestStatus.ended);
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

    test('stop() pendant la sonde → la reprise caduque ne rebloque pas l\'état',
        () async {
      final service = FakeAudioPlaybackService();
      final probe = Completer<ManifestStatus>();
      final controller = AudioPlayerController(
        service: service,
        manifestStatus: (_) => probe.future,
      );
      addTearDown(controller.dispose);

      await controller.load(_now);
      _reachPlaying(service);
      await pumpEventQueue();
      service.emitError(Exception('x')); // _recover attend la sonde
      await pumpEventQueue();

      await controller.stop(); // l'utilisateur ferme le lecteur pendant la sonde
      probe.complete(ManifestStatus.available); // la sonde se résout après coup
      await pumpEventQueue();

      // La reprise doit avorter (flux courant changé) et laisser l'état à idle,
      // pas le rebloquer sur « reconnexion ».
      expect(controller.status, PlaybackStatus.idle);
    });

    test('sans sonde câblée → reconnexions bornées puis error', () {
      // Le paramètre est optionnel (widget tests). Sans lui, aucun verdict
      // serveur n'est disponible : le contrôleur ne doit rien inventer.
      fakeAsync((async) {
        final service = FakeAudioPlaybackService()..loadError = Exception('x');
        final controller = AudioPlayerController(service: service);

        controller.load(_now);
        async.elapse(const Duration(seconds: 15));
        async.flushMicrotasks();

        expect(service.loadCalls, 5);
        expect(controller.status, PlaybackStatus.error);

        controller.dispose();
      });
    });
  });
}
