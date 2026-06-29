import 'package:streampulse_api/streampulse_api.dart';

import '../../domain/entities/token_pair.dart';
import '../../domain/entities/user.dart';

/// Conversions DTO généré (package `streampulse_api`) → entités domaine.
///
/// Centralise le mapping pour garder `AuthRepositoryImpl` mince et confiner la
/// dépendance au client généré à la couche data (l'ancien `*Model.toEntity()`
/// jouait ce rôle avant la migration vers les DTOs OpenAPI).
extension UserResponseMapper on UserResponse {
  User toEntity() => User(
    id: id,
    email: email,
    username: username,
    role: role,
    createdAt: createdAt,
  );
}

extension TokenPairResponseMapper on TokenPairResponse {
  TokenPair toEntity() =>
      TokenPair(accessToken: accessToken, refreshToken: refreshToken);
}
