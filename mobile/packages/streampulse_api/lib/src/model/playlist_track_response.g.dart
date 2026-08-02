// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_track_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlaylistTrackResponse _$PlaylistTrackResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('PlaylistTrackResponse', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const ['id', 'title', 'artist', 'duration_s', 'position'],
  );
  final val = PlaylistTrackResponse(
    id: $checkedConvert('id', (v) => v as String),
    title: $checkedConvert('title', (v) => v as String),
    artist: $checkedConvert('artist', (v) => v as String?),
    durationS: $checkedConvert('duration_s', (v) => (v as num?)?.toInt()),
    position: $checkedConvert('position', (v) => (v as num).toInt()),
  );
  return val;
}, fieldKeyMap: const {'durationS': 'duration_s'});

Map<String, dynamic> _$PlaylistTrackResponseToJson(
  PlaylistTrackResponse instance,
) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'artist': instance.artist,
  'duration_s': instance.durationS,
  'position': instance.position,
};
