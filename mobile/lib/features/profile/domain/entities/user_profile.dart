import 'package:equatable/equatable.dart';

/// Profil de l'utilisateur connecté (`GET` / `PUT /api/users/me`).
class UserProfile extends Equatable {
  const UserProfile({
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

  UserProfile copyWith({
    String? pseudo,
    String? bio,
    String? theme,
    bool? notificationsEnabled,
    String? audioQuality,
  }) {
    return UserProfile(
      id: id,
      email: email,
      role: role,
      pseudo: pseudo ?? this.pseudo,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl,
      theme: theme ?? this.theme,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      audioQuality: audioQuality ?? this.audioQuality,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        email,
        role,
        pseudo,
        bio,
        avatarUrl,
        theme,
        notificationsEnabled,
        audioQuality,
        createdAt,
      ];
}
