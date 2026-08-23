// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_global_banned_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminGlobalBannedUser _$AdminGlobalBannedUserFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'AdminGlobalBannedUser',
  json,
  ($checkedConvert) {
    $checkKeys(json, requiredKeys: const ['user_id', 'username', 'created_at']);
    final val = AdminGlobalBannedUser(
      userId: $checkedConvert('user_id', (v) => v as String),
      username: $checkedConvert('username', (v) => v as String),
      reason: $checkedConvert('reason', (v) => v as String?),
      createdAt: $checkedConvert(
        'created_at',
        (v) => DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {'userId': 'user_id', 'createdAt': 'created_at'},
);

Map<String, dynamic> _$AdminGlobalBannedUserToJson(
  AdminGlobalBannedUser instance,
) {
  final val = <String, dynamic>{
    'user_id': instance.userId,
    'username': instance.username,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('reason', instance.reason);
  val['created_at'] = instance.createdAt.toIso8601String();
  return val;
}
