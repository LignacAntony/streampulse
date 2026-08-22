import 'package:dio/dio.dart';

import '../../domain/entities/banned_user.dart';

abstract class ChatBanRepository {
  Future<List<BannedUser>> listBans();
  Future<void> unban(String userId);
}

class ChatBanRepositoryImpl implements ChatBanRepository {
  ChatBanRepositoryImpl(this._dio);

  final Dio _dio;

  @override
  Future<List<BannedUser>> listBans() async {
    final response = await _dio.get<List<dynamic>>('/api/chat/bans');
    final data = response.data ?? [];
    return data.map((e) {
      final map = e as Map<String, dynamic>;
      return BannedUser(
        userId: map['user_id'] as String,
        username: map['username'] as String,
        reason: map['reason'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );
    }).toList();
  }

  @override
  Future<void> unban(String userId) async {
    await _dio.delete<void>('/api/chat/bans/$userId');
  }
}
