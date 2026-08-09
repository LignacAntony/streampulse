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

  group('PlaylistQueueController — erreurs', () {
    test('un échec relance une fois après rotation du token', () async {
      final tokens = <bool>[];
      final t = _build(tokens: tokens);
      await _play(t.controller);
      expect(tokens, [false]);

      // Cas typique : l'access token (15 min) a expiré au milieu de la file.
      t.service.emitError(Exception('401'));
      await pumpEventQueue();

      expect(t.service.loadCalls, 2);
      expect(tokens, [false, true], reason: 'la reprise force un refresh');
      expect(t.controller.hasError, isFalse);
    });

    test('un second échec devient un état d\'erreur', () async {
      final t = _build();
      await _play(t.controller);

      t.service.emitError(Exception('401'));
      await pumpEventQueue();
      t.service.emitError(Exception('toujours KO'));
      await pumpEventQueue();

      expect(t.controller.hasError, isTrue);
      // Pas de troisième tentative : réessayer en boucle masquerait l'erreur.
      expect(t.service.loadCalls, 2);
    });

    test('une piste qui s\'ouvre réarme la reprise pour la suite de la file',
        () async {
      final t = _build();
      await _play(t.controller);

      t.service.emitError(Exception('401'));
      await pumpEventQueue();
      t.service.emitState(PlayerState(true, ProcessingState.ready));
      await pumpEventQueue();
      t.service.emitError(Exception('401 plus loin'));
      await pumpEventQueue();

      expect(t.service.loadCalls, 3);
      expect(t.controller.hasError, isFalse);
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
