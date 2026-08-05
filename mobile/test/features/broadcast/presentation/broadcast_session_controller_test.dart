import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/broadcast/domain/entities/broadcast_stats.dart';
import 'package:streampulse/features/broadcast/domain/entities/broadcast_stream.dart';
import 'package:streampulse/features/broadcast/domain/repositories/broadcast_repository.dart';
import 'package:streampulse/features/broadcast/domain/services/broadcast_audio_publisher.dart';
import 'package:streampulse/features/broadcast/presentation/controllers/broadcast_session_controller.dart';

BroadcastStream _stream(String id, {String status = 'idle'}) => BroadcastStream(
  id: id,
  title: 'Flux $id',
  status: status,
  isPublic: true,
  createdAt: DateTime.utc(2026, 1, 1),
  streamKey: 'key-$id',
  streamSourceUrl: 'http://localhost:8080/api/streams/ingest/key-$id',
);

class _FakeRepository implements BroadcastRepository {
  Object? startError;
  Object? stopError;
  BroadcastStream? sourceUrlOverride;

  final List<String> startedIds = [];
  final List<String> stoppedIds = [];

  @override
  Future<BroadcastStream> startStream(String id) async {
    startedIds.add(id);
    if (startError != null) throw startError!;
    return sourceUrlOverride ?? _stream(id, status: 'live');
  }

  @override
  Future<BroadcastStream> stopStream(String id) async {
    stoppedIds.add(id);
    if (stopError != null) throw stopError!;
    return _stream(id, status: 'ended');
  }

  @override
  Future<List<BroadcastStream>> listMyStreams() async => const [];

  @override
  Future<BroadcastStream> createStream({
    required String title,
    required bool isPublic,
    String? description,
    String? category,
  }) async => _stream('new');

  @override
  Future<void> deleteStream(String id) async {}

  @override
  Future<BroadcastStats> streamStats(String id) async =>
      BroadcastStats(streamId: id, listeners: 0, peak: 0);
}

class _FakePublisher implements BroadcastAudioPublisher {
  final StreamController<BroadcastAudioState> _states =
      StreamController<BroadcastAudioState>.broadcast();

  Object? startError;
  int stops = 0;

  @override
  bool isSupported = true;

  @override
  BroadcastAudioState state = BroadcastAudioState.idle;

  @override
  Stream<BroadcastAudioState> get states => _states.stream;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> start(Uri sourceUrl) async {
    if (startError != null) throw startError!;
    _emit(BroadcastAudioState.live);
  }

  @override
  Future<void> stop() async {
    stops++;
    _emit(BroadcastAudioState.idle);
  }

  /// Simule l'abandon du diffuseur audio après épuisement de ses tentatives.
  void giveUp() => _emit(BroadcastAudioState.failed);

  void _emit(BroadcastAudioState next) {
    state = next;
    _states.add(next);
  }

  @override
  Future<void> dispose() async {
    if (!_states.isClosed) await _states.close();
  }
}

/// Laisse tourner les callbacks asynchrones (abonnement au flux d'états,
/// arrêt serveur déclenché en `unawaited`) jusqu'à ce que [condition] tienne.
Future<void> _pumpUntil(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(condition(), isTrue);
}

