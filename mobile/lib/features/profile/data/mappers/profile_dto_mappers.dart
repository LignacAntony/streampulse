import 'package:streampulse_api/streampulse_api.dart';

import '../../domain/entities/user_profile.dart';

/// Conversions DTO généré (package `streampulse_api`) ↔ entité domaine.
///
/// Centralise le mapping pour confiner la dépendance au client généré à la
/// couche data : l'entité `UserProfile` reste en `String` pur, les enums
/// générés (`theme`, `audio_quality`) ne fuitent pas hors d'ici.
extension ProfileResponseMapper on ProfileResponse {
  UserProfile toEntity() => UserProfile(
        id: id,
        email: email,
        role: role,
        pseudo: pseudo,
        bio: bio,
        avatarUrl: avatarUrl,
        theme: theme.value,
        notificationsEnabled: notificationsEnabled,
        audioQuality: audioQuality.value,
        createdAt: createdAt,
      );
}

/// Construit le corps du `PUT /api/users/me` à partir de l'entité domaine.
/// Seuls les champs modifiables sont envoyés (cf. `UpdateProfileRequest`).
extension UserProfileUpdateMapper on UserProfile {
  UpdateProfileRequest toUpdateRequest() => UpdateProfileRequest(
        pseudo: pseudo,
        bio: bio,
        theme: _themeFromString(theme),
        notificationsEnabled: notificationsEnabled,
        audioQuality: _audioQualityFromString(audioQuality),
      );
}

UpdateProfileRequestThemeEnum _themeFromString(String value) =>
    UpdateProfileRequestThemeEnum.values.firstWhere(
      (e) => e.value == value,
      orElse: () => UpdateProfileRequestThemeEnum.system,
    );

UpdateProfileRequestAudioQualityEnum _audioQualityFromString(String value) =>
    UpdateProfileRequestAudioQualityEnum.values.firstWhere(
      (e) => e.value == value,
      orElse: () => UpdateProfileRequestAudioQualityEnum.normal,
    );
