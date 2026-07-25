// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_stream_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminStreamResponse _$AdminStreamResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'AdminStreamResponse',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'id',
            'title',
            'is_public',
            'started_at',
            'user_id',
            'username',
          ],
        );
        final val = AdminStreamResponse(
          id: $checkedConvert('id', (v) => v as String),
          title: $checkedConvert('title', (v) => v as String),
          isPublic: $checkedConvert('is_public', (v) => v as bool),
          startedAt: $checkedConvert(
            'started_at',
            (v) => v == null ? null : DateTime.parse(v as String),
          ),
          userId: $checkedConvert('user_id', (v) => v as String),
          username: $checkedConvert('username', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {
        'isPublic': 'is_public',
        'startedAt': 'started_at',
        'userId': 'user_id',
      },
    );

Map<String, dynamic> _$AdminStreamResponseToJson(
  AdminStreamResponse instance,
) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'is_public': instance.isPublic,
  'started_at': instance.startedAt?.toIso8601String(),
  'user_id': instance.userId,
  'username': instance.username,
};
