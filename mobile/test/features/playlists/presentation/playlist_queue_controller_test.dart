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

/// Laisse filer le backoff (1/2/4 s) sans attendre en temps réel. Partagé par
/// les tests de reprise et ceux de l'ordre de lecture, qui reposent dessus.
void elapse(FakeAsync async, {int seconds = 10}) {
  async.elapse(Duration(seconds: seconds));
  async.flushMicrotasks();
}

Future<void> _play(
  PlaylistQueueController controller, {
  int startIndex = 0,
  List<PlaylistTrack>? tracks,
  bool? shuffle,
}) {
  return controller.play(
    playlistId: 'p-1',
    playlistName: 'My Favorites',
    tracks: tracks ?? _tracks,
    startIndex: startIndex,
    shuffle: shuffle,
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

    test('un déplacement pendant une reprise est ignoré (revue #292)', () {
      fakeAsync((async) {
        final t = _build();
        _play(t.controller);
        async.flushMicrotasks();

        t.service.position = const Duration(seconds: 30);
        t.service.emitError(Exception('coupure'));
        async.flushMicrotasks();
        expect(t.controller.status, PlaybackStatus.reconnecting);
        expect(t.controller.canSeek, isFalse);

        t.controller.seek(const Duration(seconds: 90));
        async.flushMicrotasks();

        // La reprise en vol rechargerait à la position relevée AVANT (30 s) :
        // accepter le déplacement le ferait annuler quelques secondes plus tard,
        // et l'auditeur verrait la lecture revenir en arrière toute seule.
        expect(t.service.seeks, isEmpty);
        elapse(async);
        expect(t.service.lastInitialPosition, const Duration(seconds: 30));
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

  group('PlaylistQueueController — lecture aléatoire (US-05-05)', () {
    test('sans shuffle, l\'ordre de lecture est celui de la playlist',
        () async {
      final t = _build();

      await _play(t.controller);

      expect(t.controller.shuffleEnabled, isFalse);
      expect(t.controller.playbackOrder, [0, 1, 2]);
      expect(t.service.shuffleEnabled, isFalse);
    });

    test('lancer en aléatoire mélange la file dès le chargement', () async {
      final t = _build();
      t.service.shuffledOrder = [2, 0, 1];

      await _play(t.controller, startIndex: 2, shuffle: true);

      expect(t.service.shuffleEnabled, isTrue);
      expect(t.controller.playbackOrder, [2, 0, 1]);
      // La piste de départ est bien la première **jouée** (« 1/3 »).
      expect(t.controller.positionInOrder, 0);
    });

    test('la bascule en cours de lecture relève le nouvel ordre', () async {
      final t = _build();
      await _play(t.controller);
      t.service.shuffledOrder = [1, 2, 0];

      await t.controller.toggleShuffle();

      expect(t.controller.shuffleEnabled, isTrue);
      expect(t.service.shuffleEnabled, isTrue);
      expect(t.controller.playbackOrder, [1, 2, 0]);
    });

    test('« suivant » suit l\'ordre mélangé, pas l\'index de la playlist',
        () async {
      final t = _build();
      t.service.shuffledOrder = [1, 2, 0];
      await _play(t.controller, startIndex: 1, shuffle: true);

      await t.controller.next();

      // Depuis la piste 1 (1re jouée), la suivante est la 2 — pas la 2 par
      // hasard : c'est l'ordre mélangé qui le dit, l'index+1 aurait donné 2
      // aussi, d'où le second saut ci-dessous qui les départage.
      expect(t.service.skips, [2]);
      await t.controller.next();
      expect(t.service.skips, [2, 0]);
      expect(t.controller.currentIndex, 0);
    });

    test('la dernière piste jouée n\'a pas de suivante', () async {
      final t = _build();
      t.service.shuffledOrder = [1, 2, 0];
      await _play(t.controller, startIndex: 0, shuffle: true);

      // La piste 0 est la dernière de l'ordre mélangé, bien que première de la
      // playlist.
      expect(t.controller.hasNext, isFalse);
      expect(t.controller.hasPrevious, isTrue);
    });

    test('une reprise après erreur rejoue le même ordre (retour de revue)', () {
      fakeAsync((async) {
        final t = _build();
        t.service.shuffledOrder = [2, 0, 1];
        _play(t.controller, shuffle: true);
        async.flushMicrotasks();
        expect(t.controller.playbackOrder, [2, 0, 1]);
        expect(t.service.lastOrder, isNull,
            reason: 'un lancement demandé tire un ordre neuf');

        // Coupure réseau / access token expiré (toutes les 15 min en pratique).
        t.service.emitError(Exception('coupure'));
        async.flushMicrotasks();
        elapse(async);

        expect(t.service.loadCalls, 2);
        expect(t.service.lastOrder?.indices, [2, 0, 1],
            reason: 'le rechargement subi impose l\'ordre en cours');
        expect(t.controller.playbackOrder, [2, 0, 1],
            reason: 'la suite annoncée ne doit pas bouger sous l\'auditeur');
      });
    });

    test('relancer volontairement la playlist retire un ordre', () async {
      final t = _build();
      t.service.shuffledOrder = [1, 2, 0];
      await _play(t.controller, shuffle: true);

      await _play(t.controller);

      expect(t.service.lastOrder, isNull);
      expect(t.controller.playbackOrder, [1, 2, 0],
          reason: 'nouvel ordre relevé auprès du lecteur, pas celui d\'avant');
    });

    test('une file non mélangée n\'impose aucun ordre au rechargement', () {
      fakeAsync((async) {
        final t = _build();
        _play(t.controller);
        async.flushMicrotasks();

        t.service.emitError(Exception('coupure'));
        async.flushMicrotasks();
        elapse(async);

        expect(t.service.loadCalls, 2);
        expect(t.service.lastOrder, isNull,
            reason: 'rien à figer sur une lecture dans l\'ordre');
      });
    });

    test('le mode survit à l\'arrêt : c\'est une préférence d\'écoute',
        () async {
      final t = _build();
      await _play(t.controller);
      await t.controller.toggleShuffle();

      await t.controller.stop();

      expect(t.controller.shuffleEnabled, isTrue);
    });
  });

  group('PlaylistQueueController — répétition (US-05-05)', () {
    test('le bouton fait défiler aucune → file → piste → aucune', () async {
      final t = _build();
      await _play(t.controller);

      await t.controller.cycleRepeat();
      expect(t.controller.repeatMode, QueueRepeatMode.all);
      expect(t.service.repeatMode, QueueRepeatMode.all);

      await t.controller.cycleRepeat();
      expect(t.controller.repeatMode, QueueRepeatMode.one);

      await t.controller.cycleRepeat();
      expect(t.controller.repeatMode, QueueRepeatMode.off);
    });

    test('répéter la file : la dernière piste a une suivante, qui reboucle',
        () async {
      final t = _build();
      await _play(t.controller, startIndex: 2);
      expect(t.controller.hasNext, isFalse);

      await t.controller.cycleRepeat(); // → all

      expect(t.controller.hasNext, isTrue);
      await t.controller.next();
      expect(t.service.skips, [0]);
    });

    test('répéter la piste ne bloque pas le saut manuel', () async {
      final t = _build();
      await _play(t.controller);
      await t.controller.cycleRepeat(); // all
      await t.controller.cycleRepeat(); // one

      await t.controller.next();

      // just_audio ferait redémarrer la piste courante ; un bouton « suivant »
      // qui ne change pas de piste passerait pour une panne.
      expect(t.service.skips, [1]);
    });

    test('les modes sont réappliqués au lecteur à chaque chargement', () async {
      final t = _build();
      await _play(t.controller);
      await t.controller.cycleRepeat(); // → all
      await t.controller.toggleShuffle(); // → aléatoire

      // Le direct a pu prendre le lecteur entre-temps et remettre ses modes à
      // zéro : relancer une file doit les rétablir.
      t.service.repeatMode = QueueRepeatMode.off;
      t.service.shuffleEnabled = false;
      await _play(t.controller);

      expect(t.service.repeatMode, QueueRepeatMode.all);
      expect(t.service.shuffleEnabled, isTrue);
    });
  });
}
