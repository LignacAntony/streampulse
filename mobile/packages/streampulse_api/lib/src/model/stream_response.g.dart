// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stream_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StreamResponse _$StreamResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'StreamResponse',
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
            'ended_at',
            'created_at',
            'updated_at',
          ],
        );
        final val = StreamResponse(
          id: $checkedConvert('id', (v) => v as String),
          userId: $checkedConvert('user_id', (v) => v as String),
          title: $checkedConvert('title', (v) => v as String),
          description: $checkedConvert('description', (v) => v as String?),
          category: $checkedConvert('category', (v) => v as String?),
          status: $checkedConvert(
            'status',
            (v) => $enumDecode(_$StreamResponseStatusEnumEnumMap, v),
          ),
          isPublic: $checkedConvert('is_public', (v) => v as bool),
          streamKey: $checkedConvert('stream_key', (v) => v as String?),
          streamSourceUrl: $checkedConvert(
            'stream_source_url',
            (v) => v as String?,
          ),
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
          listenerCount: $checkedConvert(
            'listener_count',
            (v) => (v as num?)?.toInt(),
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
        'listenerCount': 'listener_count',
      },
    );

Map<String, dynamic> _$StreamResponseToJson(StreamResponse instance) {
  final val = <String, dynamic>{
    'id': instance.id,
    'user_id': instance.userId,
    'title': instance.title,
    'description': instance.description,
    'category': instance.category,
    'status': _$StreamResponseStatusEnumEnumMap[instance.status]!,
    'is_public': instance.isPublic,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('stream_key', instance.streamKey);
  writeNotNull('stream_source_url', instance.streamSourceUrl);
  val['started_at'] = instance.startedAt?.toIso8601String();
  val['ended_at'] = instance.endedAt?.toIso8601String();
  val['created_at'] = instance.createdAt.toIso8601String();
  val['updated_at'] = instance.updatedAt.toIso8601String();
  writeNotNull('listener_count', instance.listenerCount);
  return val;
}

const _$StreamResponseStatusEnumEnumMap = {
  StreamResponseStatusEnum.idle: 'idle',
  StreamResponseStatusEnum.live: 'live',
  StreamResponseStatusEnum.ended: 'ended',
};
