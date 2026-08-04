// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stream_stats_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StreamStatsResponse _$StreamStatsResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'StreamStatsResponse',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'stream_id',
            'status',
            'listeners',
            'peak_listeners',
            'duration_seconds',
          ],
        );
        final val = StreamStatsResponse(
          streamId: $checkedConvert('stream_id', (v) => v as String),
          status: $checkedConvert(
            'status',
            (v) => $enumDecode(_$StreamStatsResponseStatusEnumEnumMap, v),
          ),
          listeners: $checkedConvert('listeners', (v) => (v as num).toInt()),
          peakListeners: $checkedConvert(
            'peak_listeners',
            (v) => (v as num).toInt(),
          ),
          startedAt: $checkedConvert(
            'started_at',
            (v) => v == null ? null : DateTime.parse(v as String),
          ),
          durationSeconds: $checkedConvert(
            'duration_seconds',
            (v) => (v as num).toInt(),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'streamId': 'stream_id',
        'peakListeners': 'peak_listeners',
        'startedAt': 'started_at',
        'durationSeconds': 'duration_seconds',
      },
    );

Map<String, dynamic> _$StreamStatsResponseToJson(StreamStatsResponse instance) {
  final val = <String, dynamic>{
    'stream_id': instance.streamId,
    'status': _$StreamStatsResponseStatusEnumEnumMap[instance.status]!,
    'listeners': instance.listeners,
    'peak_listeners': instance.peakListeners,
  };

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('started_at', instance.startedAt?.toIso8601String());
  val['duration_seconds'] = instance.durationSeconds;
  return val;
}

const _$StreamStatsResponseStatusEnumEnumMap = {
  StreamStatsResponseStatusEnum.idle: 'idle',
  StreamStatsResponseStatusEnum.live: 'live',
  StreamStatsResponseStatusEnum.ended: 'ended',
};
