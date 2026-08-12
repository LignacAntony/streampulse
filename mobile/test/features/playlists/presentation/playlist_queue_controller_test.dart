import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:streampulse/core/constants/api_constants.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist_track.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_queue_controller.dart';

import '../../../support/fake_queue_playback_service.dart';

PlaylistTrack _track(String id, String title, int position) => PlaylistTrack(
      id: id,
      title: title,
      artist: 'Neon Lights',
      durationS: 214,
      position: position,
    );

final _tracks = [
  _track('t1', 'Midnight Drive', 0),
  _track('t2', 'Sunrise', 1),
  _track('t3', 'Afterglow', 2),
];

/// Contrôleur sous test + fake associé. [tokens] permet d'observer les demandes
/// de rotation d'access token.
({PlaylistQueueController controller, FakeQueuePlaybackService service})
    _build({
  List<bool>? tokens,
  Future<void> Function()? stopLive,
}) {
  final service = FakeQueuePlaybackService();
  final controller = PlaylistQueueController(
    service: service,
    token: ({bool forceRefresh = false}) async {
      tokens?.add(forceRefresh);
      return 'jwt-access';
    },
    stopLive: stopLive,
  );
  addTearDown(controller.dispose);
  addTearDown(service.dispose);
  return (controller: controller, service: service);
}

Future<void> _play(
  PlaylistQueueController controller, {
  int startIndex = 0,
  List<PlaylistTrack>? tracks,
}) {
  return controller.play(
    playlistId: 'p-1',
    playlistName: 'My Favorites',
    tracks: tracks ?? _tracks,
    startIndex: startIndex,
  );
}

