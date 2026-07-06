import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/streams/domain/entities/live_stream.dart';
import 'package:streampulse/features/streams/domain/repositories/stream_repository.dart';
import 'package:streampulse/features/streams/presentation/providers/stream_notifier.dart';

LiveStream _stream(String id) => LiveStream(
      id: id,
      title: 'Flux $id',
      startedAt: DateTime.utc(2026, 1, 1),
    );

class _FakeRepository implements StreamRepository {
  _FakeRepository({this.result = const [], this.error});

  List<LiveStream> result;
  Object? error;
  int calls = 0;

  @override
  Future<List<LiveStream>> listLiveStreams({int limit = 20, int offset = 0}) async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  group('StreamNotifier.load', () {
    test('succès avec flux : expose la liste, isEmpty faux', () async {
      final notifier = StreamNotifier(
        _FakeRepository(result: [_stream('a'), _stream('b')]),
      );

      await notifier.load();

      expect(notifier.streams, hasLength(2));
      expect(notifier.isLoading, isFalse);
      expect(notifier.hasError, isFalse);
      expect(notifier.isEmpty, isFalse);
    });

    test('succès sans flux : isEmpty vrai (état vide)', () async {
      final notifier = StreamNotifier(_FakeRepository(result: const []));

      await notifier.load();

      expect(notifier.streams, isEmpty);
      expect(notifier.isEmpty, isTrue);
      expect(notifier.hasError, isFalse);
    });

    test('échec réseau sans donnée : hasError vrai, ne relance pas', () async {
      final notifier = StreamNotifier(
        _FakeRepository(error: const NetworkException()),
      );

      await expectLater(notifier.load(), completes);

      expect(notifier.hasError, isTrue);
      expect(notifier.streams, isEmpty);
      expect(notifier.isEmpty, isFalse);
    });
  });

  group('StreamNotifier.refresh', () {
    test('conserve les flux déjà chargés si un rafraîchissement échoue', () async {
      final repo = _FakeRepository(result: [_stream('a')]);
      final notifier = StreamNotifier(repo);
      await notifier.load();
      expect(notifier.streams, hasLength(1));

      repo.error = const NetworkException();
      await notifier.refresh();

      expect(notifier.streams, hasLength(1));
      expect(notifier.hasError, isTrue);
    });
  });
}
