// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'refresh_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RefreshRequest _$RefreshRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('RefreshRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['refresh_token']);
      final val = RefreshRequest(
        refreshToken: $checkedConvert('refresh_token', (v) => v as String),
      );
      return val;
    }, fieldKeyMap: const {'refreshToken': 'refresh_token'});

Map<String, dynamic> _$RefreshRequestToJson(RefreshRequest instance) =>
    <String, dynamic>{'refresh_token': instance.refreshToken};
