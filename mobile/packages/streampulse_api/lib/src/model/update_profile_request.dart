//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'update_profile_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class UpdateProfileRequest {
  /// Returns a new [UpdateProfileRequest] instance.
  UpdateProfileRequest({
    required this.pseudo,

    required this.bio,

    required this.theme,

    required this.notificationsEnabled,

    required this.audioQuality,
  });

  @JsonKey(name: r'pseudo', required: true, includeIfNull: false)
  final String pseudo;

  @JsonKey(name: r'bio', required: true, includeIfNull: false)
  final String bio;

  @JsonKey(name: r'theme', required: true, includeIfNull: false)
  final UpdateProfileRequestThemeEnum theme;

  @JsonKey(name: r'notifications_enabled', required: true, includeIfNull: false)
  final bool notificationsEnabled;

  @JsonKey(name: r'audio_quality', required: true, includeIfNull: false)
  final UpdateProfileRequestAudioQualityEnum audioQuality;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateProfileRequest &&
          other.pseudo == pseudo &&
          other.bio == bio &&
          other.theme == theme &&
          other.notificationsEnabled == notificationsEnabled &&
          other.audioQuality == audioQuality;

  @override
  int get hashCode =>
      pseudo.hashCode +
      bio.hashCode +
      theme.hashCode +
      notificationsEnabled.hashCode +
      audioQuality.hashCode;

  factory UpdateProfileRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdateProfileRequestFromJson(json);

  Map<String, dynamic> toJson() => _$UpdateProfileRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum UpdateProfileRequestThemeEnum {
  @JsonValue(r'system')
  system(r'system'),
  @JsonValue(r'light')
  light(r'light'),
  @JsonValue(r'dark')
  dark(r'dark');

  const UpdateProfileRequestThemeEnum(this.value);

  final String value;

  @override
  String toString() => value;
}

enum UpdateProfileRequestAudioQualityEnum {
  @JsonValue(r'low')
  low(r'low'),
  @JsonValue(r'normal')
  normal(r'normal'),
  @JsonValue(r'high')
  high(r'high');

  const UpdateProfileRequestAudioQualityEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
