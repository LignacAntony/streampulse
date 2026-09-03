import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/core/network/sse_client.dart';
import 'package:streampulse/features/broadcast/domain/entities/broadcast_stats.dart';
import 'package:streampulse/features/broadcast/domain/entities/broadcast_stream.dart';
import 'package:streampulse/features/broadcast/domain/repositories/broadcast_repository.dart';
import 'package:streampulse/features/broadcast/domain/services/broadcast_audio_publisher.dart';
import 'package:streampulse/features/broadcast/presentation/controllers/broadcast_session_controller.dart';
import 'package:streampulse/features/broadcast/presentation/providers/broadcast_notifier.dart';
import 'package:streampulse/features/broadcast/presentation/providers/current_broadcast.dart';

BroadcastStream _stream(
  String id, {
  String status = 'idle',
  String? title,
  DateTime? startedAt,
  DateTime? createdAt,
}) => BroadcastStream(
  id: id,
  title: title ?? 'Flux $id',
  status: status,
  isPublic: true,
  createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
  startedAt: startedAt,
  streamKey: 'key-$id',
  streamSourceUrl: 'http://localhost:8080/api/streams/ingest/key-$id',
);

class _FakeBroadcastRepository implements BroadcastRepository {
  _FakeBroadcastRepository({List<BroadcastStream>? streams})
    : streams = streams ?? [_stream('a')];

  List<BroadcastStream> streams;

  /// Si non nul, le prochain `listMyStreams` échoue avec cette erreur.
  Object? listError;
  Object? mutationError;

  int listCalls = 0;
  final List<String> startedIds = [];
  final List<String> stoppedIds = [];

  @override
  Future<List<BroadcastStream>> listMyStreams() async {
    listCalls++;
    if (listError != null) throw listError!;
    return streams;
  }

  @override
  Future<BroadcastStream> createStream({
    required String title,
    required bool isPublic,
    String? description,
    String? category,
  }) async {
    if (mutationError != null) throw mutationError!;
    return BroadcastStream(
      id: 'new',
      title: title,
      status: 'idle',
      isPublic: isPublic,
      // Plus récent que les flux de base : vérifie aussi le tri par date.
      createdAt: DateTime.utc(2026, 6, 1),
      description: description,
      category: category,
    );
  }

  @override
  Future<BroadcastStream> startStream(String id) async {
    startedIds.add(id);
    if (mutationError != null) throw mutationError!;
    return _stream(id, status: 'live', startedAt: DateTime.utc(2026, 1, 1));
  }

  @override
  Future<BroadcastStream> stopStream(String id) async {
    stoppedIds.add(id);
    if (mutationError != null) throw mutationError!;
    return _stream(id, status: 'ended');
  }

  @override
  Future<BroadcastStream> rotateStreamKey(String id) async {
    rotatedIds.add(id);
    if (mutationError != null) throw mutationError!;
    // La rotation ne touche pas au statut : seuls la clé et l'URL changent.
    final current = streams.firstWhere((s) => s.id == id);
    return BroadcastStream(
      id: current.id,
      title: current.title,
      status: current.status,
      isPublic: current.isPublic,
      createdAt: current.createdAt,
      startedAt: current.startedAt,
      streamKey: 'cle-neuve-$id',
      streamSourceUrl: 'http://localhost:8080/api/streams/ingest/cle-neuve-$id',
    );
  }

  @override
  Future<void> deleteStream(String id) async {
    deletedIds.add(id);
    if (mutationError != null) throw mutationError!;
  }

  @override
  Future<BroadcastStats> streamStats(String id) async {
    statsCalls++;
    if (statsError != null) throw statsError!;
    return BroadcastStats(streamId: id, listeners: listeners, peak: listeners);
  }

  final List<String> deletedIds = [];
  final List<String> rotatedIds = [];
  int statsCalls = 0;
  int listeners = 3;
  Object? statsError;
}

/// Repository dont chaque `listMyStreams` reste en vol tant que le test n'a
/// pas résolu son [Completer] : permet de contrôler l'ORDRE d'arrivée de deux
/// chargements concurrents.
class _DeferredRepository implements BroadcastRepository {
  final List<Completer<List<BroadcastStream>>> pending = [];

