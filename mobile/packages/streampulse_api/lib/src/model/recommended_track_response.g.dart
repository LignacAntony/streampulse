// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'recommended_track_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RecommendedTrackResponse _$RecommendedTrackResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('RecommendedTrackResponse', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const ['id', 'title', 'artist', 'duration_s', 'reason'],
  );
  final val = RecommendedTrackResponse(
    id: $checkedConvert('id', (v) => v as String),
    title: $checkedConvert('title', (v) => v as String),
    artist: $checkedConvert('artist', (v) => v as String?),
    durationS: $checkedConvert('duration_s', (v) => (v as num?)?.toInt()),
    reason: $checkedConvert('reason', (v) => v as String),
  );
  return val;
}, fieldKeyMap: const {'durationS': 'duration_s'});

Map<String, dynamic> _$RecommendedTrackResponseToJson(
  RecommendedTrackResponse instance,
) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'artist': instance.artist,
  'duration_s': instance.durationS,
  'reason': instance.reason,
};
