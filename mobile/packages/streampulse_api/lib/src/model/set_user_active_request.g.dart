// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'set_user_active_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SetUserActiveRequest _$SetUserActiveRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('SetUserActiveRequest', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['is_active']);
  final val = SetUserActiveRequest(
    isActive: $checkedConvert('is_active', (v) => v as bool),
  );
  return val;
}, fieldKeyMap: const {'isActive': 'is_active'});

Map<String, dynamic> _$SetUserActiveRequestToJson(
  SetUserActiveRequest instance,
) => <String, dynamic>{'is_active': instance.isActive};
