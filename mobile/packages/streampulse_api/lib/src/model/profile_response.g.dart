// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProfileResponse _$ProfileResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ProfileResponse',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'id',
            'email',
            'role',
            'pseudo',
            'bio',
            'avatar_url',
            'theme',
            'notifications_enabled',
            'audio_quality',
            'created_at',
          ],
        );
        final val = ProfileResponse(
          id: $checkedConvert('id', (v) => v as String),
          email: $checkedConvert('email', (v) => v as String),
          role: $checkedConvert('role', (v) => v as String),
          pseudo: $checkedConvert('pseudo', (v) => v as String),
          bio: $checkedConvert('bio', (v) => v as String),
          avatarUrl: $checkedConvert('avatar_url', (v) => v as String?),
          theme: $checkedConvert(
            'theme',
            (v) => $enumDecode(_$ProfileResponseThemeEnumEnumMap, v),
          ),
          notificationsEnabled: $checkedConvert(
            'notifications_enabled',
            (v) => v as bool,
          ),
          audioQuality: $checkedConvert(
            'audio_quality',
            (v) => $enumDecode(_$ProfileResponseAudioQualityEnumEnumMap, v),
          ),
          createdAt: $checkedConvert(
            'created_at',
            (v) => DateTime.parse(v as String),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'avatarUrl': 'avatar_url',
        'notificationsEnabled': 'notifications_enabled',
        'audioQuality': 'audio_quality',
        'createdAt': 'created_at',
      },
    );

Map<String, dynamic> _$ProfileResponseToJson(ProfileResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'email': instance.email,
      'role': instance.role,
      'pseudo': instance.pseudo,
      'bio': instance.bio,
      'avatar_url': instance.avatarUrl,
      'theme': _$ProfileResponseThemeEnumEnumMap[instance.theme]!,
      'notifications_enabled': instance.notificationsEnabled,
      'audio_quality':
          _$ProfileResponseAudioQualityEnumEnumMap[instance.audioQuality]!,
      'created_at': instance.createdAt.toIso8601String(),
    };

const _$ProfileResponseThemeEnumEnumMap = {
  ProfileResponseThemeEnum.system: 'system',
  ProfileResponseThemeEnum.light: 'light',
  ProfileResponseThemeEnum.dark: 'dark',
};

const _$ProfileResponseAudioQualityEnumEnumMap = {
  ProfileResponseAudioQualityEnum.low: 'low',
  ProfileResponseAudioQualityEnum.normal: 'normal',
  ProfileResponseAudioQualityEnum.high: 'high',
};
