import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:streampulse_api/streampulse_api.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/playlists/data/datasources/playlist_remote_data_source.dart';
import 'package:streampulse/features/playlists/data/repositories/playlist_repository_impl.dart';

/// Fait passer de vraies réponses HTTP à travers un vrai `Dio` + le
/// `PlaylistApi` généré (via `DioAdapter`), pour valider à la fois les mappers
/// DTO -> entité et la traduction DioException -> exception typée.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late PlaylistRepositoryImpl repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    adapter = DioAdapter(dio: dio);
    repository = PlaylistRepositoryImpl(
      PlaylistRemoteDataSource(PlaylistApi(dio), TrackApi(dio)),
    );
  });

  group('list', () {
    test('succès : mappe les playlists avec track_count', () async {
      adapter.onGet(
        '/api/playlists',
        (server) => server.reply(200, [
          {
            'id': 'p-1',
            'name': 'My Favorites',
            'description': 'Ma playlist préférée',
            'is_public': true,
            'track_count': 3,
            'created_at': '2026-01-02T03:04:05.000Z',
            'updated_at': '2026-01-02T03:04:05.000Z',
          },
        ]),
      );

      final result = await repository.list();

      expect(result, hasLength(1));
      expect(result.single.id, 'p-1');
      expect(result.single.name, 'My Favorites');
      expect(result.single.trackCount, 3);
      expect(result.single.isPublic, isTrue);
    });
  });

  group('create', () {
    test('succès : mappe la playlist créée (vide)', () async {
      adapter.onPost(
        '/api/playlists',
        (server) => server.reply(201, {
          'id': 'p-2',
          'name': 'Road Trip',
          'description': null,
          'is_public': false,
          'track_count': 0,
          'created_at': '2026-01-02T03:04:05.000Z',
          'updated_at': '2026-01-02T03:04:05.000Z',
        }),
        data: Matchers.any,
      );

      final playlist = await repository.create('Road Trip', null);

      expect(playlist.id, 'p-2');
      expect(playlist.description, isNull);
      expect(playlist.trackCount, 0);
    });

    test('409 -> ConflictException (nom déjà utilisé)', () async {
      adapter.onPost(
        '/api/playlists',
        (server) => server.reply(409, {
          'error': {
            'code': 'conflict',
            'message': 'une playlist porte déjà ce nom',
          },
        }),
        data: Matchers.any,
      );

      await expectLater(
        repository.create('My Favorites', null),
        throwsA(isA<ConflictException>()),
      );
    });

    test('400 -> ValidationException', () async {
      adapter.onPost(
        '/api/playlists',
        (server) => server.reply(400, {
          'error': {'code': 'invalid_argument', 'message': 'invalid name'},
        }),
        data: Matchers.any,
      );

      await expectLater(
        repository.create('x', null),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('rename', () {
    test('succès : mappe la playlist mise à jour', () async {
      adapter.onPut(
        '/api/playlists/p-1',
        (server) => server.reply(200, {
          'id': 'p-1',
          'name': 'Jazz',
          'description': null,
          'is_public': false,
          'track_count': 2,
          'created_at': '2026-01-02T03:04:05.000Z',
          'updated_at': '2026-01-02T04:00:00.000Z',
        }),
        data: Matchers.any,
      );

      final playlist = await repository.rename('p-1', 'Jazz', null);

      expect(playlist.name, 'Jazz');
      expect(playlist.trackCount, 2);
    });

    test('404 -> ServerException (playlist d\'un tiers)', () async {
      adapter.onPut(
        '/api/playlists/p-9',
        (server) => server.reply(404, {
          'error': {'code': 'not_found', 'message': 'playlist not found'},
        }),
        data: Matchers.any,
      );

      await expectLater(
        repository.rename('p-9', 'Jazz', null),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('delete', () {
    test('succès (204)', () async {
      adapter.onDelete(
        '/api/playlists/p-1',
        (server) => server.reply(204, null),
      );

      await expectLater(repository.delete('p-1'), completes);
    });
  });

  group('tracks', () {
    test('succès : mappe les pistes (artist/duration nullables)', () async {
      adapter.onGet(
        '/api/playlists/p-1/tracks',
        (server) => server.reply(200, [
          {
            'id': 't-1',
            'title': 'Midnight Drive',
            'artist': 'Neon Lights',
            'duration_s': 214,
            'position': 0,
          },
          {
            'id': 't-2',
            'title': 'Untitled',
            'artist': null,
            'duration_s': null,
            'position': 1,
          },
        ]),
      );

      final tracks = await repository.tracks('p-1');

      expect(tracks, hasLength(2));
      expect(tracks[0].artist, 'Neon Lights');
      expect(tracks[0].durationS, 214);
      expect(tracks[1].artist, isNull);
      expect(tracks[1].durationS, isNull);
    });
  });
}
