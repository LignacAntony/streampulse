// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UserResponse _$UserResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate('UserResponse', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['id', 'email', 'username', 'role', 'created_at'],
      );
      final val = UserResponse(
        id: $checkedConvert('id', (v) => v as String),
        email: $checkedConvert('email', (v) => v as String),
        username: $checkedConvert('username', (v) => v as String),
        role: $checkedConvert('role', (v) => v as String),
        createdAt: $checkedConvert(
          'created_at',
          (v) => DateTime.parse(v as String),
        ),
      );
      return val;
    }, fieldKeyMap: const {'createdAt': 'created_at'});

Map<String, dynamic> _$UserResponseToJson(UserResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'email': instance.email,
      'username': instance.username,
      'role': instance.role,
      'created_at': instance.createdAt.toIso8601String(),
    };
