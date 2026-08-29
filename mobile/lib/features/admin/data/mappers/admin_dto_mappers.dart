import 'package:streampulse_api/streampulse_api.dart';

import '../../domain/entities/admin_chat_message.dart' as domain;
import '../../domain/entities/admin_global_ban.dart';
import '../../domain/entities/admin_stream.dart';
import '../../domain/entities/admin_user.dart';

/// Conversion DTO généré (package `streampulse_api`) → entité domaine.
///
/// Centralise le mapping pour confiner la dépendance au client généré à la
/// couche data : l'entité `AdminUser` reste en `String` pur, l'enum généré
/// (`role`) ne fuite pas hors d'ici (même pattern que `ProfileResponseMapper`).
extension AdminUserResponseMapper on AdminUserResponse {
  AdminUser toEntity() => AdminUser(
    id: id,
    email: email,
    username: username,
    role: role.value,
    isActive: isActive,
    createdAt: createdAt,
  );
}

/// Conversion DTO généré → entité domaine pour la supervision des flux
/// (STR-192). `startedAt` reste nullable de bout en bout (un flux tout juste
/// créé peut ne pas encore être démarré).
extension AdminStreamResponseMapper on AdminStreamResponse {
  AdminStream toEntity() => AdminStream(
    id: id,
    title: title,
    isPublic: isPublic,
    startedAt: startedAt,
    userId: userId,
    username: username,
  );
}

extension AdminChatMessageMapper on AdminChatMessage {
  domain.AdminChatMessage toEntity() => domain.AdminChatMessage(
    id: id,
    streamId: streamId,
    username: username,
    content: content,
    createdAt: createdAt,
    streamTitle: streamTitle,
  );
}

extension AdminGlobalBannedUserMapper on AdminGlobalBannedUser {
  AdminGlobalBan toEntity() => AdminGlobalBan(
    userId: userId,
    username: username,
    reason: reason,
    createdAt: createdAt,
  );
}