void main() {
  group('PlaylistQueueController — lancement (US-05-04)', () {
    test('charge la file entière, authentifiée, et démarre la lecture',
        () async {
      final t = _build();

      await _play(t.controller);

      expect(t.service.loadCalls, 1);
      expect(t.service.playCalls, 1);
      expect(
        t.service.lastItems.map((i) => i.id).toList(),
        ['t1', 't2', 't3'],
      );
      // Les fichiers d'une bibliothèque sont privés : sans en-tête, le serveur
      // répondrait 401 et rien ne jouerait.
      expect(t.service.lastHeaders['Authorization'], 'Bearer jwt-access');
      expect(t.service.lastItems.first.url, ApiConstants.trackStream('t1'));
      expect(t.service.lastItems.first.duration, const Duration(seconds: 214));
      expect(t.controller.hasQueue, isTrue);
      expect(t.controller.playlistName, 'My Favorites');
    });

    test('démarre à la piste demandée (appui sur une ligne de la playlist)',
        () async {
      final t = _build();

      await _play(t.controller, startIndex: 2);

      expect(t.service.lastInitialIndex, 2);
      expect(t.controller.currentIndex, 2);
      expect(t.controller.currentTrack?.id, 't3');
    });

    test('arrête le direct avant de prendre le lecteur partagé', () async {
      var liveStopped = false;
      final t = _build(stopLive: () async => liveStopped = true);

      await _play(t.controller);

      expect(liveStopped, isTrue);
    });

    test('une playlist vide ne lance rien', () async {
      final t = _build();

      await _play(t.controller, tracks: const []);

      expect(t.service.loadCalls, 0);
      expect(t.controller.hasQueue, isFalse);
    });
  });

  group('PlaylistQueueController — file d\'attente', () {
    test('l\'enchaînement automatique fait suivre la piste courante', () async {
      final t = _build();
      await _play(t.controller);

      // C'est le lecteur natif qui enchaîne : le contrôleur l'apprend par
      // currentIndexStream, pas en décidant lui-même.
      t.service.emitIndex(1);
      await pumpEventQueue();

      expect(t.controller.currentIndex, 1);
      expect(t.controller.currentTrack?.title, 'Sunrise');
      // Aucun rechargement : la file était déjà dans le lecteur.
      expect(t.service.loadCalls, 1);
    });

    test('sauter à une piste la demande au lecteur et relance', () async {
      final t = _build();
      await _play(t.controller);
      t.service.emitState(PlayerState(true, ProcessingState.ready));
      await pumpEventQueue();

      await t.controller.skipTo(2);

      expect(t.service.skips, [2]);
      expect(t.controller.currentIndex, 2);
    });

    test('un index hors file est ignoré', () async {
      final t = _build();
      await _play(t.controller);

      await t.controller.skipTo(9);

      expect(t.service.skips, isEmpty);
      expect(t.controller.currentIndex, 0);
    });

    test('un état résiduel du lecteur n\'efface pas la fin de file', () async {
      final t = _build();
      await _play(t.controller);
      t.service.emitState(PlayerState(false, ProcessingState.completed));
      await pumpEventQueue();
      expect(t.controller.isEnded, isTrue);

      // `idle` émis juste après `completed` (libération de la source) : sans
      // garde, le mini-player « terminée » et son bouton de relance
      // disparaîtraient.
      t.service.emitState(PlayerState(false, ProcessingState.idle));
      await pumpEventQueue();

      expect(t.controller.isEnded, isTrue);
      expect(t.controller.hasQueue, isTrue);
    });

    test('relancer une file déjà en cours ne fait pas clignoter le lecteur',
        () async {
      // Le direct qu'on arrête émet un `idle` alors que la file précédente est
      // encore affichée : `hasQueue` doit rester vrai sur toute la bascule,
      // sinon PlayerBar retire puis remet le mini-player.
      final service = FakeQueuePlaybackService();
      final controller = PlaylistQueueController(
        service: service,
        token: ({bool forceRefresh = false}) async => 'jwt-access',
        stopLive: () async =>
            service.emitState(PlayerState(false, ProcessingState.idle)),
      );
      addTearDown(controller.dispose);
      addTearDown(service.dispose);
      final t = (controller: controller, service: service);

      await _play(t.controller);
      t.service.emitState(PlayerState(true, ProcessingState.ready));
      await pumpEventQueue();

      final seen = <bool>[];
      t.controller.addListener(() => seen.add(t.controller.hasQueue));
      await _play(t.controller);
      await pumpEventQueue();

      expect(seen, isNotEmpty);
      expect(seen.contains(false), isFalse,
          reason: 'la file ne doit jamais paraître inactive pendant la bascule');
    });

    test('la fin de la dernière piste termine la file', () async {
      final t = _build();
      await _play(t.controller);

      t.service.emitState(PlayerState(false, ProcessingState.completed));
      await pumpEventQueue();

      expect(t.controller.status, PlaybackStatus.ended);
      // La file reste affichée : l'utilisateur peut la relancer ou y sauter.
      expect(t.controller.hasQueue, isTrue);
    });

    test('sauter à une piste après la fin recharge la file', () async {
      final t = _build();
      await _play(t.controller);
      t.service.emitState(PlayerState(false, ProcessingState.completed));
      await pumpEventQueue();

      await t.controller.skipTo(1);

      // La source native est épuisée : un simple seek ne relancerait rien.
      expect(t.service.loadCalls, 2);
      expect(t.service.lastInitialIndex, 1);
    });

    test('hasNext / hasPrevious bornent la navigation', () async {
      final t = _build();
      await _play(t.controller);

      expect(t.controller.hasPrevious, isFalse);
      expect(t.controller.hasNext, isTrue);

      t.service.emitIndex(2);
      await pumpEventQueue();

      expect(t.controller.hasPrevious, isTrue);
      expect(t.controller.hasNext, isFalse);
    });
  });

  group('PlaylistQueueController — reprise après erreur', () {
    /// Laisse filer le backoff (1/2/4 s) sans attendre en temps réel.
    Future<void> elapse(FakeAsync async, {int seconds = 10}) async {
      async.elapse(Duration(seconds: seconds));
      async.flushMicrotasks();
    }

    test('la reprise attend le backoff, force UN refresh et garde la position',
        () {
      fakeAsync((async) {
        final tokens = <bool>[];
        final t = _build(tokens: tokens);
        _play(t.controller);
        async.flushMicrotasks();
        expect(tokens, [false]);

        // L'auditeur était à 30 s de la piste quand le réseau a lâché.
        t.service.position = const Duration(seconds: 30);
        t.service.emitError(Exception('coupure'));
        async.flushMicrotasks();

        // Rechargement différé : pendant le backoff, l'état est « reconnexion ».
        expect(t.controller.status, PlaybackStatus.reconnecting);
        expect(t.service.loadCalls, 1, reason: 'pas de rechargement immédiat');

        elapse(async);
        expect(t.service.loadCalls, 2);
        expect(t.service.lastInitialPosition, const Duration(seconds: 30),
            reason: 'une coupure brève ne doit pas faire recommencer la piste');
        expect(tokens, [false, true],
            reason: 'la première reprise seule force une rotation de token');
      });
    });

    test('les reprises suivantes ne redemandent pas de rotation de token', () {
      fakeAsync((async) {
        final tokens = <bool>[];
        final t = _build(tokens: tokens);
        _play(t.controller);
        async.flushMicrotasks();

        for (var i = 0; i < 2; i++) {
          t.service.emitError(Exception('encore KO'));
          async.flushMicrotasks();
          elapse(async);
        }

        // Une rotation n'ayant pas résolu l'échec, en enchaîner d'autres non plus.
        expect(tokens, [false, true, false]);
      });
    });

    test('les reprises sont bornées : au-delà, état d\'erreur', () {
      fakeAsync((async) {
        final t = _build();
        _play(t.controller);
        async.flushMicrotasks();

        for (var i = 0; i < 4; i++) {
          t.service.emitError(Exception('KO'));
          async.flushMicrotasks();
          elapse(async);
        }

        expect(t.controller.hasError, isTrue);
        // 1 chargement initial + 3 reprises, pas une de plus.
        expect(t.service.loadCalls, 4);
      });
    });

    test(
        'une piste qui rejoue puis re-échoue ne boucle pas indéfiniment '
        '(réseau instable)', () {
      fakeAsync((async) {
        final tokens = <bool>[];
        final t = _build(tokens: tokens);
        _play(t.controller);
        async.flushMicrotasks();

        // Le cycle ready → erreur se répète : sans compteur persistant, chaque
        // `ready` réarmerait la reprise et la piste repartirait sans fin.
        for (var i = 0; i < 5; i++) {
          t.service.emitState(PlayerState(true, ProcessingState.ready));
          async.flushMicrotasks();
          t.service.emitError(Exception('flap'));
          async.flushMicrotasks();
          elapse(async);
        }

        expect(t.controller.hasError, isTrue);
        expect(t.service.loadCalls, 4, reason: 'bornées malgré les ready');
        expect(tokens.where((forced) => forced).length, 1,
            reason: 'une seule rotation de token sur toute la séquence');
      });
    });

    test('avancer dans la file réarme les reprises', () {
      fakeAsync((async) {
        final t = _build();
        _play(t.controller);
        async.flushMicrotasks();

        t.service.emitError(Exception('KO sur la piste 1'));
        async.flushMicrotasks();
        elapse(async);

        // La file avance : la piste suivante repart avec son quota complet.
        t.service.emitIndex(1);
        async.flushMicrotasks();
        for (var i = 0; i < 3; i++) {
          t.service.emitError(Exception('KO sur la piste 2'));
          async.flushMicrotasks();
          elapse(async);
        }

        expect(t.controller.hasError, isFalse,
            reason: '3 reprises restaient disponibles sur la nouvelle piste');
      });
    });
  });

  group('PlaylistQueueController — arrêt', () {
    test('stop vide la file et arrête le lecteur', () async {
      final t = _build();
      await _play(t.controller);

      await t.controller.stop();

      expect(t.service.stopped, isTrue);
      expect(t.controller.hasQueue, isFalse);
      expect(t.controller.status, PlaybackStatus.idle);
      expect(t.controller.tracks, isEmpty);
    });

    test('clear abandonne la file sans toucher au lecteur (le direct reprend)',
        () async {
      final t = _build();
      await _play(t.controller);

      t.controller.clear();

      expect(t.controller.hasQueue, isFalse);
      // Arrêter le lecteur ici couperait le direct qui vient de le charger.
      expect(t.service.stopped, isFalse);
    });

    test('un chargement encore en vol ne ressuscite pas une file arrêtée',
        () async {
      final t = _build();
      final pending = _play(t.controller);
      t.controller.clear();
      await pending;
      await pumpEventQueue();

      expect(t.controller.hasQueue, isFalse);
      expect(t.controller.status, PlaybackStatus.idle);
    });
  });
}
