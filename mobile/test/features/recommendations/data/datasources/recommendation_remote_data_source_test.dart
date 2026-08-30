import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:streampulse/core/constants/api_constants.dart';
import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/recommendations/data/datasources/recommendation_remote_data_source.dart';

/// Verrouille le décodage de `GET /api/recommendations/tracks` (US-09-04) :
/// l'endpoint est appelé via le Dio brut (hors client généré), c'est donc ici
/// que la réponse JSON devient une entité.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late RecommendationRemoteDataSource dataSource;

  const path = ApiConstants.recommendedTracks;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    adapter = DioAdapter(dio: dio);
    dataSource = RecommendationRemoteDataSource(dio);
  });

  test('200 → mappe les pistes recommandées (dont artiste/durée nulls)', () async {
    adapter.onGet(path, (server) {
      server.reply(200, [
        {
          'id': 't-1',
          'title': 'One More Time',
          'artist': 'Daft Punk',
          'duration_s': 320,
          'reason': 'Parce que vous écoutez souvent Daft Punk',
        },
        {
          'id': 't-2',
          'title': 'Sans métadonnées',
          'artist': null,
          'duration_s': null,
          'reason': 'Nouveauté de votre bibliothèque',
        },
      ]);
    });

    final result = await dataSource.fetch();

    expect(result, hasLength(2));
    expect(result[0].track.id, 't-1');
    expect(result[0].track.title, 'One More Time');
    expect(result[0].track.artist, 'Daft Punk');
    expect(result[0].track.durationS, 320);
    expect(result[0].reason, 'Parce que vous écoutez souvent Daft Punk');
    expect(result[1].track.artist, isNull);
    expect(result[1].track.durationS, isNull);
    expect(result[1].reason, 'Nouveauté de votre bibliothèque');
  });

  test('200 avec tableau vide → liste vide', () async {
    adapter.onGet(path, (server) => server.reply(200, <dynamic>[]));
    expect(await dataSource.fetch(), isEmpty);
  });

  test('500 → exception typée (mapDioException)', () async {
    adapter.onGet(path, (server) => server.reply(500, {'error': 'boom'}));
    expect(dataSource.fetch(), throwsA(isA<Exception>()));
  });

  test('erreur réseau → NetworkException', () async {
    adapter.onGet(
      path,
      (server) => server.throws(
        0,
        DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionError,
        ),
      ),
    );
    expect(dataSource.fetch(), throwsA(isA<NetworkException>()));
  });
}
