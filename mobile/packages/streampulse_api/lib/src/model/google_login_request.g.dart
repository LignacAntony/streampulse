// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'google_login_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GoogleLoginRequest _$GoogleLoginRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('GoogleLoginRequest', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['id_token']);
      final val = GoogleLoginRequest(
        idToken: $checkedConvert('id_token', (v) => v as String),
      );
      return val;
    }, fieldKeyMap: const {'idToken': 'id_token'});

Map<String, dynamic> _$GoogleLoginRequestToJson(GoogleLoginRequest instance) =>
    <String, dynamic>{'id_token': instance.idToken};
