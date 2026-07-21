// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_user_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminUserResponse _$AdminUserResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'AdminUserResponse',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'id',
            'email',
            'username',
            'role',
            'is_active',
            'created_at',
          ],
        );
        final val = AdminUserResponse(
          id: $checkedConvert('id', (v) => v as String),
          email: $checkedConvert('email', (v) => v as String),
          username: $checkedConvert('username', (v) => v as String),
          role: $checkedConvert(
            'role',
            (v) => $enumDecode(_$AdminUserResponseRoleEnumEnumMap, v),
          ),
          isActive: $checkedConvert('is_active', (v) => v as bool),
          createdAt: $checkedConvert(
            'created_at',
            (v) => DateTime.parse(v as String),
          ),
        );
        return val;
      },
      fieldKeyMap: const {'isActive': 'is_active', 'createdAt': 'created_at'},
    );

Map<String, dynamic> _$AdminUserResponseToJson(AdminUserResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'email': instance.email,
      'username': instance.username,
      'role': _$AdminUserResponseRoleEnumEnumMap[instance.role]!,
      'is_active': instance.isActive,
      'created_at': instance.createdAt.toIso8601String(),
    };

const _$AdminUserResponseRoleEnumEnumMap = {
  AdminUserResponseRoleEnum.anonymous: 'anonymous',
  AdminUserResponseRoleEnum.user: 'user',
  AdminUserResponseRoleEnum.broadcaster: 'broadcaster',
  AdminUserResponseRoleEnum.admin: 'admin',
};
