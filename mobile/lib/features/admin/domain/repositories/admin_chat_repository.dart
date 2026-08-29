import '../entities/admin_chat_message.dart';
import '../entities/admin_global_ban.dart';

abstract class AdminChatRepository {
  Future<List<AdminChatMessage>> listUserMessages(
    String userId, {
    int limit = 20,
    int offset = 0,
  });

  Future<void> globalBan(String userId, {String? reason});
  Future<void> globalUnban(String userId);
  Future<List<AdminGlobalBan>> listGlobalBans();
}
