// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'logout_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LogoutRequest _$LogoutRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('LogoutRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['refresh_token']);
      final val = LogoutRequest(
        refreshToken: $checkedConvert('refresh_token', (v) => v as String),
      );
      return val;
    }, fieldKeyMap: const {'refreshToken': 'refresh_token'});

Map<String, dynamic> _$LogoutRequestToJson(LogoutRequest instance) =>
    <String, dynamic>{'refresh_token': instance.refreshToken};