void main() {
  group('BroadcastSessionController — démarrage', () {
    test('un échec de capture annule le direct côté serveur', () async {
      final repository = _FakeRepository();
      final publisher = _FakePublisher()
        ..startError = const MicrophonePermissionException();
      final controller = BroadcastSessionController(repository, publisher);

      await expectLater(
        controller.start('a'),
        throwsA(
          isA<BroadcastSessionStartException>()
              .having((e) => e.cause, 'cause', isA<MicrophonePermissionException>())
              .having((e) => e.refreshRequired, 'refreshRequired', isFalse)
              .having((e) => e.serverState.status, 'serverState.status', 'ended'),
        ),
      );
      expect(repository.startedIds, ['a']);
      expect(repository.stoppedIds, ['a']);
      expect(controller.publishingStreamId, isNull);

      await controller.dispose();
    });

    // Double échec réseau : le rollback lui-même ne passe pas. L'état serveur
    // rendu à l'écran est alors périmé (le flux est peut-être resté `live`),
    // d'où `refreshRequired` — la présentation doit resynchroniser.
    test(
      'un rollback en échec exige une resynchronisation et rend l\'état d\'origine',
      () async {
        final repository = _FakeRepository()
          ..stopError = const NetworkException();
        final publisher = _FakePublisher()
          ..startError = const ServerException('ingest injoignable');
        final controller = BroadcastSessionController(repository, publisher);

        await expectLater(
          controller.start('a'),
          throwsA(
            isA<BroadcastSessionStartException>()
                .having((e) => e.cause, 'cause', isA<ServerException>())
                .having((e) => e.refreshRequired, 'refreshRequired', isTrue)
                // L'état rendu est celui du `start`, seul connu : le rollback
                // n'a rien renvoyé.
                .having((e) => e.serverState.status, 'serverState.status', 'live'),
          ),
        );
        expect(repository.stoppedIds, ['a']);
        expect(controller.publishingStreamId, isNull);

        await controller.dispose();
      },
    );

    test('une URL d\'ingest absente empêche la diffusion', () async {
      final repository = _FakeRepository()
        ..sourceUrlOverride = BroadcastStream(
          id: 'a',
          title: 'Flux a',
          status: 'live',
          isPublic: true,
          createdAt: DateTime.utc(2026, 1, 1),
        );
      final controller = BroadcastSessionController(
        repository,
        _FakePublisher(),
      );

      await expectLater(
        controller.start('a'),
        throwsA(
          isA<BroadcastSessionStartException>().having(
            (e) => e.cause,
            'cause',
            isA<ServerException>(),
          ),
        ),
      );
      expect(repository.stoppedIds, ['a']);

      await controller.dispose();
    });
  });

  group('BroadcastSessionController — panne du micro', () {
    test(
      'un abandon du diffuseur audio termine le direct et est signalé',
      () async {
        final repository = _FakeRepository();
        final publisher = _FakePublisher();
        final controller = BroadcastSessionController(repository, publisher);
        final failures = <BroadcastAudioFailure>[];
        final subscription = controller.audioFailures.listen(failures.add);

        await controller.start('a');
        expect(controller.isPublishing('a'), isTrue);

        publisher.giveUp();
        await _pumpUntil(() => failures.isNotEmpty);

        expect(repository.stoppedIds, ['a']);
        expect(failures.single.streamId, 'a');
        // L'état terminé est transporté avec la panne : la présentation n'a
        // pas à refaire un aller-retour réseau pour réaligner sa liste.
        expect(failures.single.serverState?.status, 'ended');
        expect(controller.publishingStreamId, isNull);
        // Le micro est relâché même si le serveur a répondu : la session locale
        // ne doit pas survivre au direct.
        expect(publisher.stops, 1);

        await subscription.cancel();
        await controller.dispose();
      },
    );

    // Le réseau est souvent coupé au moment même où le micro renonce : l'échec
    // du stop ne doit ni remonter, ni empêcher la notification.
    test('un arrêt serveur en échec ne masque pas la panne', () async {
      final repository = _FakeRepository()..stopError = const NetworkException();
      final publisher = _FakePublisher();
      final controller = BroadcastSessionController(repository, publisher);
      final failures = <BroadcastAudioFailure>[];
      final subscription = controller.audioFailures.listen(failures.add);

      await controller.start('a');
      publisher.giveUp();
      await _pumpUntil(() => failures.isNotEmpty);

      expect(failures.single.streamId, 'a');
      // Arrêt serveur impossible : sans état à jour, la présentation devra
      // recharger la liste elle-même.
      expect(failures.single.serverState, isNull);
      expect(controller.publishingStreamId, isNull);

      await subscription.cancel();
      await controller.dispose();
    });

    test('un arrêt volontaire n\'est pas traité comme une panne', () async {
      final repository = _FakeRepository();
      final publisher = _FakePublisher();
      final controller = BroadcastSessionController(repository, publisher);
      final failures = <BroadcastAudioFailure>[];
      final subscription = controller.audioFailures.listen(failures.add);

      await controller.start('a');
      await controller.stop('a');
      await _pumpUntil(() => controller.publishingStreamId == null);
      // Laisse le temps à un éventuel faux positif d'arriver.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(failures, isEmpty);
      expect(repository.stoppedIds, ['a']); // le stop demandé, pas un second

      await subscription.cancel();
      await controller.dispose();
    });
  });

  test('audioSupported reflète la capacité de la plateforme', () async {
    final unsupported = BroadcastSessionController(
      _FakeRepository(),
      _FakePublisher()..isSupported = false,
    );
    expect(unsupported.audioSupported, isFalse);
    await unsupported.dispose();

    // Sans publisher (tests de présentation) rien n'interdit le démarrage.
    final headless = BroadcastSessionController(_FakeRepository(), null);
    expect(headless.audioSupported, isTrue);
    await headless.dispose();
  });
}
