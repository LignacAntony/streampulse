// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_banned_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ChatBannedUser _$ChatBannedUserFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'ChatBannedUser',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const ['user_id', 'username', 'created_at'],
        );
        final val = ChatBannedUser(
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

Map<String, dynamic> _$ChatBannedUserToJson(ChatBannedUser instance) {
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
