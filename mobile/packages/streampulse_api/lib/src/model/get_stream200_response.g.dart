// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'get_stream200_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GetStream200Response _$GetStream200ResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'GetStream200Response',
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
        'stream_key',
        'stream_source_url',
        'started_at',
        'ended_at',
        'created_at',
        'updated_at',
      ],
    );
    final val = GetStream200Response(
      id: $checkedConvert('id', (v) => v as String),
      userId: $checkedConvert('user_id', (v) => v as String),
      title: $checkedConvert('title', (v) => v as String),
      description: $checkedConvert('description', (v) => v as String?),
      category: $checkedConvert('category', (v) => v as String?),
      status: $checkedConvert(
        'status',
        (v) => $enumDecode(_$GetStream200ResponseStatusEnumEnumMap, v),
      ),
      isPublic: $checkedConvert('is_public', (v) => v as bool),
      streamKey: $checkedConvert('stream_key', (v) => v as String),
      streamSourceUrl: $checkedConvert('stream_source_url', (v) => v as String),
      startedAt: $checkedConvert(
        'started_at',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      endedAt: $checkedConvert(
        'ended_at',
        (v) => v == null ? null : DateTime.parse(v as String),
      ),
      createdAt: $checkedConvert(
        'created_at',
        (v) => DateTime.parse(v as String),
      ),
      updatedAt: $checkedConvert(
        'updated_at',
        (v) => DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'userId': 'user_id',
    'isPublic': 'is_public',
    'streamKey': 'stream_key',
    'streamSourceUrl': 'stream_source_url',
    'startedAt': 'started_at',
    'endedAt': 'ended_at',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
);

Map<String, dynamic> _$GetStream200ResponseToJson(
  GetStream200Response instance,
) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'title': instance.title,
  'description': instance.description,
  'category': instance.category,
  'status': _$GetStream200ResponseStatusEnumEnumMap[instance.status]!,
  'is_public': instance.isPublic,
  'stream_key': instance.streamKey,
  'stream_source_url': instance.streamSourceUrl,
  'started_at': instance.startedAt?.toIso8601String(),
  'ended_at': instance.endedAt?.toIso8601String(),
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
};

const _$GetStream200ResponseStatusEnumEnumMap = {
  GetStream200ResponseStatusEnum.idle: 'idle',
  GetStream200ResponseStatusEnum.live: 'live',
  GetStream200ResponseStatusEnum.ended: 'ended',
};
