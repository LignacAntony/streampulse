// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_chat_message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminChatMessage _$AdminChatMessageFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'AdminChatMessage',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'id',
            'stream_id',
            'username',
            'content',
            'created_at',
            'stream_title',
          ],
        );
        final val = AdminChatMessage(
          id: $checkedConvert('id', (v) => v as String),
          streamId: $checkedConvert('stream_id', (v) => v as String),
          username: $checkedConvert('username', (v) => v as String),
          content: $checkedConvert('content', (v) => v as String),
          createdAt: $checkedConvert(
            'created_at',
            (v) => DateTime.parse(v as String),
          ),
          streamTitle: $checkedConvert('stream_title', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {
        'streamId': 'stream_id',
        'createdAt': 'created_at',
        'streamTitle': 'stream_title',
      },
    );

Map<String, dynamic> _$AdminChatMessageToJson(AdminChatMessage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'stream_id': instance.streamId,
      'username': instance.username,
      'content': instance.content,
      'created_at': instance.createdAt.toIso8601String(),
      'stream_title': instance.streamTitle,
    };
