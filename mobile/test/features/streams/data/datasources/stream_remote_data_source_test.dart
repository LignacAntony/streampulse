import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:streampulse_api/streampulse_api.dart';

import 'package:streampulse/core/constants/api_constants.dart';
import 'package:streampulse/features/streams/data/datasources/stream_remote_data_source.dart';
import 'package:streampulse/features/streams/domain/entities/manifest_status.dart';

/// Verrouille la traduction « réponse HTTP du manifeste → verdict » (STR-229).
///
/// C'est le seul endroit du client qui *interprète* un code d'erreur métier
/// plutôt que de l'afficher, et l'interprétation gouverne un choix visible pour
/// l'auditeur : annoncer la fin du direct, ou patienter. De vraies réponses
/// passent donc par un vrai `Dio`, plutôt qu'un faux datasource — le mapping
/// lui-même est ce qu'on teste.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late StreamRemoteDataSource dataSource;

  const streamId = 's1';
  final path = ApiConstants.playlistPath(streamId);

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    adapter = DioAdapter(dio: dio);
    dataSource = StreamRemoteDataSource(StreamingApi(dio), dio);
  });

  group('manifestStatus', () {
    test('200 → available', () async {
      adapter.onGet(path, (server) => server.reply(200, '#EXTM3U'));

      expect(await dataSource.manifestStatus(streamId), ManifestStatus.available);
    });

    test('409 stream_not_live → ended', () async {
      adapter.onGet(
        path,
        (server) => server.reply(409, {
          'error': {'code': 'stream_not_live', 'message': 'stream is not live'},
        }),
      );

      expect(await dataSource.manifestStatus(streamId), ManifestStatus.ended);
    });

    test('409 manifest_not_ready → notReady', () async {
      adapter.onGet(
        path,
        (server) => server.reply(409, {
          'error': {
            'code': 'manifest_not_ready',
            'message': 'stream manifest is not ready yet',
          },
        }),
      );

      expect(await dataSource.manifestStatus(streamId), ManifestStatus.notReady);
    });

    test('404 (flux absent, archivé ou privé) → ended', () async {
      adapter.onGet(
        path,
        (server) => server.reply(404, {
          'error': {'code': 'not_found', 'message': 'stream not found'},
        }),
      );

      expect(await dataSource.manifestStatus(streamId), ManifestStatus.ended);
    });

    test('409 sans code reconnu → notReady (défaut prudent)', () async {
      // Le cas d'un backend antérieur à STR-229, qui rend un `conflict` nu.
      // Le défaut doit pencher vers l'attente : se tromper dans l'autre sens
      // couperait un direct en train de démarrer — précisément le bug corrigé.
      adapter.onGet(
        path,
        (server) => server.reply(409, {
          'error': {'code': 'conflict', 'message': 'stream is not live'},
        }),
      );

      expect(await dataSource.manifestStatus(streamId), ManifestStatus.notReady);
    });

    test('409 au corps inattendu → notReady, sans lever', () async {
      // Une sonde de reprise ne doit jamais échouer sur la forme du corps :
      // elle est appelée depuis un chemin de récupération d'erreur.
      adapter.onGet(path, (server) => server.reply(409, 'pas du json'));

      expect(await dataSource.manifestStatus(streamId), ManifestStatus.notReady);
    });

    test('503 (capacité auditeurs atteinte) → unknown, jamais ended', () async {
      // Le direct est bien vivant : le serveur refuse temporairement de servir.
      // Conclure « terminé » ici afficherait une fin de direct inexistante à
      // tous les auditeurs refusés d'un flux populaire.
      adapter.onGet(
        path,
        (server) => server.reply(503, {
          'error': {'code': 'unavailable', 'message': 'at capacity'},
        }),
      );

      expect(await dataSource.manifestStatus(streamId), ManifestStatus.unknown);
    });

    test('réseau indisponible → unknown', () async {
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

      expect(await dataSource.manifestStatus(streamId), ManifestStatus.unknown);
    });
  });
}
