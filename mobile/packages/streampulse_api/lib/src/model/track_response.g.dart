// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TrackResponse _$TrackResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate('TrackResponse', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['id', 'title', 'artist', 'duration_s'],
      );
      final val = TrackResponse(
        id: $checkedConvert('id', (v) => v as String),
        title: $checkedConvert('title', (v) => v as String),
        artist: $checkedConvert('artist', (v) => v as String?),
        durationS: $checkedConvert('duration_s', (v) => (v as num?)?.toInt()),
      );
      return val;
    }, fieldKeyMap: const {'durationS': 'duration_s'});

Map<String, dynamic> _$TrackResponseToJson(TrackResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'artist': instance.artist,
      'duration_s': instance.durationS,
    };