  @override
  Future<List<BroadcastStream>> listMyStreams() {
    final completer = Completer<List<BroadcastStream>>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<BroadcastStream> createStream({
    required String title,
    required bool isPublic,
    String? description,
    String? category,
  }) => throw UnimplementedError();

  @override
  Future<BroadcastStream> startStream(String id) => throw UnimplementedError();

  @override
  Future<BroadcastStream> stopStream(String id) => throw UnimplementedError();

  @override
  Future<void> deleteStream(String id) => throw UnimplementedError();

  @override
  Future<BroadcastStream> rotateStreamKey(String id) =>
      throw UnimplementedError();

  @override
  Future<BroadcastStats> streamStats(String id) => throw UnimplementedError();
}

/// Repository dont `startStream` reste en vol jusqu'à résolution manuelle :
/// permet de disposer le notifier pendant qu'une mutation est en cours.
class _DeferredMutationRepository implements BroadcastRepository {
  final List<Completer<BroadcastStream>> pending = [];

  @override
  Future<BroadcastStream> startStream(String id) {
    final completer = Completer<BroadcastStream>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<List<BroadcastStream>> listMyStreams() async => const [];

  @override
  Future<BroadcastStream> createStream({
    required String title,
    required bool isPublic,
    String? description,
    String? category,
  }) => throw UnimplementedError();

  @override
  Future<BroadcastStream> stopStream(String id) => throw UnimplementedError();

  @override
  Future<void> deleteStream(String id) => throw UnimplementedError();

  @override
  Future<BroadcastStream> rotateStreamKey(String id) =>
      throw UnimplementedError();

  @override
  Future<BroadcastStats> streamStats(String id) => throw UnimplementedError();
}

/// Connecteur SSE piloté par le test : chaque `connect` ouvre un
/// `StreamController` que le test alimente ou ferme à volonté.
class _FakeSseConnector implements SseConnector {
  final List<String> paths = [];
  final List<StreamController<SseEvent>> controllers = [];

  StreamController<SseEvent> get current => controllers.last;
  int get connectCount => controllers.length;

  @override
  Stream<SseEvent> connect(String path) {
    paths.add(path);
    final controller = StreamController<SseEvent>();
    controllers.add(controller);
    return controller.stream;
  }
}

class _FakeAudioPublisher implements BroadcastAudioPublisher {
  final StreamController<BroadcastAudioState> _states =
      StreamController<BroadcastAudioState>.broadcast();
  Object? prepareError;
  Object? startError;
  int prepares = 0;
  int starts = 0;
  int stops = 0;
  Uri? sourceUrl;

  @override
  bool isSupported = true;

  @override
  BroadcastAudioState state = BroadcastAudioState.idle;

  /// Abandon du diffuseur audio après épuisement de ses reconnexions.
  void giveUp() {
    state = BroadcastAudioState.failed;
    _states.add(state);
  }

  /// Coupure de capture puis rétablissement, comme une perte de réseau.
  void reconnect() {
    state = BroadcastAudioState.reconnecting;
    _states.add(state);
  }

  void backLive() {
    state = BroadcastAudioState.live;
    _states.add(state);
  }

  /// Une autre source (encodeur externe) a pris l'ingest en cours de route.
  void supersede() {
    state = BroadcastAudioState.superseded;
    _states.add(state);
  }

  @override
  Stream<BroadcastAudioState> get states => _states.stream;

  @override
  Future<void> prepare() async {
    prepares++;
    if (prepareError != null) throw prepareError!;
  }

  @override
  Future<void> start(Uri sourceUrl) async {
    starts++;
    this.sourceUrl = sourceUrl;
    if (startError != null) throw startError!;
    state = BroadcastAudioState.live;
    _states.add(state);
  }

  @override
  Future<void> stop() async {
    stops++;
    state = BroadcastAudioState.idle;
    _states.add(state);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
  }
}

/// Laisse tourner les callbacks asynchrones (arrêt serveur déclenché en
/// `unawaited` derrière un flux d'états) jusqu'à ce que [condition] tienne.
Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue);
}

