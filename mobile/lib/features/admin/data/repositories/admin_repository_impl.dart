import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_error_mapper.dart';
import '../../domain/entities/admin_user.dart';
import '../../domain/repositories/admin_repository.dart';
import '../mappers/admin_dto_mappers.dart';

/// Implémentation branchée directement sur `AdminApi` (package généré) :
/// contrairement à `auth`/`streams`/`profile`, il n'y a pas de couche
/// `datasource` séparée ici (3 endpoints seulement, cf. brief STR-195).
class AdminRepositoryImpl implements AdminRepository {
  AdminRepositoryImpl(this._api);

  final AdminApi _api;

  static const _conflictMessage = 'Action impossible sur ce compte';

  @override
  Future<({List<AdminUser> users, int total})> listUsers({
    String? search,
    String? role,
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _api.listAdminUsers(
        search: search,
        role: role,
        status: status,
        limit: limit,
        offset: offset,
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return (
        users: body.users.map((dto) => dto.toEntity()).toList(),
        total: body.total,
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<AdminUser> setUserActive(String id, bool active) async {
    try {
      final response = await _api.setAdminUserActive(
        id: id,
        setUserActiveRequest: SetUserActiveRequest(isActive: active),
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body.toEntity();
    } on DioException catch (e) {
      throw mapDioException(e, conflictMessage: _conflictMessage);
    }
  }

  @override
  Future<void> deleteUser(String id) async {
    try {
      await _api.deleteAdminUser(id: id);
    } on DioException catch (e) {
      throw mapDioException(e, conflictMessage: _conflictMessage);
    }
  }
}
