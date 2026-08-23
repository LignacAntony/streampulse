import 'package:dio/dio.dart';
import 'package:streampulse_api/streampulse_api.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_error_mapper.dart';
import '../../domain/entities/admin_chat_message.dart' as domain;
import '../../domain/entities/admin_global_ban.dart';
import '../../domain/repositories/admin_chat_repository.dart';
import '../mappers/admin_dto_mappers.dart';

class AdminChatRepositoryImpl implements AdminChatRepository {
  AdminChatRepositoryImpl(this._api);

  final AdminApi _api;

  @override
  Future<List<domain.AdminChatMessage>> listUserMessages(
    String userId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _api.listAdminUserChatMessages(
        id: userId,
        limit: limit,
        offset: offset,
      );
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body.map((dto) => dto.toEntity()).toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> globalBan(String userId, {String? reason}) async {
    try {
      await _api.globalBanUser(
        id: userId,
        globalBanUserRequest: GlobalBanUserRequest(reason: reason),
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> globalUnban(String userId) async {
    try {
      await _api.globalUnbanUser(id: userId);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<AdminGlobalBan>> listGlobalBans() async {
    try {
      final response = await _api.listGlobalChatBans();
      final body = response.data;
      if (body == null) {
        throw const ServerException('Réponse vide du serveur');
      }
      return body.map((dto) => dto.toEntity()).toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