void main() {
  group('BroadcastNotifier — chargement', () {
    test(
      'trie le direct en tête, puis les flux prêts, puis les terminés',
      () async {
        final repository = _FakeBroadcastRepository(
          streams: [
            _stream('ended', status: 'ended'),
            _stream('idle'),
            _stream('live', status: 'live'),
          ],
        );
        final notifier = BroadcastNotifier(repository);

        await notifier.load();

        expect(notifier.streams.map((s) => s.id).toList(), [
          'live',
          'idle',
          'ended',
        ]);
        expect(notifier.liveStream?.id, 'live');
        expect(notifier.hasLiveStream, isTrue);
      },
    );

    test('expose un message dédié sur erreur réseau', () async {
      final repository = _FakeBroadcastRepository()
        ..listError = const NetworkException();
      final notifier = BroadcastNotifier(repository);

      await notifier.load();

      expect(notifier.error, 'Pas de connexion réseau');
      expect(notifier.isNetworkError, isTrue);
      expect(notifier.loading, isFalse);
    });

    test(
      'erreur non réseau : message générique, isNetworkError faux',
      () async {
        final repository = _FakeBroadcastRepository()
          ..listError = const ServerException();
        final notifier = BroadcastNotifier(repository);

        await notifier.load();

        expect(notifier.error, 'Impossible de charger vos flux');
        expect(notifier.isNetworkError, isFalse);
      },
    );

    test('deux chargements concurrents : seul le plus récent écrit l\'état, '
        'sans spinner figé', () async {
      final repository = _DeferredRepository();
      final notifier = BroadcastNotifier(repository);

      final first = notifier.load();
      final second = notifier.load();

      // Le PREMIER répond en dernier : sa réponse est obsolète et ignorée.
      repository.pending[1].complete([_stream('recent')]);
      repository.pending[0].complete([_stream('perimee')]);
      await Future.wait([first, second]);

      expect(notifier.streams.single.id, 'recent');
      expect(notifier.loading, isFalse);
    });
  });

  group('BroadcastNotifier — mutations', () {
    test('create ajoute le flux à la liste et repositionne le tri', () async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('live', status: 'live')],
      );
      final notifier = BroadcastNotifier(repository);
      await notifier.load();

      final created = await notifier.create(title: 'Nouveau', isPublic: true);

      expect(created.title, 'Nouveau');
      expect(notifier.streams.map((s) => s.id).toList(), ['live', 'new']);
      expect(notifier.creating, isFalse);
    });

    test('start remplace le flux par sa version live', () async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      final notifier = BroadcastNotifier(repository);
      await notifier.load();

      await notifier.start('a');

      expect(repository.startedIds, ['a']);
      expect(notifier.streams.single.isLive, isTrue);
      expect(notifier.mutatingId, isNull);
    });

    test('start prépare le micro puis pousse vers stream_source_url', () async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      final audio = _FakeAudioPublisher();
      final notifier = BroadcastNotifier(repository, audioPublisher: audio);
      await notifier.load();

      await notifier.start('a');

      expect(audio.prepares, 1);
      expect(audio.starts, 1);
      expect(audio.sourceUrl, Uri.parse(_stream('a').streamSourceUrl!));
      expect(notifier.audioState, BroadcastAudioState.live);
      expect(notifier.isPublishingAudio('a'), isTrue);
    });

    test('publie le flux diffusé vers CurrentBroadcast, puis le libère à '
        'l\'arrêt', () async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      final audio = _FakeAudioPublisher();
      final current = CurrentBroadcast();
      final notifier = BroadcastNotifier(
        repository,
        audioPublisher: audio,
        currentBroadcast: current,
      );
      await notifier.load();

      await notifier.start('a');
      expect(current.streamId, 'a');
      expect(current.isBroadcasting('a'), isTrue);

      await notifier.stop('a');
      expect(current.streamId, isNull);
    });

    test('une panne micro libère aussi CurrentBroadcast', () async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      final audio = _FakeAudioPublisher();
      final current = CurrentBroadcast();
      final notifier = BroadcastNotifier(
        repository,
        audioPublisher: audio,
        currentBroadcast: current,
      );
      await notifier.load();
      await notifier.start('a');
      expect(current.streamId, 'a');

      audio.giveUp();
      await _pumpUntil(() => current.streamId == null);
    });

    test('un refus micro ne passe jamais le flux serveur à live', () async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      final audio = _FakeAudioPublisher()
        ..prepareError = const MicrophonePermissionException();
      final notifier = BroadcastNotifier(repository, audioPublisher: audio);
      await notifier.load();

      await expectLater(
        notifier.start('a'),
        throwsA(isA<MicrophonePermissionException>()),
      );

      expect(repository.startedIds, isEmpty);
      expect(notifier.streams.single.isIdle, isTrue);
    });

    test(
      'un échec de capture après start annule immédiatement le live',
      () async {
        final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
        final audio = _FakeAudioPublisher()..startError = StateError('occupé');
        final notifier = BroadcastNotifier(repository, audioPublisher: audio);
        await notifier.load();

        await expectLater(notifier.start('a'), throwsStateError);

        expect(repository.startedIds, ['a']);
        expect(repository.stoppedIds, ['a']);
        expect(notifier.streams.single.isEnded, isTrue);
        expect(notifier.isPublishingAudio('a'), isFalse);
      },
    );

    // Une panne définitive du micro coupe le direct sans passer par `stop()` :
    // la liste doit s'aligner sur l'état rendu par l'arrêt serveur, sans
    // rechargement — c'est justement le moment où le réseau est le moins sûr.
    test(
      'un abandon du micro réaligne la liste sans recharger',
      () async {
        final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
        final audio = _FakeAudioPublisher();
        final notifier = BroadcastNotifier(repository, audioPublisher: audio);
        await notifier.load();
        await notifier.start('a');
        final listCallsBefore = repository.listCalls;

        audio.giveUp();
        await _pumpUntil(() => notifier.streams.single.isEnded);

        expect(repository.stoppedIds, ['a']);
        expect(notifier.hasLiveStream, isFalse);
        expect(notifier.isPublishingAudio('a'), isFalse);
        expect(repository.listCalls, listCallsBefore);
      },
    );

    test('stop remplace le flux par sa version terminée', () async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live')],
      );
      final notifier = BroadcastNotifier(repository);
      await notifier.load();

      await notifier.stop('a');

      expect(repository.stoppedIds, ['a']);
      expect(notifier.streams.single.isEnded, isTrue);
      expect(notifier.hasLiveStream, isFalse);
    });

    test('stop termine le serveur avant de libérer le micro local', () async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      final audio = _FakeAudioPublisher();
      final notifier = BroadcastNotifier(repository, audioPublisher: audio);
      await notifier.load();
      await notifier.start('a');

      await notifier.stop('a');

      expect(repository.stoppedIds, ['a']);
      expect(audio.stops, 1);
      expect(notifier.audioState, BroadcastAudioState.idle);
    });

    // ADR 049 — quitter l'application ne coupe plus rien : le service de
    // premier plan Android maintient la capture pendant que le diffuseur fait
    // autre chose sur son téléphone. Seule la fermeture arrête le direct.
    test(
      'fermer l\'application termine le direct et libère le micro',
      () async {
        final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
        final audio = _FakeAudioPublisher();
        final notifier = BroadcastNotifier(repository, audioPublisher: audio);
        await notifier.load();
        await notifier.start('a');

        await notifier.stopForAppClosed();

        expect(repository.stoppedIds, ['a']);
        expect(audio.stops, 1);
        expect(notifier.isPublishingAudio('a'), isFalse);
      },
    );

    test(
      'fermer sans diffusion en cours ne déclenche aucun arrêt serveur',
      () async {
        final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
        final audio = _FakeAudioPublisher();
        final notifier = BroadcastNotifier(repository, audioPublisher: audio);
        await notifier.load();

        await notifier.stopForAppClosed();

        expect(repository.stoppedIds, isEmpty);
        expect(audio.stops, 0);
      },
    );

    // Revue PR #382 — un 409 d'ingest survenu APRÈS le démarrage signifie qu'une
    // autre source a pris la clé. Le publisher sortait alors sur `idle`, que le
    // contrôleur ignorait : micro mort, tuile toujours « en direct », aucun
    // message. Désynchronisation silencieuse, le pire mode de défaillance.
    test(
      'la prise de relais par une autre source relâche le micro sans arrêter le direct',
      () async {
        final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
        final audio = _FakeAudioPublisher();
        final notifier = BroadcastNotifier(repository, audioPublisher: audio);
        final raisons = <BroadcastAudioEndReason>[];
        notifier.audioFailures.listen((f) => raisons.add(f.reason));
        await notifier.load();
        await notifier.start('a');

        audio.supersede();
        await _pumpUntil(() => raisons.isNotEmpty);

        // Le direct vit toujours : le terminer couperait la diffusion de
        // l'autre source.
        expect(repository.stoppedIds, isEmpty);
        expect(notifier.hasLiveStream, isTrue);
        // Mais l'état local est relâché, et la raison remonte à l'écran.
        expect(notifier.isPublishingAudio('a'), isFalse);
        expect(raisons, [BroadcastAudioEndReason.supersededByOtherSource]);
      },
    );

    // ADR 050 — le diffuseur voit « Reconnexion audio… » pendant la coupure,
    // mais rien ne lui disait au retour combien de temps n'était pas parti.
    // C'est pourtant la seule information qui change son comportement : il
    // peut redire ce qui a été perdu.
    test('une coupure rétablie annonce sa durée', () async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      final audio = _FakeAudioPublisher();
      var horloge = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final notifier = BroadcastNotifier(
        repository,
        audioPublisher: audio,
        now: () => horloge,
      );
      final durees = <Duration>[];
      notifier.audioRecoveries.listen(durees.add);
      await notifier.load();
      await notifier.start('a');

      // Le démarrage lui-même (connecting -> live) ne doit rien annoncer.
      expect(durees, isEmpty);

      audio.reconnect();
      await _pumpUntil(() => true);
      horloge = horloge.add(const Duration(seconds: 20));
      audio.backLive();
      await _pumpUntil(() => durees.isNotEmpty);

      expect(durees, [const Duration(seconds: 20)]);
    });

    test('les erreurs de mutation remontent à l\'appelant', () async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')])
        ..mutationError = const ConflictException('déjà en direct');
      final notifier = BroadcastNotifier(repository);
      await notifier.load();

      await expectLater(notifier.start('a'), throwsA(isA<ConflictException>()));
      // Le verrou est bien relâché malgré l'échec : une mutation ultérieure
      // doit rester possible.
      expect(notifier.mutatingId, isNull);
    });

    test('une seule mutation à la fois, et le no-op est signalé', () async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a'), _stream('b')],
      );
      final notifier = BroadcastNotifier(repository);
      await notifier.load();

      // Les deux appels partent sans await intermédiaire : le second doit être
      // un no-op tant que le premier est en vol.
      final first = notifier.start('a');
      final second = notifier.start('b');
      final results = await Future.wait([first, second]);

      expect(repository.startedIds, ['a']);
      // Le retour distingue « fait » de « ignoré » : sans ça, l'écran annonçait
      // « Vous êtes en direct » sur le second tap alors que rien n'avait démarré.
      expect(results, [true, false]);
    });

    test('isMutating expose qu\'une mutation est en vol', () async {
      final repository = _DeferredRepository();
      final notifier = BroadcastNotifier(repository);

      expect(notifier.isMutating, isFalse);
    });

    test('rotateKey remplace le flux par sa version à clé neuve', () async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      final notifier = BroadcastNotifier(repository);
      await notifier.load();

      final rotated = await notifier.rotateKey('a');

      expect(rotated, isTrue);
      expect(repository.rotatedIds, ['a']);
      expect(notifier.streams.single.streamKey, 'cle-neuve-a');
      expect(notifier.streams.single.streamSourceUrl, contains('cle-neuve-a'));
      // Le statut ne bouge pas : c'est ce qui distingue la rotation des autres
      // mutations, et pourquoi elle ne resynchronise ni SSE ni audience.
      expect(notifier.streams.single.isIdle, isTrue);
      expect(notifier.mutatingId, isNull);
    });

    test('rotateKey est un no-op si une autre mutation est en vol', () async {
      final repository = _DeferredMutationRepository();
      final notifier = BroadcastNotifier(repository);
      unawaited(notifier.start('a'));

      expect(await notifier.rotateKey('a'), isFalse);

      repository.pending.first.complete(_stream('a', status: 'live'));
      notifier.dispose();
    });

    test('rotateKey relaie le 409 d\'un flux passé en direct', () async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')])
        ..mutationError = const ConflictException('stream is live');
      final notifier = BroadcastNotifier(repository);
      await notifier.load();

      await expectLater(
        notifier.rotateKey('a'),
        throwsA(isA<ConflictException>()),
      );
      expect(notifier.mutatingId, isNull);
    });

    test('delete retire le flux de la liste', () async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a'), _stream('b')],
      );
      final notifier = BroadcastNotifier(repository);
      await notifier.load();

      final deleted = await notifier.delete('a');

      expect(deleted, isTrue);
      expect(repository.deletedIds, ['a']);
      expect(notifier.streams.map((s) => s.id).toList(), ['b']);
    });

    test('delete relaie les erreurs et libère le verrou', () async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')])
        ..mutationError = const ServerException('boom');
      final notifier = BroadcastNotifier(repository);
      await notifier.load();

      await expectLater(notifier.delete('a'), throwsA(isA<ServerException>()));
      expect(notifier.mutatingId, isNull);
      expect(notifier.streams, hasLength(1));
    });
  });

  group('BroadcastNotifier — audience (STR-154)', () {
    test('un direct déclenche une première mesure immédiate', () async {
      // Attendre 5 s laisserait la carte sans chiffre juste après le
      // démarrage, au moment où le diffuseur la regarde le plus.
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live')],
      );
      final notifier = BroadcastNotifier(
        repository,
        statsInterval: const Duration(milliseconds: 20),
      );
      notifier.setActive(true);

      await notifier.load();
      await Future<void>.delayed(Duration.zero);

      expect(repository.statsCalls, greaterThanOrEqualTo(1));
      expect(notifier.stats?.listeners, 3);
      notifier.dispose();
    });

    test('les mesures se répètent à la cadence demandée', () async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live')],
      );
      final notifier = BroadcastNotifier(
        repository,
        statsInterval: const Duration(milliseconds: 20),
      );
      notifier.setActive(true);
      await notifier.load();
      final callsAfterLoad = repository.statsCalls;

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(repository.statsCalls, greaterThan(callsAfterLoad));
      notifier.dispose();
    });

    test('aucune mesure sans flux en direct', () async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      final notifier = BroadcastNotifier(
        repository,
        statsInterval: const Duration(milliseconds: 20),
      );
      notifier.setActive(true);

      await notifier.load();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(repository.statsCalls, 0);
      expect(notifier.stats, isNull);
      notifier.dispose();
    });

    test(
      'l\'arrêt du direct coupe les mesures et efface l\'audience',
      () async {
        final repository = _FakeBroadcastRepository(
          streams: [_stream('a', status: 'live')],
        );
        final notifier = BroadcastNotifier(
          repository,
          statsInterval: const Duration(milliseconds: 20),
        );
        notifier.setActive(true);
        await notifier.load();
        await Future<void>.delayed(Duration.zero);
        expect(notifier.stats, isNotNull);

        await notifier.stop('a');
        final callsAfterStop = repository.statsCalls;
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(notifier.stats, isNull);
        expect(repository.statsCalls, callsAfterStop);
        notifier.dispose();
      },
    );

    test('les mesures s\'arrêtent en arrière-plan', () async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live')],
      );
      final notifier = BroadcastNotifier(
        repository,
        statsInterval: const Duration(milliseconds: 20),
      );
      notifier.setActive(true);
      await notifier.load();

      notifier.setActive(false);
      final callsAfterPause = repository.statsCalls;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(repository.statsCalls, callsAfterPause);
      notifier.dispose();
    });

    test('une mesure identique ne notifie pas', () async {
      // L'audience bouge rarement entre deux relevés : reconstruire l'écran
      // toutes les 5 s pour réafficher les mêmes chiffres est du gaspillage.
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live')],
      );
      final notifier = BroadcastNotifier(
        repository,
        statsInterval: const Duration(milliseconds: 20),
      );
      notifier.setActive(true);
      await notifier.load();
      await Future<void>.delayed(Duration.zero);

      var notifications = 0;
      notifier.addListener(() => notifications++);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        repository.statsCalls,
        greaterThan(1),
        reason: 'les mesures tournent',
      );
      expect(notifications, 0, reason: 'valeurs inchangées : aucun rebuild');
      notifier.dispose();
    });

    test('une mesure différente notifie', () async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live')],
      );
      final notifier = BroadcastNotifier(
        repository,
        statsInterval: const Duration(milliseconds: 20),
      );
      notifier.setActive(true);
      await notifier.load();
      await Future<void>.delayed(Duration.zero);

      var notifications = 0;
      notifier.addListener(() => notifications++);
      repository.listeners = 12;
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(notifications, greaterThan(0));
      expect(notifier.stats?.listeners, 12);
      notifier.dispose();
    });

    test('un échec de mesure ne casse pas l\'écran', () async {
      // L'audience est une information d'appoint : une coupure réseau ne doit
      // pas faire clignoter une erreur sur un dashboard par ailleurs sain.
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live')],
      )..statsError = const NetworkException();
      final notifier = BroadcastNotifier(
        repository,
        statsInterval: const Duration(milliseconds: 20),
      );
      notifier.setActive(true);

      await notifier.load();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(notifier.stats, isNull);
      expect(
        notifier.error,
        isNull,
        reason: 'pas d\'erreur remontée à l\'écran',
      );
      expect(notifier.streams, hasLength(1));
      notifier.dispose();
    });
  });

  group('BroadcastNotifier — robustesse', () {
    test('un tri de même rang suit createdAt décroissant', () async {
      // `List.sort` de Dart n'est pas stable : sans départage explicite, deux
      // flux de même statut pourraient permuter d'un refresh à l'autre.
      final repository = _FakeBroadcastRepository(
        streams: [
          _stream('vieux', createdAt: DateTime.utc(2026, 1, 1)),
          _stream('recent', createdAt: DateTime.utc(2026, 3, 1)),
          _stream('milieu', createdAt: DateTime.utc(2026, 2, 1)),
        ],
      );
      final notifier = BroadcastNotifier(repository);

      await notifier.load();
      final first = notifier.streams.map((s) => s.id).toList();
      await notifier.refresh();
      final second = notifier.streams.map((s) => s.id).toList();

      expect(first, ['recent', 'milieu', 'vieux']);
      expect(second, first, reason: 'l\'ordre doit être reproductible');
    });

    test('une mutation qui répond après dispose ne notifie pas', () async {
      final repository = _DeferredMutationRepository();
      final notifier = BroadcastNotifier(repository);

      final pending = notifier.start('a');
      notifier.dispose();
      repository.pending.single.complete(_stream('a', status: 'live'));

      // Sans garde `_disposed`, le `finally` lèverait « A ChangeNotifier was
      // used after being disposed » en debug.
      await expectLater(pending, completes);
    });
  });

  group('BroadcastNotifier — souscription SSE', () {
    test(
      'ne se branche que sur un flux en direct, et sur le bon chemin',
      () async {
        final sse = _FakeSseConnector();
        final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
        final notifier = BroadcastNotifier(repository, sse: sse);
        notifier.setActive(true);

        await notifier.load();
        expect(sse.connectCount, 0, reason: 'aucun flux en direct');

        repository.streams = [_stream('a', status: 'live')];
        await notifier.load();

        expect(sse.connectCount, 1);
        expect(sse.paths.single, '/api/streams/a/events');
      },
    );

    test('l\'évènement ended coupe la souscription et resynchronise', () async {
      final sse = _FakeSseConnector();
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live')],
      );
      final notifier = BroadcastNotifier(repository, sse: sse);
      notifier.setActive(true);
      await notifier.load();
      final callsBefore = repository.listCalls;

      repository.streams = [_stream('a', status: 'ended')];
      sse.current.add(const SseEvent(name: 'ended', data: '{"type":"ended"}'));
      await Future<void>.delayed(Duration.zero);

      expect(repository.listCalls, greaterThan(callsBefore));
      expect(notifier.hasLiveStream, isFalse);
    });

    test(
      'une coupure déclenche une reconnexion suivie d\'une resynchronisation',
      () async {
        final sse = _FakeSseConnector();
        final repository = _FakeBroadcastRepository(
          streams: [_stream('a', status: 'live')],
        );
        final notifier = BroadcastNotifier(
          repository,
          sse: sse,
          // Backoff neutralisé : le test vérifie la mécanique, pas les délais.
          backoff: (_) => Duration.zero,
        );
        notifier.setActive(true);
        await notifier.load();
        final callsBefore = repository.listCalls;

        // Le serveur ferme la connexion sans avoir envoyé `ended`.
        await sse.current.close();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(sse.connectCount, 2, reason: 'reconnexion attendue');
        expect(
          repository.listCalls,
          greaterThan(callsBefore),
          reason:
              'le SSE ne rejoue pas les évènements manqués : il faut '
              'resynchroniser après chaque reconnexion',
        );
      },
    );

    test(
      'setActive(false) coupe la souscription et empêche la reconnexion',
      () async {
        final sse = _FakeSseConnector();
        final repository = _FakeBroadcastRepository(
          streams: [_stream('a', status: 'live')],
        );
        final notifier = BroadcastNotifier(
          repository,
          sse: sse,
          backoff: (_) => Duration.zero,
        );
        notifier.setActive(true);
        await notifier.load();
        expect(sse.connectCount, 1);

        notifier.setActive(false);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          sse.connectCount,
          1,
          reason: 'aucune reconnexion en arrière-plan',
        );
      },
    );

    test('sans connecteur SSE, le notifier reste fonctionnel', () async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live')],
      );
      final notifier = BroadcastNotifier(repository);
      notifier.setActive(true);

      await notifier.load();

      expect(notifier.hasLiveStream, isTrue);
      notifier.dispose();
    });
  });

  group(
    'BroadcastNotifier — repli par polling (plateformes sans streaming)',
    () {
      test(
        'un direct sans connecteur SSE déclenche un rafraîchissement périodique',
        () async {
          // Cas de Flutter web : l'adaptateur navigateur de Dio ne sait pas
          // streamer, on ne branche donc aucun SSE et on interroge l'API.
          final repository = _FakeBroadcastRepository(
            streams: [_stream('a', status: 'live')],
          );
          final notifier = BroadcastNotifier(
            repository,
            pollInterval: const Duration(milliseconds: 20),
          );
          notifier.setActive(true);
          await notifier.load();
          final callsAfterLoad = repository.listCalls;

          await Future<void>.delayed(const Duration(milliseconds: 80));

          expect(repository.listCalls, greaterThan(callsAfterLoad));
          notifier.dispose();
        },
      );

      test('aucun polling tant qu\'aucun flux n\'est en direct', () async {
        final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
        final notifier = BroadcastNotifier(
          repository,
          pollInterval: const Duration(milliseconds: 20),
        );
        notifier.setActive(true);
        await notifier.load();
        final callsAfterLoad = repository.listCalls;

        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(repository.listCalls, callsAfterLoad);
        notifier.dispose();
      });

      test('le polling s\'arrête en arrière-plan', () async {
        final repository = _FakeBroadcastRepository(
          streams: [_stream('a', status: 'live')],
        );
        final notifier = BroadcastNotifier(
          repository,
          pollInterval: const Duration(milliseconds: 20),
        );
        notifier.setActive(true);
        await notifier.load();

        notifier.setActive(false);
        final callsAfterPause = repository.listCalls;
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(repository.listCalls, callsAfterPause);
        notifier.dispose();
      });
    },
  );

  group('BroadcastStream', () {
    test('liveDurationAt ne vaut que pour un flux en direct', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final live = _stream(
        'a',
        status: 'live',
        startedAt: now.subtract(const Duration(minutes: 3)),
      );
      final idle = _stream('b', startedAt: now);

      expect(live.liveDurationAt(now), const Duration(minutes: 3));
      expect(idle.liveDurationAt(now), isNull);
    });

    test('une horloge client en avance ne produit pas de durée négative', () {
      final now = DateTime.utc(2026, 1, 1, 12);
      final live = _stream(
        'a',
        status: 'live',
        startedAt: now.add(const Duration(seconds: 5)),
      );

      expect(live.liveDurationAt(now), Duration.zero);
    });
  });
}
