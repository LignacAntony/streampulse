// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_user_list_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminUserListResponse _$AdminUserListResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('AdminUserListResponse', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['users', 'total']);
  final val = AdminUserListResponse(
    users: $checkedConvert(
      'users',
      (v) => (v as List<dynamic>)
          .map((e) => AdminUserResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    total: $checkedConvert('total', (v) => (v as num).toInt()),
  );
  return val;
});

Map<String, dynamic> _$AdminUserListResponseToJson(
  AdminUserListResponse instance,
) => <String, dynamic>{
  'users': instance.users.map((e) => e.toJson()).toList(),
  'total': instance.total,
};
