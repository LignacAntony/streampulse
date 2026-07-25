import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_error_mapper.dart';
import '../../domain/entities/admin_stream.dart';
import '../../domain/repositories/admin_streams_repository.dart';
import '../mappers/admin_dto_mappers.dart';

/// Implémentation branchée directement sur `AdminApi` (package généré) :
/// même forme condensée que `AdminRepositoryImpl` — pas de couche
/// `datasource` séparée ici (cf. brief STR-195 / STR-199).
class AdminStreamsRepositoryImpl implements AdminStreamsRepository {
  AdminStreamsRepositoryImpl(this._api);

  final AdminApi _api;

  static const _conflictMessage = 'Action impossible sur ce flux';

  @override
  Future<({List<AdminStream> streams, int total})> listLiveStreams({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _api.listAdminStreams(
        limit: limit,
        offset: offset,
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return (
        streams: body.streams.map((dto) => dto.toEntity()).toList(),
        total: body.total,
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> stopStream(String id) async {
    try {
      await _api.stopAdminStream(id: id);
    } on DioException catch (e) {
      throw mapDioException(e, conflictMessage: _conflictMessage);
    }
  }
}
