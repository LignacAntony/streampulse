//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'profile_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ProfileResponse {
  /// Returns a new [ProfileResponse] instance.
  ProfileResponse({
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

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'email', required: true, includeIfNull: false)
  final String email;

  @JsonKey(name: r'role', required: true, includeIfNull: false)
  final String role;

  @JsonKey(name: r'pseudo', required: true, includeIfNull: false)
  final String pseudo;

  @JsonKey(name: r'bio', required: true, includeIfNull: false)
  final String bio;

  @JsonKey(name: r'avatar_url', required: true, includeIfNull: true)
  final String? avatarUrl;

  @JsonKey(name: r'theme', required: true, includeIfNull: false)
  final ProfileResponseThemeEnum theme;

  @JsonKey(name: r'notifications_enabled', required: true, includeIfNull: false)
  final bool notificationsEnabled;

  @JsonKey(name: r'audio_quality', required: true, includeIfNull: false)
  final ProfileResponseAudioQualityEnum audioQuality;

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileResponse &&
          other.id == id &&
          other.email == email &&
          other.role == role &&
          other.pseudo == pseudo &&
          other.bio == bio &&
          other.avatarUrl == avatarUrl &&
          other.theme == theme &&
          other.notificationsEnabled == notificationsEnabled &&
          other.audioQuality == audioQuality &&
          other.createdAt == createdAt;

  @override
  int get hashCode =>
      id.hashCode +
      email.hashCode +
      role.hashCode +
      pseudo.hashCode +
      bio.hashCode +
      (avatarUrl == null ? 0 : avatarUrl.hashCode) +
      theme.hashCode +
      notificationsEnabled.hashCode +
      audioQuality.hashCode +
      createdAt.hashCode;

  factory ProfileResponse.fromJson(Map<String, dynamic> json) =>
      _$ProfileResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ProfileResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum ProfileResponseThemeEnum {
  @JsonValue(r'system')
  system(r'system'),
  @JsonValue(r'light')
  light(r'light'),
  @JsonValue(r'dark')
  dark(r'dark');

  const ProfileResponseThemeEnum(this.value);

  final String value;

  @override
  String toString() => value;
}

enum ProfileResponseAudioQualityEnum {
  @JsonValue(r'low')
  low(r'low'),
  @JsonValue(r'normal')
  normal(r'normal'),
  @JsonValue(r'high')
  high(r'high');

  const ProfileResponseAudioQualityEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
