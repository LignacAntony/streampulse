import '../../domain/entities/user_profile.dart';

class UserProfileModel {
  const UserProfileModel({
    required this.id,
    required this.email,
    required this.role,
    required this.pseudo,
    required this.bio,
    required this.avatarUrl,
    required this.theme,
    required this.notificationsEnabled,
    required this.audioQuality,
    required this.createdAt,
  });

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      id: json['id'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      pseudo: json['pseudo'] as String,
      bio: (json['bio'] as String?) ?? '',
      avatarUrl: json['avatar_url'] as String?,
      theme: json['theme'] as String,
      notificationsEnabled: json['notifications_enabled'] as bool,
      audioQuality: json['audio_quality'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String email;
  final String role;
  final String pseudo;
  final String bio;
  final String? avatarUrl;
  final String theme;
  final bool notificationsEnabled;
  final String audioQuality;
  final DateTime createdAt;

  /// Corps du `PUT /api/users/me` — uniquement les champs modifiables.
  Map<String, dynamic> toUpdateJson() => {
        'pseudo': pseudo,
        'bio': bio,
        'theme': theme,
        'notifications_enabled': notificationsEnabled,
        'audio_quality': audioQuality,
      };

  UserProfile toEntity() => UserProfile(
        id: id,
        email: email,
        role: role,
        pseudo: pseudo,
        bio: bio,
        avatarUrl: avatarUrl,
        theme: theme,
        notificationsEnabled: notificationsEnabled,
        audioQuality: audioQuality,
        createdAt: createdAt,
      );

  static UserProfileModel fromEntity(UserProfile p) => UserProfileModel(
        id: p.id,
        email: p.email,
        role: p.role,
        pseudo: p.pseudo,
        bio: p.bio,
        avatarUrl: p.avatarUrl,
        theme: p.theme,
        notificationsEnabled: p.notificationsEnabled,
        audioQuality: p.audioQuality,
        createdAt: p.createdAt,
      );
}
