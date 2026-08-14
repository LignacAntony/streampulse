import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:streampulse_api/streampulse_api.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/admin/data/mappers/admin_dto_mappers.dart';
import 'package:streampulse/features/admin/data/repositories/admin_streams_repository_impl.dart';

/// `AdminStreamsRepositoryImpl` n'a pas de couche `datasource` séparée (même
/// forme condensée que `AdminRepositoryImpl`, cf. brief STR-199) : le mapping
/// DioException -> exception typée vit directement dedans. On fait donc
/// passer de vraies réponses HTTP à travers un vrai `Dio` + le vrai
/// `AdminApi` généré, via `DioAdapter` — même style que
/// `admin_repository_impl_test.dart`.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AdminStreamsRepositoryImpl repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    adapter = DioAdapter(dio: dio);
    repository = AdminStreamsRepositoryImpl(AdminApi(dio));
  });

  group('AdminStreamResponseMapper', () {
    test(
      'convertit tous les champs vers AdminStream (startedAt renseigné)',
      () {
        final dto = AdminStreamResponse(
          id: 's-1',
          title: 'Chill beats',
          isPublic: true,
          startedAt: DateTime.parse('2026-01-02T03:04:05.000Z'),
          userId: 'u-1',
          username: 'alice',
        );

        final entity = dto.toEntity();

        expect(entity.id, 's-1');
        expect(entity.title, 'Chill beats');
        expect(entity.isPublic, isTrue);
        expect(entity.startedAt, DateTime.parse('2026-01-02T03:04:05.000Z'));
        expect(entity.userId, 'u-1');
        expect(entity.username, 'alice');
      },
    );

    test('convertit startedAt null (flux pas encore démarré)', () {
      final dto = AdminStreamResponse(
        id: 's-2',
        title: 'Late night jazz',
        isPublic: false,
        startedAt: null,
        userId: 'u-2',
        username: 'bob',
      );

      final entity = dto.toEntity();

      expect(entity.id, 's-2');
      expect(entity.title, 'Late night jazz');
      expect(entity.isPublic, isFalse);
      expect(entity.startedAt, isNull);
      expect(entity.userId, 'u-2');
      expect(entity.username, 'bob');
    });
  });

  group('AdminStreamsRepositoryImpl.listLiveStreams', () {
    test(
      'succès : mappe la liste + le total et transmet limit/offset',
      () async {
        adapter.onGet(
          '/api/admin/streams',
          (server) => server.reply(200, {
            'streams': [
              {
                'id': 's-1',
                'title': 'Chill beats',
                'is_public': true,
                'started_at': '2026-01-02T03:04:05.000Z',
                'user_id': 'u-1',
                'username': 'alice',
              },
            ],
            'total': 7,
          }),
          queryParameters: {'limit': 10, 'offset': 5},
        );

        final result = await repository.listLiveStreams(limit: 10, offset: 5);

        expect(result.total, 7);
        expect(result.streams, hasLength(1));
        expect(result.streams.single.id, 's-1');
        expect(result.streams.single.username, 'alice');
        expect(
          result.streams.single.startedAt,
          DateTime.parse('2026-01-02T03:04:05.000Z'),
        );
      },
    );
  });

  group('AdminStreamsRepositoryImpl.stopStream', () {
    test('succès : arrête le flux (204)', () async {
      adapter.onPost(
        '/api/admin/streams/s-1/stop',
        (server) => server.reply(204, null),
      );

      await expectLater(repository.stopStream('s-1'), completes);
    });

    test('409 -> ConflictException avec le message serveur', () async {
      adapter.onPost(
        '/api/admin/streams/s-1/stop',
        (server) => server.reply(409, {
          'error': {'code': 'conflict', 'message': 'stream already ended'},
        }),
      );

      await expectLater(
        repository.stopStream('s-1'),
        throwsA(
          isA<ConflictException>().having(
            (e) => e.message,
            'message',
            'stream already ended',
          ),
        ),
      );
    });

    test('404 -> exception typée avec le message serveur', () async {
      adapter.onPost(
        '/api/admin/streams/s-1/stop',
        (server) => server.reply(404, {
          'error': {'code': 'not_found', 'message': 'stream not found'},
        }),
      );

      await expectLater(
        repository.stopStream('s-1'),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            'stream not found',
          ),
        ),
      );
    });

    test('erreur réseau -> NetworkException', () async {
      adapter.onPost(
        '/api/admin/streams/s-1/stop',
        (server) => server.throws(
          500,
          DioException(
            type: DioExceptionType.connectionError,
            requestOptions: RequestOptions(
              path: '/api/admin/streams/s-1/stop',
            ),
          ),
        ),
      );

      await expectLater(
        repository.stopStream('s-1'),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
