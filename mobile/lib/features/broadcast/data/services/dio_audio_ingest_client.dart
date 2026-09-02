import 'package:dio/dio.dart';

import 'audio_ingest_client.dart';

/// Client Dio sans timeout de réception ni intercepteur d'auth, dédié aux
/// requêtes d'ingest longues. Un `Stream` sans `Content-Length` devient un
/// transfert HTTP chunked sans accumulation en mémoire.
class DioAudioIngestClient implements AudioIngestClient {
  DioAudioIngestClient([Dio? dio])
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: null,
              sendTimeout: null,
            ),
          );

  final Dio _dio;
  CancelToken? _cancelToken;

  @override
  Future<void> push(Uri sourceUrl, Stream<List<int>> audio) async {
    final token = CancelToken();
    _cancelToken = token;
    try {
      await _dio.postUri<void>(
        sourceUrl,
        data: audio,
        cancelToken: token,
        options: Options(
          contentType: 'audio/aac',
          responseType: ResponseType.plain,
          // 409 accepté ici pour être traduit ci-dessous : laissé aux status
          // valides, il ressortirait en `DioException` indifférenciée et la
          // boucle de reprise le prendrait pour une panne réseau.
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
    } on DioException catch (e) {
      // Un autre encodeur pousse déjà sur cette clé : ce n'est pas une panne,
      // et réessayer finirait par tuer SON direct (cf. IngestConflictException).
      if (e.response?.statusCode == 409) {
        throw const IngestConflictException();
      }
      rethrow;
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
  }

  @override
  Future<void> cancel() async {
    _cancelToken?.cancel('Diffusion audio arrêtée');
    _cancelToken = null;
  }
}
