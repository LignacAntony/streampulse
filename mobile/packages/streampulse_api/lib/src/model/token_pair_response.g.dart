// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'token_pair_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TokenPairResponse _$TokenPairResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'TokenPairResponse',
      json,
      ($checkedConvert) {
        $checkKeys(json, requiredKeys: const ['access_token', 'refresh_token']);
        final val = TokenPairResponse(
          accessToken: $checkedConvert('access_token', (v) => v as String),
          refreshToken: $checkedConvert('refresh_token', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {
        'accessToken': 'access_token',
        'refreshToken': 'refresh_token',
      },
    );

Map<String, dynamic> _$TokenPairResponseToJson(TokenPairResponse instance) =>
    <String, dynamic>{
      'access_token': instance.accessToken,
      'refresh_token': instance.refreshToken,
    };
