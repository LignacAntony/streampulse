// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stream_summary_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StreamSummaryResponse _$StreamSummaryResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'StreamSummaryResponse',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'id',
        'user_id',
        'title',
        'description',
        'category',
        'status',
        'is_public',
        'started_at',
        'created_at',
        'broadcaster_username',
      ],
    );
    final val = StreamSummaryResponse(
      id: $checkedConvert('id', (v) => v as String),
      userId: $checkedConvert('user_id', (v) => v as String),
      title: $checkedConvert('title', (v) => v as String),
      description: $checkedConvert('description', (v) => v as String?),
      category: $checkedConvert('category', (v) => v as String?),
      status: $checkedConvert(
        'status',
        (v) => $enumDecode(_$StreamSummaryResponseStatusEnumEnumMap, v),
      ),
      isPublic: $checkedConvert('is_public', (v) => v as bool),
      startedAt: $checkedConvert(
        'started_at',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      createdAt: $checkedConvert(
        'created_at',
        (v) => DateTime.parse(v as String),
      ),
      broadcasterUsername: $checkedConvert(
        'broadcaster_username',
        (v) => v as String,
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'userId': 'user_id',
    'isPublic': 'is_public',
    'startedAt': 'started_at',
    'createdAt': 'created_at',
    'broadcasterUsername': 'broadcaster_username',
  },
);

Map<String, dynamic> _$StreamSummaryResponseToJson(
  StreamSummaryResponse instance,
) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'title': instance.title,
  'description': instance.description,
  'category': instance.category,
  'status': _$StreamSummaryResponseStatusEnumEnumMap[instance.status]!,
  'is_public': instance.isPublic,
  'started_at': instance.startedAt?.toIso8601String(),
  'created_at': instance.createdAt.toIso8601String(),
  'broadcaster_username': instance.broadcasterUsername,
};

const _$StreamSummaryResponseStatusEnumEnumMap = {
  StreamSummaryResponseStatusEnum.idle: 'idle',
  StreamSummaryResponseStatusEnum.live: 'live',
  StreamSummaryResponseStatusEnum.ended: 'ended',
};
