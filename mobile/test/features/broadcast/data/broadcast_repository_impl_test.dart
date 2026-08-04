import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:streampulse_api/streampulse_api.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/broadcast/data/datasources/broadcast_remote_data_source.dart';
import 'package:streampulse/features/broadcast/data/mappers/broadcast_dto_mappers.dart';
import 'package:streampulse/features/broadcast/data/repositories/broadcast_repository_impl.dart';

/// Fait passer de vraies réponses HTTP à travers un vrai `Dio` et le
/// `StreamingApi` généré (même style que `admin_streams_repository_impl_test`),
/// pour verrouiller à la fois le mapping DTO -> entité et la traduction des
/// erreurs Dio en exceptions typées.
Map<String, Object?> _streamJson(
  String id, {
  String status = 'idle',
  String? streamKey = 'cle-secrete',
  String? sourceUrl = 'http://localhost:8080/api/streams/ingest/cle-secrete',
  bool isPublic = true,
  String? category,
  String? startedAt,
}) =>
    {
      'id': id,
      'user_id': 'u-1',
      'title': 'Flux $id',
      'description': null,
      'category': category,
      'status': status,
      'is_public': isPublic,
      'stream_key': streamKey,
      'stream_source_url': sourceUrl,
      'started_at': startedAt,
      'ended_at': null,
      'created_at': '2026-01-02T03:04:05.000Z',
      'updated_at': '2026-01-02T03:04:05.000Z',
    };

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late BroadcastRepositoryImpl repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    adapter = DioAdapter(dio: dio);
    repository = BroadcastRepositoryImpl(
      BroadcastRemoteDataSource(StreamingApi(dio)),
    );
  });

  group('BroadcastRepositoryImpl.listMyStreams', () {
    test('convertit les DTO en entités, secrets compris', () async {
      adapter.onGet(
        '/api/users/me/streams',
        (server) => server.reply(200, [
          _streamJson(
            's-1',
            status: 'live',
            category: 'music',
            startedAt: '2026-01-02T03:04:05.000Z',
          ),
        ]),
      );

      final streams = await repository.listMyStreams();

      expect(streams, hasLength(1));
      final stream = streams.single;
      expect(stream.id, 's-1');
      expect(stream.status, 'live');
      expect(stream.isLive, isTrue);
      expect(stream.category, 'music');
      expect(stream.startedAt, DateTime.parse('2026-01-02T03:04:05.000Z'));
      // Le propriétaire est le seul destinataire : les secrets doivent bien
      // traverser le mapper, contrairement à la vue auditeur.
      expect(stream.streamKey, 'cle-secrete');
      expect(
        stream.streamSourceUrl,
        'http://localhost:8080/api/streams/ingest/cle-secrete',
      );
    });

    test('liste vide : aucun flux, aucune erreur', () async {
      adapter.onGet(
        '/api/users/me/streams',
        (server) => server.reply(200, <Object?>[]),
      );

      expect(await repository.listMyStreams(), isEmpty);
    });

    test('401 -> AuthException', () async {
      adapter.onGet(
        '/api/users/me/streams',
        (server) => server.reply(401, {
          'error': {'code': 'unauthorized', 'message': 'unauthenticated'},
        }),
      );

      await expectLater(
        repository.listMyStreams(),
        throwsA(isA<AuthException>()),
      );
    });

    test('panne réseau -> NetworkException', () async {
      adapter.onGet(
        '/api/users/me/streams',
        (server) => server.throws(
          0,
          DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/users/me/streams'),
            reason: 'connexion refusée',
          ),
        ),
      );

      await expectLater(
        repository.listMyStreams(),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('BroadcastRepositoryImpl.createStream', () {
    test('envoie les champs saisis et renvoie le flux créé', () async {
      // Corps attendu tel que le client généré l'encode (jsonEncode d'une
      // String, description omise car nulle) : verrouille au passage la
      // traduction de la catégorie domaine vers l'énumération du DTO.
      adapter.onPost(
        '/api/streams',
        (server) => server.reply(201, _streamJson('s-new', category: 'talk')),
        data: '{"title":"Le talk du soir","category":"talk","is_public":true}',
      );

      final created = await repository.createStream(
        title: 'Le talk du soir',
        isPublic: true,
        category: 'talk',
      );

      expect(created.id, 's-new');
      expect(created.category, 'talk');
      expect(created.isIdle, isTrue);
    });

    test('400 -> ValidationException avec le message serveur', () async {
      adapter.onPost(
        '/api/streams',
        (server) => server.reply(400, {
          'error': {'code': 'invalid_argument', 'message': 'invalid title'},
        }),
        data: '{"title":"ab","is_public":true}',
      );

      await expectLater(
        repository.createStream(title: 'ab', isPublic: true),
        throwsA(
          isA<ValidationException>()
              .having((e) => e.message, 'message', 'invalid title'),
        ),
      );
    });
  });

  group('BroadcastRepositoryImpl.startStream / stopStream', () {
    test('start renvoie le flux passé en direct', () async {
      adapter.onPatch(
        '/api/streams/s-1/start',
        (server) => server.reply(
          200,
          _streamJson('s-1', status: 'live', startedAt: '2026-01-02T03:04:05.000Z'),
        ),
      );

      final started = await repository.startStream('s-1');

      expect(started.isLive, isTrue);
      expect(started.startedAt, isNotNull);
    });

    test('409 sur start -> ConflictException', () async {
      adapter.onPatch(
        '/api/streams/s-2/start',
        (server) => server.reply(409, {
          'error': {
            'code': 'conflict',
            'message': 'you already have a live stream',
          },
        }),
      );

      await expectLater(
        repository.startStream('s-2'),
        throwsA(isA<ConflictException>()),
      );
    });

    test('stop renvoie le flux terminé', () async {
      adapter.onPatch(
        '/api/streams/s-1/stop',
        (server) => server.reply(200, _streamJson('s-1', status: 'ended')),
      );

      final stopped = await repository.stopStream('s-1');

      expect(stopped.isEnded, isTrue);
    });
  });

  group('streamCategoryToDto', () {
    test('traduit une catégorie de la liste blanche', () {
      expect(
        streamCategoryToDto('gaming'),
        CreateStreamRequestCategoryEnum.gaming,
      );
    });

    test('null et valeur inconnue donnent une absence de catégorie', () {
      expect(streamCategoryToDto(null), isNull);
      // Le formulaire ne propose que des valeurs valides : ce cas n'arrive que
      // si le backend retire une catégorie de sa liste blanche.
      expect(streamCategoryToDto('philosophie'), isNull);
    });
  });
}
