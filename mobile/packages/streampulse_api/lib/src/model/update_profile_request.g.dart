// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_profile_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateProfileRequest _$UpdateProfileRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'UpdateProfileRequest',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'pseudo',
        'bio',
        'theme',
        'notifications_enabled',
        'audio_quality',
      ],
    );
    final val = UpdateProfileRequest(
      pseudo: $checkedConvert('pseudo', (v) => v as String),
      bio: $checkedConvert('bio', (v) => v as String),
      theme: $checkedConvert(
        'theme',
        (v) => $enumDecode(_$UpdateProfileRequestThemeEnumEnumMap, v),
      ),
      notificationsEnabled: $checkedConvert(
        'notifications_enabled',
        (v) => v as bool,
      ),
      audioQuality: $checkedConvert(
        'audio_quality',
        (v) => $enumDecode(_$UpdateProfileRequestAudioQualityEnumEnumMap, v),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'notificationsEnabled': 'notifications_enabled',
    'audioQuality': 'audio_quality',
  },
);

Map<String, dynamic> _$UpdateProfileRequestToJson(
  UpdateProfileRequest instance,
) => <String, dynamic>{
  'pseudo': instance.pseudo,
  'bio': instance.bio,
  'theme': _$UpdateProfileRequestThemeEnumEnumMap[instance.theme]!,
  'notifications_enabled': instance.notificationsEnabled,
  'audio_quality':
      _$UpdateProfileRequestAudioQualityEnumEnumMap[instance.audioQuality]!,
};

const _$UpdateProfileRequestThemeEnumEnumMap = {
  UpdateProfileRequestThemeEnum.system: 'system',
  UpdateProfileRequestThemeEnum.light: 'light',
  UpdateProfileRequestThemeEnum.dark: 'dark',
};

const _$UpdateProfileRequestAudioQualityEnumEnumMap = {
  UpdateProfileRequestAudioQualityEnum.low: 'low',
  UpdateProfileRequestAudioQualityEnum.normal: 'normal',
  UpdateProfileRequestAudioQualityEnum.high: 'high',
};
