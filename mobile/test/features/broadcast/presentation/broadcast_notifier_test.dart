import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/core/network/sse_client.dart';
import 'package:streampulse/features/broadcast/domain/entities/broadcast_stream.dart';
import 'package:streampulse/features/broadcast/domain/repositories/broadcast_repository.dart';
import 'package:streampulse/features/broadcast/presentation/providers/broadcast_notifier.dart';

BroadcastStream _stream(
  String id, {
  String status = 'idle',
  String? title,
  DateTime? startedAt,
}) =>
    BroadcastStream(
      id: id,
      title: title ?? 'Flux $id',
      status: status,
      isPublic: true,
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
  }) =>
      throw UnimplementedError();

  @override
  Future<BroadcastStream> startStream(String id) => throw UnimplementedError();

  @override
  Future<BroadcastStream> stopStream(String id) => throw UnimplementedError();
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

void main() {
  group('BroadcastNotifier — chargement', () {
    test('trie le direct en tête, puis les flux prêts, puis les terminés',
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

      expect(
        notifier.streams.map((s) => s.id).toList(),
        ['live', 'idle', 'ended'],
      );
      expect(notifier.liveStream?.id, 'live');
      expect(notifier.hasLiveStream, isTrue);
    });

    test('expose un message dédié sur erreur réseau', () async {
      final repository = _FakeBroadcastRepository()
        ..listError = const NetworkException();
      final notifier = BroadcastNotifier(repository);

      await notifier.load();

      expect(notifier.error, 'Pas de connexion réseau');
      expect(notifier.isNetworkError, isTrue);
      expect(notifier.loading, isFalse);
    });

    test('erreur non réseau : message générique, isNetworkError faux',
        () async {
      final repository = _FakeBroadcastRepository()
        ..listError = const ServerException();
      final notifier = BroadcastNotifier(repository);

      await notifier.load();

      expect(notifier.error, 'Impossible de charger vos flux');
      expect(notifier.isNetworkError, isFalse);
    });

    test(
        'deux chargements concurrents : seul le plus récent écrit l\'état, '
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

    test('une seule mutation à la fois', () async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a'), _stream('b')],
      );
      final notifier = BroadcastNotifier(repository);
      await notifier.load();

      // Les deux appels partent sans await intermédiaire : le second doit être
      // un no-op tant que le premier est en vol.
      final first = notifier.start('a');
      final second = notifier.start('b');
      await Future.wait([first, second]);

      expect(repository.startedIds, ['a']);
    });
  });

  group('BroadcastNotifier — souscription SSE', () {
    test('ne se branche que sur un flux en direct, et sur le bon chemin',
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
    });

    test('l\'évènement ended coupe la souscription et resynchronise',
        () async {
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

    test('une coupure déclenche une reconnexion suivie d\'une resynchronisation',
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
        reason: 'le SSE ne rejoue pas les évènements manqués : il faut '
            'resynchroniser après chaque reconnexion',
      );
    });

    test('setActive(false) coupe la souscription et empêche la reconnexion',
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

      expect(sse.connectCount, 1, reason: 'aucune reconnexion en arrière-plan');
    });

    test('sans connecteur SSE, le notifier reste fonctionnel', () async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live')],
      );
      final notifier = BroadcastNotifier(repository);
      notifier.setActive(true);

      await notifier.load();

      expect(notifier.hasLiveStream, isTrue);
    });
  });

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
